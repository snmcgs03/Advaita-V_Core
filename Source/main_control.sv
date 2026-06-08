module main_control (
    input logic [6:0] opcode,
    input  logic rs1_is_zero,
    input logic [31:20]inst,
    input  logic [2:0] fn3,
    output logic [1:0] memtoreg,
    output logic branch,mux_inp,memread,memwrite,alusrc,reg_write,
    output logic [2:0]aluop,
    output logic csr_we,is_mret,sw_trap
);

always @(*) begin
    // Default values
    branch = 0;
    memread = 0;
    memtoreg = 2'b11; 
    memwrite = 0;
    alusrc = 0;
    reg_write = 0;
    aluop = 3'b000;
    mux_inp = 1'b0;
    csr_we=0;
    is_mret=0;
    sw_trap =0;
    
    case (opcode)
        7'b0110011: // R-type
        begin
            branch = 0;
            memread = 0;
            memtoreg = 2'b00;
            memwrite = 0;
            alusrc = 0;
            reg_write = 1;
            aluop = 3'b000;
            mux_inp = 1'b0;
        end

        7'b0010011: // I-type
        begin 
            branch = 0;
            memread = 0;
            memtoreg = 2'b00;
            memwrite = 0;
            alusrc = 1;
            reg_write = 1;
            aluop = 3'b001;
            mux_inp = 1'b0;
        end

        7'b0000011: // Load
        begin
            branch = 0;
            memread = 1;
            memtoreg = 2'b01; 
            memwrite = 0;
            alusrc = 1;
            reg_write = 1;
            aluop = 3'b010;
            mux_inp = 1'b0;
        end

        7'b0100011: // Store
        begin
            branch = 0;
            memread = 0;
            memtoreg = 2'b11; 
            memwrite=1; 
            alusrc = 1; 
            reg_write = 0; 
            aluop = 3'b011; 
            mux_inp = 1'b0;
        end

        7'b1100011: // Branch
        begin
            branch = 1; 
            memread = 0; 
            memtoreg = 2'b00; 
            memwrite = 0; 
            alusrc = 0; 
            reg_write = 0; 
            aluop = 3'b100; 
            mux_inp = 1'b0;
        end

        7'b1101111: // JAL
        begin
            branch = 0; 
            memread = 0; 
            memtoreg = 2'b10; 
            memwrite = 0; 
            alusrc = 1; 
            reg_write = 1; 
            aluop = 3'b110;
            mux_inp = 1'b0; 
        end
        
         7'b1100111: // JALR
        begin
            branch = 0; 
            memread = 0; 
            memtoreg = 2'b10; 
            memwrite = 0; 
            alusrc = 1; 
            reg_write = 1; 
            aluop = 3'b001; 
            mux_inp = 1'b1;
        end

        // U-type instruction handling lui
        7'b0110111: 
        begin
            branch = 0; 
            memread = 0; 
            memtoreg = 2'b10; 
            memwrite = 0; 
            alusrc = 1; 
            reg_write = 1; 
            aluop = 3'b110; 
            mux_inp = 1'b0;
        end
        
         // U-type instruction handling auipc
        7'b0010111: 
        begin
            branch = 0; 
            memread = 0; 
            memtoreg = 2'b10; 
            memwrite = 0; 
            alusrc = 1; 
            reg_write = 1; 
            aluop = 3'b000; 
            mux_inp = 1'b0;
        end
        
        7'b1110011: begin 
                if (fn3 != 3'b000) begin
                    // CSR Instructions (CSRRW, CSRRS, CSRRC, etc.)
                    reg_write = 1;
                    memtoreg  = 2'b11; // Select CSR data
                    alusrc    = fn3[2]; // Use zimm if fn3[2] is high
                    
                    // Optimization: CSRRS/RC only write if RS1 is not x0
                    // CSRRW (fn3[1:0] == 01) always writes.
                    csr_we = (fn3[1:0] == 2'b01) || // CSRRW/CSRRWI always write
                            (fn3[1:0] != 2'b01 && !rs1_is_zero); // CSRRS/CSRRC only if rs1≠x0
                    aluop     = 3'b101; 
                end else begin
                    // Non-CSR Privileged Instructions
                    case (inst[31:20])
                        12'h000: sw_trap = 1; // ECALL
                        12'h001: sw_trap = 1; // EBREAK
                        12'h302: is_mret = 1; // MRET
                        12'h105: ;            // WFI (NOP in simple cores)
                        default: ;
                    endcase
                end
            end
        
        
        default: // Handle unspecified opcodes
        begin
            branch    = 0; 
            memread   = 0; 
            memwrite  = 0; 
            alusrc    = 0; 
            reg_write = 0; 
            aluop     = 3'b000; 
            memtoreg  = 2'b00; 
            csr_we    = 0; 
            is_mret   = 0;
            mux_inp   = 0;
            sw_trap   = 0;
         end
    endcase
end

endmodule