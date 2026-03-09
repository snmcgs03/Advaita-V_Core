`timescale 1ns/1ps

module riscv_core_with_mem(
    input  logic         clk,
    input  logic         reset,             // Asynchronous reset input
    input  logic [31:0]  write_inst,        // External instruction to load
    input  logic         inst_mem_write_en  // External write enable for IMEM
);

    // --- Internal Signals ---
    wire [31:0] instruction;
    wire [31:0] pc_address;
    wire [31:0] alu_out;
    wire [31:0] rs2_data;
    wire [31:0] raw_mem_read_data;
    wire [31:0] data_to_cpu_wb;
    wire [31:0] data_to_mem_write;
    wire        mem_write;
    wire        mem_read;        
    wire [3:0]  byte_enable;
    wire [2:0]  fn3;
    wire [6:0]  opcode;
    wire        sync_reset_w;

    // --- 1. Instruction Memory Control (Hardwired) ---
    // cs_n is active (0) when NOT in reset.
    // we_n is active (0) only when external loading is enabled.
    wire inst_cs_n = sync_reset_w; 
    wire inst_we_n = !inst_mem_write_en;

    // --- 2. Data Memory Control (Logic-Based) ---
    // cs_n is active (0) if the CPU is either Reading (Load) or Writing (Store).
    // we_n is active (0) only during Store instructions.
    wire data_cs_n = !(mem_read | mem_write);
    wire data_we_n = !mem_write;

    // --- Instantiations ---

    // Reset Synchronizer
    rst_sync reset_synchronizer_unit (
        .clk(clk),
        .reset(reset),
        .sync_reset(sync_reset_w)
    );  

    // Instruction Memory
    instruction_mem inst_mem (
        .clk(clk),
        .reset(sync_reset_w),
        .cs_n(inst_cs_n),
        .we_n(inst_we_n),
        .address(pc_address),
        .write_inst(write_inst),
        .instruction(instruction)
    );

    // CPU Core
    single_cycle_riscV cpu (
        .clk(clk),
        .reset(sync_reset_w),
        .instruction(instruction),
        .mem_out(data_to_cpu_wb),
        .rs2_data(rs2_data),
        .address(pc_address),
        .alu_out(alu_out),
        .mem_write(mem_write),
        .mem_read(mem_read),    
        .fn3(fn3),
        .opcode(opcode)
    );

    // Data Memory
    data_mem data_memory (
        .clk(clk),
        .cs_n(data_cs_n),
        .we_n(data_we_n),
        .addr({alu_out[31:2], 2'b00}),
        .write_data(data_to_mem_write),
        .byte_enable(byte_enable),
        .read_data(raw_mem_read_data)
    );
    
    // Memory Interface (Load/Store alignment)
    memory_interface mem_if (
        .opcode(opcode),
        .fn3(fn3),
        .cpu_store_data(rs2_data),
        .cpu_writeback_data(data_to_cpu_wb),
        .addr_lsb(alu_out[1:0]),
        .mem_read_data(raw_mem_read_data),
        .byte_enable(byte_enable),
        .mem_write_data(data_to_mem_write)
    );

endmodule
