module data_mem(
    input  logic        clk,
    input  logic        mem_write,
    input  logic [31:0] addr,
    input  logic [31:0] write_data,
    input  logic [3:0]  byte_enable,
    output logic [31:0] read_data
);
    // A byte-addressable memory of 1024 bytes
    logic [7:0] mem [0:1023];

    always_ff @(posedge clk) begin
        if (mem_write) begin
            if (byte_enable[0]) mem[addr + 0] <= write_data[7:0];
            if (byte_enable[1]) mem[addr + 1] <= write_data[15:8];
            if (byte_enable[2]) mem[addr + 2] <= write_data[23:16];
            if (byte_enable[3]) mem[addr + 3] <= write_data[31:24];
        end
    end

    always_comb 
    begin
        if (!mem_write) 
        begin
            // When not writing, the memory outputs the data at the current address.
            read_data = {mem[addr + 3], mem[addr + 2], mem[addr + 1], mem[addr]};
        end else 
        begin           
            read_data = 32'hzzzzzzzz;
        end
    end
endmodule
