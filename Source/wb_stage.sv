module wb_stage(
    input  logic [31:0] mem_out,          // Data from Data Memory
    input  logic [31:0] alu_out,          // Data from ALU
    input  logic [31:0] csr_read_data,    // NEW: Data from CSR File
    input  logic [31:0] return_addr,      // PC + 4 (for JAL/JALR)
    input  logic [31:0] imm_out,          // For LUI (U-type)
    input  logic [31:0] pc_signed_offset, // For AUIPC (U-type)
    input  logic [1:0]  memtoreg,         // Selection from Main Control
    input  logic [6:0]  opcode_out_d,     // Instruction opcode for U-type sub-selection
    output logic [31:0] wb_data           // Final data to Register File
);

    // This internal variable handles the "Special" instructions (Jumps and U-types)
    // that all share the same 'memtoreg' select line (2'b10).
    logic [31:0] pre_wb_data;

    // --- Sub-selection Logic for Jumps and U-Types ---
    // Instead of a separate wb_control and wb_mux31, we use a single clean case statement.
    always_comb begin
        case (opcode_out_d)
            7'b1101111, 
            7'b1100111: pre_wb_data = return_addr;      // JAL / JALR (Write PC+4)
            7'b0110111: pre_wb_data = imm_out;          // LUI (Write Upper Imm)
            7'b0010111: pre_wb_data = pc_signed_offset; // AUIPC (Write PC + Upper Imm)
            default:    pre_wb_data = alu_out;
        endcase
    end

    // --- Final Write-Back Multiplexer ---
    // Based on the 'memtoreg' signal from your Main Control Unit.
    always_comb begin
        unique case (memtoreg)
            2'b00: wb_data = alu_out;          // Standard R-type / I-type ALU ops
            2'b01: wb_data = mem_out;          // Loads (LB, LH, LW, etc.)
            2'b10: wb_data = pre_wb_data;   // Jumps and U-Type instructions
            2'b11: wb_data = csr_read_data;    // Zicsr instructions (CSRRW, CSRRS, etc.)
            default: wb_data = alu_out;
        endcase
    end

endmodule