module alu_control (
    input  logic [2:0] alu_op,          // Operation class from main_control
    input  logic [2:0] fn3,             // funct3 field from instruction
    input  logic [6:0] imm11_5,         // instruction[31:25]: funct7 / shift qualifier
    input  logic       fn7_5,           // instruction[30]: SUB/SRA distinguish bit
    output logic [4:0] control_out      // 5-bit ALU operation select → alu
);

    always_comb begin
        control_out = 5'b00000;  // Default: ADD (safe for undefined paths)

        case (alu_op)

            // ------------------------------------------------------------------
            // R-type: fn3 selects operation; fn7_5 qualifies ADD→SUB, SRL→SRA
            // ------------------------------------------------------------------
            3'b000: begin
                case (fn3)
                    3'b000: control_out = fn7_5 ? 5'b00001 : 5'b00000; // SUB : ADD
                    3'b001: control_out = 5'b00101;                     // SLL
                    3'b010: control_out = 5'b01000;                     // SLT
                    3'b011: control_out = 5'b01001;                     // SLTU
                    3'b100: control_out = 5'b00010;                     // XOR
                    3'b101: control_out = fn7_5 ? 5'b00111 : 5'b00110; // SRA : SRL
                    3'b110: control_out = 5'b00011;                     // OR
                    3'b111: control_out = 5'b00100;                     // AND
                    default: control_out = 5'b00000;
                endcase
            end

            // ------------------------------------------------------------------
            // I-type ALU immediate: same fn3 map as R-type except:
            //   SUB has no I-type equivalent.
            //   SRAI/SRLI share fn3=101 — distinguished by imm11_5 (funct7 field):
            //     imm11_5 == 7'h20 (0100000) → SRAI
            //     imm11_5 == 7'h00 (0000000) → SRLI
            // ------------------------------------------------------------------
            3'b001: begin
                case (fn3)
                    3'b000: control_out = 5'b00000;                               // ADDI
                    3'b001: control_out = 5'b00101;                               // SLLI
                    3'b010: control_out = 5'b01000;                               // SLTI
                    3'b011: control_out = 5'b01001;                               // SLTIU
                    3'b100: control_out = 5'b00010;                               // XORI
                    3'b101: control_out = (imm11_5 == 7'h20) ? 5'b00111          // SRAI
                                                              : 5'b00110;         // SRLI
                    3'b110: control_out = 5'b00011;                               // ORI
                    3'b111: control_out = 5'b00100;                               // ANDI
                    default: control_out = 5'b00000;
                endcase
            end

            // ------------------------------------------------------------------
            // Load: effective address = rs1 + sign-extended-imm → ADD
            // ------------------------------------------------------------------
            3'b010: control_out = 5'b00000;  // ADD

            // ------------------------------------------------------------------
            // Store: effective address = rs1 + sign-extended-imm → ADD
            // ------------------------------------------------------------------
            3'b011: control_out = 5'b00000;  // ADD

            // ------------------------------------------------------------------
            // Branch: fn3 selects comparison type
            // ------------------------------------------------------------------
            3'b100: begin
                case (fn3)
                    3'b000: control_out = 5'b01010;   // BEQ
                    3'b001: control_out = 5'b01011;   // BNE
                    3'b100: control_out = 5'b01100;   // BLT  (signed)
                    3'b101: control_out = 5'b01101;   // BGE  (signed)
                    3'b110: control_out = 5'b01110;   // BLTU (unsigned)
                    3'b111: control_out = 5'b01111;   // BGEU (unsigned)
                    default: control_out = 5'b00000;  // fn3 2,3 undefined → ADD (illegal_instr traps)
                endcase
            end

            // ------------------------------------------------------------------
            // CSR Zicsr (§9.1): fn3 encodes the atomic operation.
            // Register variants (fn3[2]=0) and immediate variants (fn3[2]=1)
            // map to the same ALU operations — the operand difference (rs1 vs
            // uimm) is handled upstream by the alu_src mux in ex_stage.
            // ------------------------------------------------------------------
            3'b101: begin
                case (fn3)
                    3'b001, 3'b101: control_out = 5'b10000;  // CSRRW / CSRRWI
                    3'b010, 3'b110: control_out = 5'b10001;  // CSRRS / CSRRSI
                    3'b011, 3'b111: control_out = 5'b10010;  // CSRRC / CSRRCI
                    default:        control_out = 5'b00000;  // fn3=0 is SYSTEM, not CSR
                endcase
            end

            // ------------------------------------------------------------------
            // JAL / LUI path (aluop = 3'b110)
            // The ALU computes ADD but its output is NOT used for writeback:
            //   JAL  writeback: rd ← PC+4  (return_addr from IF stage)
            //   LUI  writeback: rd ← imm_out  (upper immediate direct from ID)
            // This path exists to give the ALU a defined operation and avoid
            // combinational X-propagation; the WB mux selects pre_wb_data instead.
            // ------------------------------------------------------------------
            3'b110: control_out = 5'b00000;  // ADD (result discarded by WB mux)

            // ------------------------------------------------------------------
            // Unused / reserved aluop codes → ADD (safe default)
            // ------------------------------------------------------------------
            default: control_out = 5'b00000;

        endcase
    end

endmodule