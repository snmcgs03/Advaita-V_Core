module single_cycle_riscv (
    input  logic        clk,
    input  logic        reset,

    // Instruction from instruction memory
    input  logic [31:0] instruction,

    // Data from data memory (load result)
    input  logic [31:0] mem_out,

    // -------------------------------------------------------------------------
    // CSR bank interface
    // -------------------------------------------------------------------------
    input  logic [31:0] mtvec,             // Trap vector  (BASE + MODE bits)
    input  logic [31:0] mepc,              // Exception return address
    input  logic [31:0] csr_rdata,         // Old CSR value (read-before-write to rd)
    input  logic [31:0] mie_out,           // Machine interrupt enable register
    input  logic        interrupt_pending, // (mstatus.MIE & mie & mip) from CSR bank

    output logic        csr_en,            // CSR instruction write enable
    output logic        trap_en,           // Exception or interrupt this cycle
    output logic        is_mret,           // MRET retiring this cycle
    output logic [31:0] trap_cause,        // Value to write into mcause
    output logic [31:0] trap_val,          // Value to write into mtval
    output logic [11:0] csr_addr,          // CSR address for read/write

    // -------------------------------------------------------------------------
    // Data memory interface
    // -------------------------------------------------------------------------
    output logic [31:0] rs2_data,          // Store data
    output logic [31:0] alu_out,           // Memory address (from ALU)
    output logic        mem_write,         // Write enable (gated on no trap)
    output logic        mem_read,          // Read  enable (gated on no trap)
    output logic [2:0]  fn3,              // Transfer width / sign select
    output logic [6:0]  opcode,           // Instruction opcode

    // Debug / monitoring
    output logic [31:0] address            // Current PC
);

    // =========================================================================
    // Internal interconnect
    // =========================================================================
    logic [31:0] rs1_data;          // Register file rs1 output
    logic [31:0] imm_out;           // Sign/zero extended immediate
    logic [31:0] return_addr;       // PC + 4  (JAL/JALR writeback value)
    logic [31:0] wb_data;           // Final writeback data to register file
    logic [31:0] pc_signed_offset;  // Branch/JAL/JALR computed target from EX

    logic        and_out_ex;        // Branch-taken or JAL unconditional flag
    logic        branch;            // Branch instruction flag from ID
    logic        alu_src;           // ALU operand-B mux select
    logic [1:0]  memtoreg;          // Writeback mux select
    logic [2:0]  aluop;             // ALU operation class
    logic        fn7_5;             // instruction[30] — SUB/SRA qualifier
    logic        mux_inp;           // JALR target select for EX stage

    logic [6:0]  fn7;               // instruction[31:25] — funct7 field
    logic [11:0] fn12;              // instruction[31:20] — funct12 / CSR addr
    logic [6:0]  imm11_5;           // instruction[31:25] — shift amount mask

    logic        sw_trap;           // ECALL / EBREAK from ID stage
    logic        mem_write_raw;     // mem_write before trap gating
    logic        mem_read_raw;      // mem_read  before trap gating

    // Exception flag signals
    logic        illegal_instr;
    logic        load_misaligned;
    logic        store_misaligned;
    logic        instr_misaligned;

    // Actual branch / jump target (JALR uses alu_out with bit-0 cleared)
    logic [31:0] actual_branch_target;

    // Interrupt cause encoding — which interrupt fired?
    logic [31:0] int_cause;

    // =========================================================================
    // Constant field extractions (independent of opcode)
    // fn7  is safe to always extract — used only when opcode==7'h33
    // fn12 is used for ECALL/EBREAK/MRET detection and CSR address
    // =========================================================================
    assign fn7  = instruction[31:25];
    assign fn12 = instruction[31:20];

    // =========================================================================
    // Memory enable gating — suppress access on any trap
    // =========================================================================
    assign mem_write = mem_write_raw && !trap_en;
    assign mem_read  = mem_read_raw  && !trap_en;

    // =========================================================================
    // Branch / JALR target computation
    //   JALR: alu_out (rs1+imm) with bit-0 forced to 0 (spec §2.5)
    //   Branch / JAL: pc_signed_offset (PC + sign-extended offset)
    // =========================================================================
    assign actual_branch_target = mux_inp ? {alu_out[31:1], 1'b0} : pc_signed_offset;

    // =========================================================================
    // Instruction-address misalignment detection
    // Triggered when a taken branch/jump targets a non-4-byte-aligned address.
    // Checked after bit-0 clear for JALR, so only bit[1] can still be set.
    // =========================================================================
    assign instr_misaligned =
        (and_out_ex || opcode == 7'h6F || opcode == 7'h67)
        && (actual_branch_target[1:0] != 2'b00);

    // =========================================================================
    // Illegal instruction detection
    //
    // Strategy: allow-list of valid opcodes + funct3 combinations.
    // Anything not in the list is illegal (mcause = 2).
    //
    // Validation depth per opcode:
    //   R-type  (0x33): funct7 must be 0x00 or 0x20
    //   I-ALU   (0x13): all 8 funct3 values valid (shifts checked via funct7
    //                   in alu_control — no need to duplicate here)
    //   Load    (0x03): only LB/LH/LW/LBU/LHU — fn3 3/6/7 are undefined
    //   Store   (0x23): only SB/SH/SW — fn3 3..7 are undefined
    //   Branch  (0x63): fn3 2 and 3 are undefined (no BLTEU/BGEU aliases)
    //   JALR    (0x67): fn3 must be 000
    //   SYSTEM  (0x73): fn3≠0 → CSR instructions; fn3=0 → privileged
    //   LUI/AUIPC/JAL/FENCE: opcode sufficient
    // =========================================================================
    assign illegal_instr = !(
        // U-type: LUI, AUIPC (no funct3)
        (opcode == 7'h37) ||
        (opcode == 7'h17) ||

        // J-type: JAL (no funct3)
        (opcode == 7'h6F) ||

        // JALR: funct3 must be 000
        (opcode == 7'h67 && fn3 == 3'h0) ||

        // Branch: valid funct3 = BEQ/BNE/BLT/BGE/BLTU/BGEU (0,1,4,5,6,7)
        (opcode == 7'h63 && fn3 inside {3'h0, 3'h1, 3'h4, 3'h5, 3'h6, 3'h7}) ||

        // Load: valid funct3 = LB/LH/LW/LBU/LHU (0,1,2,4,5)
        (opcode == 7'h03 && fn3 inside {3'h0, 3'h1, 3'h2, 3'h4, 3'h5}) ||

        // Store: valid funct3 = SB/SH/SW (0,1,2)
        (opcode == 7'h23 && fn3 inside {3'h0, 3'h1, 3'h2}) ||

        // I-type ALU: all 8 funct3 values are defined in RV32I
        (opcode == 7'h13) ||

        // R-type ALU: funct7 must be 0x00 (ADD,SLL,SLT,SLTU,XOR,SRL,OR,AND)
        //             or 0x20 (SUB, SRA)
        (opcode == 7'h33 && (fn7 == 7'h00 || fn7 == 7'h20)) ||

        // FENCE: opcode sufficient for RV32I (no fence.i in this core)
        (opcode == 7'h0F) ||

        // SYSTEM: CSR instructions (fn3 != 0) or valid privileged (fn3==0)
        (opcode == 7'h73 && fn3 != 3'h0) ||
        (opcode == 7'h73 && fn3 == 3'h0 &&
             fn12 inside {12'h000,   // ECALL
                          12'h001,   // EBREAK
                          12'h302,   // MRET
                          12'h105})  // WFI (treated as NOP)
    );

    // =========================================================================
    // Data alignment checks
    // Checked against alu_out (the effective byte address).
    // =========================================================================
    always_comb begin
        load_misaligned  = 1'b0;
        store_misaligned = 1'b0;

        // Loads
        if (opcode == 7'h03) begin
            case (fn3)
                3'h2:            if (alu_out[1:0] != 2'b00) load_misaligned = 1'b1; // LW
                3'h1, 3'h5:      if (alu_out[0])            load_misaligned = 1'b1; // LH/LHU
                default:         load_misaligned = 1'b0; // LB/LBU always aligned
            endcase
        end

        // Stores
        if (opcode == 7'h23) begin
            case (fn3)
                3'h2:            if (alu_out[1:0] != 2'b00) store_misaligned = 1'b1; // SW
                3'h1:            if (alu_out[0])             store_misaligned = 1'b1; // SH
                default:         store_misaligned = 1'b0; // SB always aligned
            endcase
        end
    end

    // =========================================================================
    // Interrupt cause encoding
    //
    // Priority within interrupts (Privileged ISA §3.7.1):
    //   MEI (Machine External Interrupt) — mcause 11 — highest
    //   MSI (Machine Software Interrupt) — mcause  3
    //   MTI (Machine Timer Interrupt)    — mcause  7 — lowest
    //
    // mie_out bit positions mirror the MIE CSR:
    //   [11] = MEIE, [7] = MTIE, [3] = MSIE
    //
    // trap_cause bit[31] = 1 signals an interrupt to mcause.
    // =========================================================================
    always_comb begin
        // Default: no interrupt
        int_cause = 32'h0;

        if (interrupt_pending) begin
            // mcause bit[31]=1 flags an interrupt; bits[30:0] hold the cause code.
            // Privileged ISA §3.1.15: mcause values for M-mode interrupts:
            //   MEI = 11  → mcause = 0x8000_000B
            //   MSI =  3  → mcause = 0x8000_0003
            //   MTI =  7  → mcause = 0x8000_0007
            if      (mie_out[11]) int_cause = {1'b1, 31'd11}; // MEI — highest priority
            else if (mie_out[3])  int_cause = {1'b1, 31'd3};  // MSI
            else if (mie_out[7])  int_cause = {1'b1, 31'd7};  // MTI — lowest priority
        end
    end

    // =========================================================================
    // Consolidated priority trap handler
    //
    // Priority (Privileged ISA §3.7 + §3.1.14):
    //   Synchronous exceptions take priority over interrupts within a cycle.
    //   Within synchronous exceptions:
    //     1. Illegal instruction       (mcause 2)
    //     2. Instr-address misaligned  (mcause 0)
    //     3. ECALL                     (mcause 11)
    //     4. EBREAK                    (mcause 3)
    //     5. Load-address misaligned   (mcause 4)
    //     6. Store-address misaligned  (mcause 6)
    //     7. Interrupt (pending)       (mcause bit31=1, code 11/3/7)
    //
    // trap_en → CSR bank latches mepc/mcause/mtval and updates mstatus
    // trap_en → IF stage jumps to mtvec (Direct or Vectored)
    // trap_en → mem_write/mem_read suppressed (faulting instr never touches mem)
    // trap_en → gated_reg_write suppressed in ID stage (no rd update)
    // =========================================================================
    always_comb begin
        // Safe defaults
        trap_en    = 1'b0;
        trap_cause = 32'h0;
        trap_val   = 32'h0;

        if (illegal_instr) begin
            // mcause = 2: Illegal Instruction
            // mtval  = faulting instruction word (spec §3.2.1)
            trap_en    = 1'b1;
            trap_cause = 32'd2;
            trap_val   = instruction;

        end else if (instr_misaligned) begin
            // mcause = 0: Instruction Address Misaligned
            // mtval  = target address that was misaligned (spec §3.2.1)
            trap_en    = 1'b1;
            trap_cause = 32'd0;
            trap_val   = actual_branch_target;  // Fixed: was pc_signed_offset

        end else if (sw_trap) begin
            // ECALL: mcause = 11 (from M-mode), mtval = 0
            // EBREAK: mcause = 3, mtval = PC of EBREAK instruction
            trap_en    = 1'b1;
            if (fn12 == 12'h000) begin
                trap_cause = 32'd11;   // ECALL from M-mode
                trap_val   = 32'd0;
            end else begin
                trap_cause = 32'd3;    // EBREAK
                trap_val   = address;  // PC of the EBREAK instruction
            end

        end else if (load_misaligned) begin
            // mcause = 4: Load Address Misaligned
            // mtval  = effective byte address (spec §3.2.1)
            trap_en    = 1'b1;
            trap_cause = 32'd4;
            trap_val   = alu_out;

        end else if (store_misaligned) begin
            // mcause = 6: Store/AMO Address Misaligned
            // mtval  = effective byte address
            trap_en    = 1'b1;
            trap_cause = 32'd6;
            trap_val   = alu_out;

        end else if (interrupt_pending) begin
            // Interrupt: lowest priority — only taken when no sync exception.
            // mcause bit[31]=1 signals interrupt to hardware.
            // mtval  = 0 for all standard M-mode interrupts.
            // The IF stage uses trap_cause[31] to select vectored vs direct.
            trap_en    = 1'b1;
            trap_cause = int_cause;
            trap_val   = 32'd0;
        end
    end

    // =========================================================================
    // Stage instantiations
    // =========================================================================

    // --- 1. Instruction Fetch ---
    if_stage if_st (
        .clk              (clk),
        .reset            (reset),
        .stall            (1'b0),           // No stall in single-cycle
        .and_out          (and_out_ex),
        .pc_signed_offset (pc_signed_offset),
        .mepc             (mepc),
        .mtvec            (mtvec),
        .trap_cause       (trap_cause),     // For vectored interrupt dispatch
        .trap_occurred    (trap_en),
        .is_mret_instr    (is_mret),
        .address          (address),
        .pc_new           (return_addr)     // PC+4 → JAL/JALR writeback
    );

    // --- 2. Instruction Decode + Register File ---
    id_stage id_st (
        .clk              (clk),
        .reset            (reset),
        .instruction      (instruction),
        .wb_data          (wb_data),
        .rs1_data         (rs1_data),
        .rs2_data         (rs2_data),
        .imm_out          (imm_out),
        .opcode_out_d     (opcode),
        .imm11_5          (imm11_5),
        .fn3_out_d        (fn3),
        .fn7_5            (fn7_5),
        .aluop            (aluop),
        .memtoreg         (memtoreg),
        .branch           (branch),
        .mem_write        (mem_write_raw),
        .mem_read         (mem_read_raw),
        .alu_src          (alu_src),
        .mux_inp          (mux_inp),
        .csr_we           (csr_en),
        .is_mret          (is_mret),
        .sw_trap          (sw_trap),
        .csr_addr         (csr_addr),
        .trap_en          (trap_en)         // Gates gated_reg_write in ID
    );

    // --- 3. Execute (ALU + branch resolver) ---
    ex_stage ex_st (
        .rs1_data         (rs1_data),
        .rs2_data         (rs2_data),
        .imm_out          (imm_out),
        .address          (address),
        .csr_read_data    (csr_rdata),
        .branch           (branch),
        .alu_src          (alu_src),
        .fn7_5            (fn7_5),
        .mux_inp          (mux_inp),
        .fn3              (fn3),
        .imm11_5          (imm11_5),        // Shift-amount / funct7 field
        .aluop            (aluop),
        .opcode           (opcode),         // Fixed: was opcode_out_d (port mismatch)
        .and_out_ex       (and_out_ex),
        .alu_out          (alu_out),
        .pc_ex_out        (pc_signed_offset)
    );

    // --- 4. Write-Back mux ---
    wb_stage wb_st (
        .mem_out          (mem_out),
        .alu_out          (alu_out),
        .csr_read_data    (csr_rdata),
        .return_addr      (return_addr),      // PC+4  for JAL/JALR
        .imm_out          (imm_out),          // Upper-imm for LUI
        .pc_signed_offset (pc_signed_offset), // PC+imm for AUIPC
        .memtoreg         (memtoreg),
        .opcode_out_d     (opcode),
        .wb_data          (wb_data)
    );

endmodule