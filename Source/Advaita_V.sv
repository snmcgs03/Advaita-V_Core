`timescale 1ns/1ps

module Advaita_V (
    input  logic        clk,
    input  logic        reset,
    input  logic [31:0] ext_write_inst,    
    input  logic        ext_inst_we,       
    input  logic [31:0] ext_interrupts,    
    
    output logic        trap_active_o,     
    output logic [31:0] mstatus_o,         
    output logic [31:0] pc_debug_o         
);

    // --- Internal Wires ---
    wire [31:0] instruction;
    wire [31:0] pc_address;
    wire [31:0] alu_result;
    wire [31:0] rs2_data;
    wire [31:0] cpu_mem_out;         // Combined read data from wrapper
    wire        mem_write_en;
    wire        mem_read_en;        
    wire [2:0]  instr_fn3;
    wire [6:0]  instr_opcode;
    
    wire [31:0] csr_rdata_wire; 
    wire [31:0] mtvec_target;
    wire [31:0] mepc_val;
    wire        csr_write_en;
  //  wire [2:0]  csr_op_type;
    wire [11:0] csr_address;
    
    wire        trap_detected;
    wire        is_mret_instr;
    wire [31:0] exc_cause;
    wire [31:0] exc_tval;
    wire [31:0] internal_mstatus;

    // --- Interrupt wires (Bug 1 fix) ---
    wire [31:0] mie_out_wire;        // MIE register value from CSR bank → CPU
    wire        interrupt_pending_wire; // Qualified interrupt flag from CSR bank → CPU

    wire        sync_rst_h; 
    wire        sync_rst_n; 

    // --- Global Assignments ---
    assign sync_rst_n    = !sync_rst_h;
    assign pc_debug_o    = pc_address;
    assign mstatus_o     = internal_mstatus;
    assign trap_active_o = trap_detected;

    // 1. Reset Synchronizer
    reset_sync i_reset_sync (
        .clk        (clk),
        .reset      (reset),
        .sync_reset (sync_rst_h)
    );  

    // 2. Instruction Memory
    inst_memory i_imem (
        .clk        (clk),
        .reset      (sync_rst_h),
        .cs_n       (1'b0),          
        .we_n       (!ext_inst_we),
        .address    (pc_address),
        .write_inst (ext_write_inst),
        .instruction(instruction)
    );

    // 3. CPU Core
    single_cycle_riscv i_cpu_core (
        .clk        (clk),
        .reset      (sync_rst_h),
        .instruction(instruction),
        .mem_out    (cpu_mem_out),   // Data coming from Memory Wrapper
        .rs2_data   (rs2_data),
        .address    (pc_address),
        .alu_out    (alu_result),
        .mem_write  (mem_write_en),
        .mem_read   (mem_read_en),    
        .fn3        (instr_fn3),
        .opcode     (instr_opcode),
        .csr_rdata  (csr_rdata_wire), 
        .mtvec      (mtvec_target),
        .mepc       (mepc_val),
        .csr_en              (csr_write_en),
        .trap_en             (trap_detected),
        .is_mret             (is_mret_instr),
        .trap_cause          (exc_cause),
        .trap_val            (exc_tval),
        .csr_addr            (csr_address),
        // Bug 1 fix: connect interrupt signals from CSR bank
        .mie_out             (mie_out_wire),
        .interrupt_pending   (interrupt_pending_wire)
    );

    // 4. CSR Bank
    csr_bank i_csr_bank (
        .clk        (clk),
        .rst_n      (sync_rst_n),
        .csr_addr   (csr_address),
        .csr_wdata  (alu_result),      
      //  .csr_op     (csr_op_type),
        .csr_en     (csr_write_en),
        .csr_rdata  (csr_rdata_wire), 
        .trap_en    (trap_detected),
        .is_mret    (is_mret_instr),
        .trap_pc    (pc_address),
        .trap_cause (exc_cause),
        .trap_val   (exc_tval),
        .ext_mip    (ext_interrupts),  
        .mtvec_out  (mtvec_target),
        .mepc_out   (mepc_val),
        .mstatus_out(internal_mstatus),
        // Bug 1 fix: drive CPU interrupt signals
        .mie_out            (mie_out_wire),
        .interrupt_pending  (interrupt_pending_wire)
    );

    // 5. Consolidated Data Memory Subsystem
    // This replaces BOTH the old data_mem and the datamem_interface
    data_mem_wrapper i_dmem_subsystem (
        .clk          (clk),
        .reset        (sync_rst_h),
        .addr         (alu_result),
        .write_data   (rs2_data),
        .mem_read_en  (mem_read_en),
        .mem_write_en (mem_write_en),
        .opcode       (instr_opcode),
        .fn3          (instr_fn3),
        .read_data_out(cpu_mem_out)
    );

endmodule