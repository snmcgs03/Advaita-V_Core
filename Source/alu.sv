// =============================================================================
// Operation encoding (alu_control → 5 bits):
//   00000  ADD          rs1 + rs2
//   00001  SUB          rs1 - rs2
//   00010  XOR          rs1 ^ rs2
//   00011  OR           rs1 | rs2
//   00100  AND          rs1 & rs2
//   00101  SLL          rs1 << rs2[4:0]
//   00110  SRL          rs1 >> rs2[4:0]       (logical)
//   00111  SRA          rs1 >>> rs2[4:0]      (arithmetic)
//   01000  SLT          (signed rs1 < signed rs2) ? 1 : 0
//   01001  SLTU         (unsigned rs1 < unsigned rs2) ? 1 : 0
//   01010  BEQ          zero = (rs1 == rs2)
//   01011  BNE          zero = (rs1 != rs2)
//   01100  BLT          zero = (signed rs1 < signed rs2)
//   01101  BGE          zero = (signed rs1 >= signed rs2)
//   01110  BLTU         zero = (unsigned rs1 < unsigned rs2)
//   01111  BGEU         zero = (unsigned rs1 >= unsigned rs2)
//   10000  CSRRW/CSRRWI new_csr = rs1_data  (rs2 for *I variants)
//   10001  CSRRS/CSRRSI new_csr = csr_data | rs1_data
//   10010  CSRRC/CSRRCI new_csr = csr_data & ~rs1_data
// =============================================================================

module alu #(
    parameter int DATA_WIDTH = 32
)(
    input  logic [4:0]            alu_control,
    input  logic [DATA_WIDTH-1:0] rs1_data,   // Operand A  (always rs1)
    input  logic [DATA_WIDTH-1:0] rs2_data,   // Operand B  (rs2 or immediate via mux)
    input  logic [DATA_WIDTH-1:0] csr_data,   // Current CSR value (for CSRRS/CSRRC)
    output logic [DATA_WIDTH-1:0] alu_out,    // Result → writeback / memory address
    output logic                  zero        // Branch condition flag → EX stage
);

    // Signed views of operands for arithmetic comparisons
    // signed' is standard SV; the explicit cast makes tool intent unambiguous.
    logic signed [DATA_WIDTH-1:0] rs1_signed;
    logic signed [DATA_WIDTH-1:0] rs2_signed;
    assign rs1_signed = $signed(rs1_data);
    assign rs2_signed = $signed(rs2_data);

    always_comb begin
        // Safe defaults — both outputs fully assigned in every path.
        alu_out = {DATA_WIDTH{1'b0}};
        zero    = 1'b0;

        unique case (alu_control)

            // ------------------------------------------------------------------
            // Arithmetic
            // ------------------------------------------------------------------
            5'b00000: alu_out = rs1_data + rs2_data;           // ADD / ADDI / LOAD / STORE / JALR addr
            5'b00001: alu_out = rs1_data - rs2_data;           // SUB

            // ------------------------------------------------------------------
            // Logical
            // ------------------------------------------------------------------
            5'b00010: alu_out = rs1_data ^ rs2_data;           // XOR  / XORI
            5'b00011: alu_out = rs1_data | rs2_data;           // OR   / ORI
            5'b00100: alu_out = rs1_data & rs2_data;           // AND  / ANDI

            // ------------------------------------------------------------------
            // Shifts  (only lower 5 bits of shift amount used — RV32I §2.6)
            // ------------------------------------------------------------------
            5'b00101: alu_out = rs1_data  <<  rs2_data[4:0];   // SLL / SLLI
            5'b00110: alu_out = rs1_data  >>  rs2_data[4:0];   // SRL / SRLI (logical)
            5'b00111: alu_out = rs1_signed >>> rs2_data[4:0];  // SRA / SRAI (arithmetic)

            // ------------------------------------------------------------------
            // Set-less-than comparisons (result is 0 or 1 in bit[0])
            // ------------------------------------------------------------------
            5'b01000: alu_out = (rs1_signed < rs2_signed)      // SLT / SLTI
                                ? 32'd1 : 32'd0;
            5'b01001: alu_out = (rs1_data < rs2_data)          // SLTU / SLTIU
                                ? 32'd1 : 32'd0;

            // ------------------------------------------------------------------
            // Branch comparisons — set 'zero' flag only; alu_out stays 0.
            // The EX stage ANDs 'zero' with 'branch' to produce and_out_ex.
            // ------------------------------------------------------------------
            5'b01010: zero = (rs1_data   == rs2_data);         // BEQ
            5'b01011: zero = (rs1_data   != rs2_data);         // BNE
            5'b01100: zero = (rs1_signed <  rs2_signed);       // BLT  (signed)
            5'b01101: zero = (rs1_signed >= rs2_signed);       // BGE  (signed)
            5'b01110: zero = (rs1_data   <  rs2_data);         // BLTU (unsigned)
            5'b01111: zero = (rs1_data   >= rs2_data);         // BGEU (unsigned)

            // ------------------------------------------------------------------
            // Zicsr atomic read-modify-write operations
            //
            // rs2_data carries the write source:
            //   Register variants (*RW/S/C)  : rs2_data = rs1 register value
            //                                  (alu_src=0, mux passes rs2 port)
            //   Immediate variants (*RWI/SI/CI): rs2_data = zero-extended uimm
            //                                  (alu_src=1, mux passes imm_out)
            //
            // The CSR bank receives alu_out as csr_wdata (the new CSR value).
            // The old value (csr_data) is read before the write and goes to rd
            // via the WB stage's memtoreg=2'b11 path.
            // ------------------------------------------------------------------
            5'b10000: alu_out = rs2_data;                      // CSRRW/CSRRWI: new = source
            5'b10001: alu_out = csr_data |  rs2_data;          // CSRRS/CSRRSI: set bits
            5'b10010: alu_out = csr_data & ~rs2_data;          // CSRRC/CSRRCI: clear bits

            // ------------------------------------------------------------------
            // Undefined control codes → safe zero output
            // ------------------------------------------------------------------
            default: begin
                alu_out = {DATA_WIDTH{1'b0}};
                zero    = 1'b0;
            end

        endcase
    end

endmodule