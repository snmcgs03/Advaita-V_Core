module id_stage(
    input  logic        clk, reset,trap_en,
    input  logic [31:0] instruction,
    input  logic [31:0] wb_data,
    output logic [31:0] rs1_data, rs2_data,
    output logic [31:0] imm_out,
    output logic [6:0]  opcode_out_d,
    output logic [6:0]  imm11_5,
    output logic [2:0]  fn3_out_d,
    output logic        fn7_5,
    output logic [2:0]  aluop,
    output logic [1:0]  memtoreg,
    output logic        branch, mem_write, mem_read, alu_src,mux_inp, 
    output logic        csr_we, is_mret,sw_trap, 
    output logic [11:0] csr_addr
);

    logic [4:0]  rs1, rs2, rd;
    logic [11:0] imm_i_s;
    logic [19:0] imm_u_j;
    logic reg_write_out;
    logic gated_reg_write;
    
    assign gated_reg_write = reg_write_out && !trap_en; // silenced by ANY trap
    
    decoder decode (
            .instruction(instruction),
            .rs1(rs1), .rs2(rs2), .rd(rd),
            .opcode(opcode_out_d), .fn3(fn3_out_d), .fn7_5(fn7_5),
            .imm(imm_i_s), .imm_uj(imm_u_j), .csr_addr(csr_addr),.imm11_5(imm11_5)
        );
    
    imm_generator imm_gen (
        .imm_input(imm_i_s),
        .imm_input_uj(imm_u_j),
        .rs1_field(rs1), 
        .opcode(opcode_out_d),
        .fn3(fn3_out_d),
        .imm_output(imm_out)
    );

    register_file reg_file (
        .clk(clk), .reset(reset),
        .rs1_sel(rs1), .rs2_sel(rs2), .rd_sel(rd),
        .reg_write(gated_reg_write), .wb_data(wb_data),
        .rs1_data(rs1_data), .rs2_data(rs2_data)
    );

    main_control mc (
        .opcode(opcode_out_d),
        .fn3(fn3_out_d),
        .inst(instruction[31:20]),
        .rs1_is_zero(rs1 == 5'b0), 
        .branch(branch),
        .memtoreg(memtoreg),
        .aluop(aluop),
        .memwrite(mem_write),
        .alusrc(alu_src),
        .reg_write(reg_write_out),
        .memread(mem_read),
        .csr_we(csr_we),
        .is_mret(is_mret),
        .mux_inp(mux_inp),
        .sw_trap(sw_trap)
    );
endmodule