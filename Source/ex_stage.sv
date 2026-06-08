module ex_stage (
    // Data inputs
    input  logic [31:0] rs1_data,       // Register file rs1
    input  logic [31:0] rs2_data,       // Register file rs2
    input  logic [31:0] imm_out,        // Sign/zero-extended immediate
    input  logic [31:0] address,        // Current PC (for branch/JAL target)
    input  logic [31:0] csr_read_data,  // Old CSR value (for CSRRS/CSRRC mask)

    // Control inputs (from ID stage)
    input  logic        branch,         // Instruction is a conditional branch
    input  logic        alu_src,        // 0=rs2_data, 1=imm_out for ALU operand B
    input  logic        fn7_5,          // instruction[30] — SUB/SRA qualifier
    input  logic        mux_inp,        // 1=JALR (use alu_out as target), 0=branch/JAL
    input  logic [2:0]  fn3,            // funct3 field
    input  logic [6:0]  imm11_5,        // instruction[31:25] — funct7 / shift-amount mask
    input  logic [2:0]  aluop,          // ALU operation class from main_control
    input  logic [6:0]  opcode,         // Instruction opcode (for JAL detection)

    // Outputs
    output logic        and_out_ex,     // Branch/jump taken flag → IF stage
    output logic [31:0] alu_out,        // ALU result → data memory addr / writeback
    output logic [31:0] pc_ex_out       // Computed jump/branch target → IF stage
);

    // =========================================================================
    // Internal signals
    // =========================================================================
    logic [31:0] alu_operand_b;   // Selected ALU operand B
    logic        branch_taken;    // Condition flag from ALU (replaces 'zero')
    logic [4:0]  alu_operation;   // 5-bit ALU control from alu_control
    logic [31:0] pc_signed_offset;// PC + sign-extended offset (branch/JAL target)

    // =========================================================================
    // Operand-B mux
    //   alu_src=0 → R-type  : operand B = rs2_data
    //   alu_src=1 → I/S/CSR : operand B = imm_out
    //   Note: for CSR-immediate variants (CSRRWI/CSRRSI/CSRRCI), main_control
    //   sets alu_src=1 and the imm_generator puts uimm[4:0] into imm_out.
    // =========================================================================
    assign alu_operand_b = alu_src ? imm_out : rs2_data;

    // =========================================================================
    // PC target computation
    //
    //   Branch / JAL : target = PC + sign-extended-offset  (pc_signed_offset)
    //   JALR         : target = (rs1 + imm) with bit[0] forced to 0  (alu_out)
    //
    // mux_inp=1 selects JALR path; mux_inp=0 selects branch/JAL path.
    // =========================================================================
    assign pc_signed_offset = address + imm_out;
    assign pc_ex_out        = mux_inp ? {alu_out[31:1], 1'b0} : pc_signed_offset;

    // =========================================================================
    // Branch / jump taken flag
    //
    //   Conditional branch : branch_taken comes from ALU comparison result.
    //   JAL (opcode 7'h6F) : always taken — unconditionally assert and_out_ex.
    //   JALR               : mux_inp=1 routes pc_ex_out correctly; the IF stage
    //                        uses and_out_ex to switch away from PC+4. JALR sets
    //                        branch=0 in main_control so it must be caught here
    //                        via mux_inp (same as JAL path).
    //
    // and_out_ex is consumed by if_stage to select pc_signed_offset / pc_ex_out
    // over the sequential PC+4.
    // =========================================================================
    assign and_out_ex = (branch & branch_taken)    // Conditional branch taken
                      | (opcode == 7'h6F)           // JAL unconditional
                      | (opcode == 7'h67);          // JALR unconditional

    // =========================================================================
    // Sub-module instantiations
    // =========================================================================

    alu alu_unit (
        .alu_control (alu_operation),
        .rs1_data    (rs1_data),
        .rs2_data    (alu_operand_b),   // Muxed operand B (rs2 or immediate)
        .csr_data    (csr_read_data),
        .alu_out     (alu_out),
        .zero        (branch_taken)
    );

    alu_control ac (
        .alu_op      (aluop),
        .fn3         (fn3),
        .imm11_5     (imm11_5),
        .fn7_5       (fn7_5),
        .control_out (alu_operation)
    );

endmodule