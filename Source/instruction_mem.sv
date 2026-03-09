module instruction_mem (
    input  logic        clk,
    input  logic        reset,
    input  logic        cs_n,       // Active Low Chip Select
    input  logic        we_n,       // Active Low Write Enable
    input  logic [31:0] address,
    input  logic [31:0] write_inst,
    output logic [31:0] instruction
);

    // 1MB Memory: 2^20 entries of 8 bits (byte-addressable)
    logic [7:0] mem [0:1048575];

    // Synchronous Write Logic (Program Loading)
    // Only happens if Chip is Selected AND Write is Enabled (cs_n=0, we_n=0)
    always_ff @(posedge clk) begin
        if (!cs_n && !we_n) begin
            // Ensure address is within 1MB range and word-aligned
            if (address <= 1048572 && (address[1:0] == 2'b00)) begin 
                mem[address + 0] <= write_inst[7:0];
                mem[address + 1] <= write_inst[15:8];
                mem[address + 2] <= write_inst[23:16];
                mem[address + 3] <= write_inst[31:24];
            end
        end
    end

    // Sequential Read Logic (Instruction Fetch)
    // Only happens if Chip is Selected AND Write is NOT Enabled (cs_n=0, we_n=1)
    always_ff @(posedge clk) begin
        if (reset) begin
            instruction <= 32'h00000013; // RISC-V NOP (addi x0, x0, 0)
        end
        else if (!cs_n && we_n) begin
            if (address <= 1048572 && (address[1:0] == 2'b00)) begin
                instruction <= { mem[address + 3], 
                                 mem[address + 2], 
                                 mem[address + 1], 
                                 mem[address + 0] };
            end
            else begin
                instruction <= 32'h00000013; // NOP on out-of-bounds
            end
        end
        else begin
            // If not selected, maintain a safe state (usually last instruction or NOP)
            instruction <= 32'h00000013; 
        end
    end

endmodule
