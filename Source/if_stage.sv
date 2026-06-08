module if_stage (
    input  logic        clk,
    input  logic        reset,          // Asynchronous active-high reset

    // Control inputs
    input  logic        stall,          // Freeze PC when high (future pipeline use)
    input  logic        and_out,        // Branch taken / JAL unconditional jump
    input  logic        trap_occurred,  // Synchronous exception or interrupt this cycle
    input  logic        is_mret_instr,  // MRET retiring this cycle

    // Target addresses
    input  logic [31:0] pc_signed_offset, // Branch / JAL / JALR computed target
    input  logic [31:0] mepc,             // Exception return address (from CSR bank)
    input  logic [31:0] mtvec,            // Trap vector register (BASE + MODE)
    input  logic [31:0] trap_cause,       // mcause value being written this cycle
                                          // bit[31]=1 → interrupt, bit[30:0]=code

    // Outputs
    output logic [31:0] address,          // Current PC (registered)
    output logic [31:0] pc_new            // PC + 4 (next sequential address)
);

    // =========================================================================
    // PC + 4 (sequential next address, also used as JAL/JALR return address)
    // =========================================================================
    assign pc_new = address + 32'd4;

    // =========================================================================
    // Vectored trap-target computation
    //
    // Always extract the aligned BASE from mtvec regardless of mode, then
    // conditionally add the interrupt offset.
    //
    // Interrupt offset = 4 × cause_code = {cause_code[29:0], 2'b00}
    // We use trap_cause[29:0] (not [30:0]) so the shift cannot overflow 32 bits.
    // M-mode cause codes max at 11 (MEI), so [29:0] is safe.
    // =========================================================================
    logic [31:0] mtvec_base;    // BASE with mode bits cleared
    logic [31:0] trap_target;   // Final entry point sent to the PC register

    assign mtvec_base = {mtvec[31:2], 2'b00};

    always_comb begin
        if (mtvec[1:0] == 2'b01 && trap_cause[31]) begin
            // Vectored mode AND this is an interrupt (mcause bit31 = 1)
            // Target = BASE + (4 × cause_code)
            trap_target = mtvec_base + {trap_cause[29:0], 2'b00};
        end else begin
            // Direct mode, OR vectored mode but exception (mcause bit31 = 0)
            // Spec §3.1.7: in vectored mode exceptions always go to BASE
            trap_target = mtvec_base;
        end
    end

    // =========================================================================
    // Next-PC priority mux
    //
    //   Priority   Signal           Source
    //   --------   ------           ------
    //     High      trap_occurred   trap_target  (Direct or Vectored)
    //               is_mret_instr   mepc
    //               and_out         pc_signed_offset
    //     Low       —               PC + 4
    // =========================================================================
    logic [31:0] pc_next;
    logic [1:0]  pc_sel;

    always_comb begin
        // Priority encoder
        if      (trap_occurred)   pc_sel = 2'b11;
        else if (is_mret_instr)   pc_sel = 2'b10;
        else if (and_out)         pc_sel = 2'b01;
        else                      pc_sel = 2'b00;

        // Mux
        unique case (pc_sel)
            2'b00:   pc_next = pc_new;            // Sequential
            2'b01:   pc_next = pc_signed_offset;  // Branch / JAL / JALR
            2'b10:   pc_next = mepc;              // MRET
            2'b11:   pc_next = trap_target;       // Trap entry (Direct or Vectored)
            default: pc_next = pc_new;
        endcase
    end

    // =========================================================================
    // PC register — synchronous load, asynchronous reset to 0x0
    // =========================================================================
    always_ff @(posedge clk or posedge reset) begin
        if (reset)
            address <= 32'h0000_0000;
        else if (!stall)
            address <= pc_next;
    end

endmodule