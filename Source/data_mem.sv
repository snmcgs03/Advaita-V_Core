module data_mem(
    input  logic        clk,
    input  logic        cs_n,         // Chip Select (Active Low)
    input  logic        we_n,         // Write Enable (Active Low)
    input  logic [31:0] addr,         // Address from ALU
    input  logic [31:0] write_data,   // Data from rs2
    input  logic [3:0]  byte_enable,  // Mask for SB, SH, SW
    output logic [31:0] read_data     // Data to Writeback
);
    // 1MB Memory: 2^20 bytes
    // 1,048,576 entries of 8-bits
    logic [7:0] mem [0:1048575];

    // --- Synchronous Write Logic ---
    // Occurs only if the chip is selected (cs_n=0) AND write is enabled (we_n=0)
    always_ff @(posedge clk) begin
        if (!cs_n && !we_n) begin
            // Safety check to prevent out-of-bounds memory access
            if (addr <= 1048572) begin
                if (byte_enable[0]) mem[addr + 0] <= write_data[7:0];
                if (byte_enable[1]) mem[addr + 1] <= write_data[15:8];
                if (byte_enable[2]) mem[addr + 2] <= write_data[23:16];
                if (byte_enable[3]) mem[addr + 3] <= write_data[31:24];
            end
        end
    end

    // --- Combinational Read Logic ---
    // Industry standard: Only drive the bus if chip is selected and we are NOT writing
    always_comb begin
        if (!cs_n && we_n) begin
            if (addr <= 1048572) begin
                read_data = {mem[addr + 3], mem[addr + 2], mem[addr + 1], mem[addr]};
            end else begin
                read_data = 32'h0; // Return zero for out-of-bounds read
            end
        end else begin
            // Drive 0 or Z when idle to save power and simplify debugging
            read_data = 32'hzzzzzzzz; 
        end
    end
endmodule
