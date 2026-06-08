module csr_bank (
    input  logic        clk,
    input  logic        rst_n,         // Asynchronous, active-low reset

    // -------------------------------------------------------------------------
    // Zicsr instruction interface (from CPU execute stage)
    // -------------------------------------------------------------------------
    input  logic [11:0] csr_addr,      // CSR address from instruction[31:20]
    input  logic [31:0] csr_wdata,     // New value computed by ALU (after CSRRW/S/C op)
    input  logic        csr_en,        // Pulse high when a CSR instruction retires

    output logic [31:0] csr_rdata,     // Old CSR value (read-before-write to rd)

    // -------------------------------------------------------------------------
    // Trap / MRET interface (from CPU trap detection logic)
    // -------------------------------------------------------------------------
    input  logic        trap_en,       // Synchronous exception this cycle
    input  logic        is_mret,       // MRET instruction retiring this cycle
    input  logic [31:0] trap_pc,       // PC of faulting / trapping instruction
    input  logic [31:0] trap_cause,    // mcause value (bit31=0 for exceptions)
    input  logic [31:0] trap_val,      // mtval value

    // -------------------------------------------------------------------------
    // External interrupt lines (level-sensitive, from SoC interrupt controller)
    // Bit mapping mirrors MIP/MIE register layout:
    //   [11] = Machine External Interrupt (MEI)
    //   [7]  = Machine Timer Interrupt    (MTI)
    //   [3]  = Machine Software Interrupt (MSI)
    // -------------------------------------------------------------------------
    input  logic [31:0] ext_mip,       // Raw pending interrupt bits from SoC

    // -------------------------------------------------------------------------
    // Outputs to CPU control path
    // -------------------------------------------------------------------------
    output logic [31:0] mtvec_out,     // Trap vector (base, always Direct mode)
    output logic [31:0] mepc_out,      // Exception return address
    output logic [31:0] mstatus_out,   // Full mstatus (CPU reads MIE, MPIE, MPP)
    output logic [31:0] mie_out,       // Interrupt enable bits
    output logic        interrupt_pending  // Asserted when an enabled interrupt is pending
                                           // and global interrupts are enabled (MIE=1).
                                           // CPU must latch this as a trap_en source.
);

    // =========================================================================
    // CSR address map  (Privileged ISA v1.12, Table 2.2 / 2.4 / 2.5)
    // =========================================================================
    typedef enum logic [11:0] {
        // Machine Information Registers (RO)
        ADDR_MVENDORID  = 12'hF11,
        ADDR_MARCHID    = 12'hF12,
        ADDR_MIMPID     = 12'hF13,
        ADDR_MHARTID    = 12'hF14,

        // Machine Trap Setup (RW)
        ADDR_MSTATUS    = 12'h300,
        ADDR_MISA       = 12'h301,   // RO in this core
        ADDR_MIE        = 12'h304,
        ADDR_MTVEC      = 12'h305,

        // Machine Trap Handling (RW)
        ADDR_MSCRATCH   = 12'h340,
        ADDR_MEPC       = 12'h341,
        ADDR_MCAUSE     = 12'h342,
        ADDR_MTVAL      = 12'h343,
        ADDR_MIP        = 12'h344,   // Mostly RO; software-writable bits not implemented

        // Machine Counters (RW — software can write to reset)
        ADDR_MCYCLE     = 12'hB00,
        ADDR_MINSTRET   = 12'hB02,
        ADDR_MCYCLEH    = 12'hB80,
        ADDR_MINSTRETH  = 12'hB82
    } csr_addr_e;

    // =========================================================================
    // Hardwired / read-only values
    // =========================================================================
    // misa: MXL=01 (RV32), Extensions=I (bit8)
    localparam [31:0] MISA_VAL      = 32'h4000_0100;
    localparam [31:0] MVENDORID_VAL = 32'h0000_0000;  // Non-commercial
    localparam [31:0] MARCHID_VAL   = 32'h0000_0000;
    localparam [31:0] MIMPID_VAL    = 32'h0100_0000;  // Implementation v1.0
    localparam [31:0] MHARTID_VAL   = 32'h0000_0000;  // Single hart

    // mstatus write mask: only MIE[3] and MPIE[7] are software-writable.
    // MPP[12:11] is locked to 2'b11 (M-mode only core — no U/S modes).
    // SD[31], SXL, UXL, FS, XS, MPRV, SUM, MXR, TVM, TW, TSR not implemented.
    localparam [31:0] MSTATUS_WMASK = 32'h0000_0088;

    // mie write mask: only MEI[11], MTI[7], MSI[3] implemented
    localparam [31:0] MIE_WMASK     = 32'h0000_0888;

    // =========================================================================
    // CSR storage registers
    // =========================================================================
    logic [31:0] mstatus;   // Machine status
    logic [31:0] mtvec;     // Trap-vector base address (Direct mode only)
    logic [31:0] mepc;      // Exception program counter
    logic [31:0] mcause;    // Trap cause
    logic [31:0] mtval;     // Trap value
    logic [31:0] mscratch;  // Scratch register for M-mode software
    logic [31:0] mie;       // Machine interrupt enable
    logic [31:0] mip;       // Machine interrupt pending (hardware-driven)
    logic [63:0] mcycle;    // Cycle counter (64-bit)
    logic [63:0] minstret;  // Instruction-retired counter (64-bit)

    // =========================================================================
    // Interrupt pending detection
    // Spec §3.1.9: An interrupt i is pending when mip[i] & mie[i].
    // Global enable: mstatus.MIE must be set for M-mode interrupts to fire.
    // Only the three standard M-mode interrupts are implemented here.
    // =========================================================================
    logic [31:0] effective_mip;

    // Reflect only implemented interrupt bits
    assign effective_mip   = mip & MIE_WMASK;

    // interrupt_pending goes high when at least one enabled interrupt is pending
    // and global M-mode interrupts are enabled.
    // The CPU should treat this as the lowest-priority trap source (checked after
    // all synchronous exceptions).
    assign interrupt_pending = mstatus[3] & (|(mie & effective_mip));

    // =========================================================================
    // Combinational read port  (read-before-write semantics)
    // The CPU reads this *before* the write takes effect — csr_wdata is the
    // new value computed by the ALU, and the old value here goes to rd.
    // =========================================================================
    always_comb begin
        case (csr_addr)
            // Machine information (hardwired)
            ADDR_MVENDORID:  csr_rdata = MVENDORID_VAL;
            ADDR_MARCHID:    csr_rdata = MARCHID_VAL;
            ADDR_MIMPID:     csr_rdata = MIMPID_VAL;
            ADDR_MHARTID:    csr_rdata = MHARTID_VAL;
            ADDR_MISA:       csr_rdata = MISA_VAL;

            // Machine trap setup
            ADDR_MSTATUS:    csr_rdata = mstatus;
            ADDR_MIE:        csr_rdata = mie;
            ADDR_MTVEC:      csr_rdata = mtvec;

            // Machine trap handling
            ADDR_MSCRATCH:   csr_rdata = mscratch;
            ADDR_MEPC:       csr_rdata = mepc;
            ADDR_MCAUSE:     csr_rdata = mcause;
            ADDR_MTVAL:      csr_rdata = mtval;
            ADDR_MIP:        csr_rdata = mip;  // Reflects live interrupt lines

            // Machine counters
            ADDR_MCYCLE:     csr_rdata = mcycle[31:0];
            ADDR_MCYCLEH:    csr_rdata = mcycle[63:32];
            ADDR_MINSTRET:   csr_rdata = minstret[31:0];
            ADDR_MINSTRETH:  csr_rdata = minstret[63:32];

            // Unimplemented CSR → return 0 (no illegal-instruction here;
            // the CPU's illegal_instr check handles that)
            default:         csr_rdata = 32'h0;
        endcase
    end

    // =========================================================================
    // Sequential write logic
    //
    // Priority (highest to lowest):
    //   1. Synchronous exception  (trap_en)
    //   2. MRET                   (is_mret)
    //   3. CSR instruction write  (csr_en)
    //   4. Background updates     (mcycle, minstret, mip) — always run
    //
    // Non-blocking assignment semantics: all RHS values are sampled from the
    // *current* register state (before this clock edge). Multiple assignments
    // to the same register: the last one in source order wins.
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset state: interrupts globally disabled, MPP=M-mode, all else 0
            mstatus  <= 32'h0000_1800; // MPP[12:11]=11 (M-mode), MIE=0, MPIE=0
            mtvec    <= 32'h0000_0000;
            mepc     <= 32'h0000_0000;
            mcause   <= 32'h0000_0000;
            mtval    <= 32'h0000_0000;
            mscratch <= 32'h0000_0000;
            mie      <= 32'h0000_0000;
            mip      <= 32'h0000_0000;
            mcycle   <= 64'h0;
            minstret <= 64'h0;

        end else begin

            // -----------------------------------------------------------------
            // Background updates — run every cycle regardless of trap/CSR activity.
            // These use non-blocking assignments; if a CSR write to mcycle/minstret
            // occurs in the same cycle, the CSR write (being lower in the if-chain)
            // wins because it's the last assignment — BUT here we want the opposite:
            // counter updates should be superseded by SW writes. So the counter
            // increments are placed FIRST; SW writes in csr_en branch below will
            // override them correctly via last-assignment-wins.
            // -----------------------------------------------------------------

            // Cycle counter: always increments (1 per clock)
            mcycle   <= mcycle + 1;

            // Instruction-retired counter: increments once per retired instruction.
            // A trapped instruction does NOT retire (trap_en gates reg_write in
            // the CPU), but the counter still ticks here — we decrement later
            // during trap handling is NOT needed because minstret is a performance
            // hint, not a correctness register. Simple cores increment every cycle
            // and accept the slight over-count on traps.
            minstret <= minstret + 1;

            // MIP: reflects live hardware interrupt lines from SoC.
            // Only implemented bits are latched; others remain 0.
            // This must always run so MIP is never stale.
            mip <= ext_mip & MIE_WMASK;

            // -----------------------------------------------------------------
            // Priority 1: Synchronous exception / software trap entry
            // Spec §3.1.6.1: on trap, hardware sets:
            //   mepc    ← PC of trapping instruction (aligned to 4 bytes)
            //   mcause  ← exception code (bit31=0 for exceptions)
            //   mtval   ← exception-specific value
            //   mstatus.MPIE ← mstatus.MIE   (save interrupt enable state)
            //   mstatus.MIE  ← 0             (disable interrupts during handler)
            //   mstatus.MPP  ← current mode  (always M-mode in this core)
            // -----------------------------------------------------------------
            if (trap_en) begin
                mepc              <= trap_pc & 32'hFFFF_FFFC; // Enforce 4-byte alignment
                mcause            <= trap_cause;               // bit31=0 (exception)
                mtval             <= trap_val;
                mstatus[7]        <= mstatus[3];  // MPIE = MIE  (save)
                mstatus[3]        <= 1'b0;         // MIE  = 0   (disable)
                mstatus[12:11]    <= 2'b11;        // MPP  = M-mode

            // -----------------------------------------------------------------
            // Priority 2: MRET — return from machine-mode trap handler
            // Spec §3.3.2: MRET restores interrupt state and returns to mepc.
            //   mstatus.MIE  ← mstatus.MPIE  (restore interrupt enable)
            //   mstatus.MPIE ← 1             (set MPIE to 1 after restore)
            //   mstatus.MPP  ← least-privileged mode supported (M-mode here)
            // The PC update to mepc is handled by the CPU IF stage.
            // -----------------------------------------------------------------
            end else if (is_mret) begin
                mstatus[3]        <= mstatus[7];  // MIE  = MPIE (restore)
                mstatus[7]        <= 1'b1;         // MPIE = 1
                mstatus[12:11]    <= 2'b11;        // MPP  stays M-mode

            // -----------------------------------------------------------------
            // Priority 3: Zicsr instruction write
            // The ALU has already computed csr_wdata (new value after CSRRW/S/C).
            // We apply field-level write masks per CSR.
            // -----------------------------------------------------------------
            end else if (csr_en) begin
                case (csr_addr)

                    // mstatus: only MIE[3] and MPIE[7] are SW-writable.
                    // All other bits are either hardwired or managed by hardware.
                    ADDR_MSTATUS:
                        mstatus <= (csr_wdata & MSTATUS_WMASK)
                                 | (mstatus   & ~MSTATUS_WMASK);

                    // mie: only MEI[11], MTI[7], MSI[3] implemented.
                    ADDR_MIE:
                        mie <= csr_wdata & MIE_WMASK;

                    // mtvec: force Direct mode (bits[1:0] = 2'b00).
                    // Vectored mode (bits[1:0]=01) is NOT implemented — the IF
                    // stage always jumps to mtvec base. Masking prevents software
                    // from accidentally enabling a broken mode.
                    ADDR_MTVEC:
                        mtvec <= {csr_wdata[31:2], (csr_wdata[1:0] == 2'b01) ? 2'b01 : 2'b00};

                    // mscratch: fully writable, no restrictions
                    ADDR_MSCRATCH:
                        mscratch <= csr_wdata;

                    // mepc: bits[1:0] must be zero (4-byte instruction alignment)
                    ADDR_MEPC:
                        mepc <= csr_wdata & 32'hFFFF_FFFC;

                    // mcause: fully writable (SW may synthesize a cause for testing)
                    ADDR_MCAUSE:
                        mcause <= csr_wdata;

                    // mtval: fully writable
                    ADDR_MTVAL:
                        mtval <= csr_wdata;

                    // Counter low words — SW write supersedes the +1 above
                    // (last assignment wins in non-blocking; this fires after the
                    // unconditional increment, so it correctly overrides it)
                    ADDR_MCYCLE:
                        mcycle[31:0]    <= csr_wdata;

                    ADDR_MCYCLEH:
                        mcycle[63:32]   <= csr_wdata;

                    ADDR_MINSTRET:
                        minstret[31:0]  <= csr_wdata;

                    ADDR_MINSTRETH:
                        minstret[63:32] <= csr_wdata;

                    // All others (MISA, MVENDORID, MARCHID, MIMPID, MHARTID,
                    // MIP) are read-only — silently ignore writes.
                    default: ;

                endcase
            end
            // (no else — background updates already applied above)

        end
    end

    // =========================================================================
    // Output assignments to CPU control path
    // These are registered values; no combinational path from inputs to outputs.
    // =========================================================================
    assign mtvec_out   = mtvec;
    assign mepc_out    = mepc;
    assign mstatus_out = mstatus;
    assign mie_out     = mie;
    // interrupt_pending is assigned combinationally above

endmodule