module alu #(
    parameter DATA_WIDTH = 32
)(
    input  logic [3:0]            alu_control,
    input  logic [DATA_WIDTH-1:0] rs1_data,   // rs1 / Operand A
    input  logic [DATA_WIDTH-1:0] rs2_data,   // rs2 or Immediate / Operand B
    output logic [DATA_WIDTH-1:0] alu_out,
    output logic                  zero
);

    wire signed [DATA_WIDTH-1:0] rss1_data = signed'(rs1_data);
    wire signed [DATA_WIDTH-1:0] rss2_data = signed'(rs2_data);

    always_comb begin
        zero    = 1'b0;
        alu_out = {DATA_WIDTH{1'b0}};

        case(alu_control)
            // ==========================================================
            // ARITHMETIC OPERATIONS
            // ==========================================================
            4'b0000: begin 
                // Handles: ADD (R-type), ADDI (I-type), 
                // Also: LW, SW, JALR, AUIPC (address calculation)
                alu_out = rs1_data + rs2_data; 
            end

            4'b0001: begin 
                // Handles: SUB (R-type)
                alu_out = rs1_data - rs2_data;
            end

            // ==========================================================
            // LOGICAL OPERATIONS
            // ==========================================================
            4'b0010: alu_out = rs1_data ^ rs2_data; // XOR, XORI
            4'b0011: alu_out = rs1_data | rs2_data; // OR, ORI
            4'b0100: alu_out = rs1_data & rs2_data; // AND, ANDI

            // ==========================================================
            // SHIFT OPERATIONS
            // ==========================================================
            4'b0101: alu_out = rs1_data << rs2_data[4:0];   // SLL, SLLI
            4'b0110: alu_out = rs1_data >> rs2_data[4:0];   // SRL, SRLI
            4'b0111: alu_out = rss1_data >>> rs2_data[4:0]; // SRA, SRAI

            // ==========================================================
            // COMPARISON OPERATIONS
            // ==========================================================
            4'b1000: alu_out = (rss1_data < rss2_data) ? 1 : 0; // SLT, SLTI
            4'b1001: alu_out = (rs1_data < rs2_data)   ? 1 : 0; // SLTU, SLTIU

            // ==========================================================
            // BRANCH COMPARISONS (Sets 'zero' flag for Control Unit)
            // ==========================================================
            4'b1010: zero = (rs1_data == rs2_data);            // BEQ
            4'b1011: zero = (rs1_data != rs2_data);            // BNE
            4'b1100: zero = (rss1_data <  rss2_data);          // BLT
            4'b1101: zero = (rss1_data >= rss2_data);          // BGE
            4'b1110: zero = (rs1_data <  rs2_data);            // BLTU
            4'b1111: zero = (rs1_data >= rs2_data);            // BGEU

            default: begin
                alu_out = {DATA_WIDTH{1'b0}};
                zero    = 1'b0;
            end
        endcase
    end
endmodule
