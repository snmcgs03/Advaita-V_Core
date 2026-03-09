module id_stage(rs1_data,rs2_data,imm_out,wb_data,opcode_out_d,fn3_out_d,fn7_5,imm11_5,branch,memtoreg,aluop,mem_write,alu_src,clk,reset,instruction,mux_inp);
input logic [31:0]instruction,wb_data;
input logic clk,reset;
output logic mux_inp;
output logic [31:0]rs1_data,rs2_data,imm_out;
output logic [6:0]opcode_out_d,imm11_5;
output logic [2:0]fn3_out_d;
output logic [2:0]aluop;
output logic [1:0]memtoreg;
output logic fn7_5,branch,mem_write,mem_read,alu_src;
(* KEEP = "TRUE" *) wire reg_write;
(* KEEP = "TRUE" *) wire [4:0]rs1,rs2,rd;
(* KEEP = "TRUE" *) wire [19:0]imm_uj_outd;
(* KEEP = "TRUE" *) wire [11:0]imm_out_d;
(* DONT_TOUCH = "TRUE" *) decoder decode (.imm11_5(imm11_5),.instruction(instruction),.rs1(rs1),.rs2(rs2),.rd(rd),.imm(imm_out_d),.imm_uj(imm_uj_outd),.fn3(fn3_out_d),.opcode(opcode_out_d),.fn7_5(fn7_5));
(* DONT_TOUCH = "TRUE" *) imm_generator imm_gen (.imm_input_uj(imm_uj_outd),.imm_input(imm_out_d),.imm_output(imm_out),.opcode(opcode_out_d),.fn3(fn3_out_d));
(* DONT_TOUCH = "TRUE" *) reg_file register_file (.rd_sel(rd),.reg_write(reg_write),.wb_data(wb_data),.clk(clk),.reset(reset),.rs1_sel(rs1),.rs2_sel(rs2),.rs1_data(rs1_data),.rs2_data(rs2_data));
(* DONT_TOUCH = "TRUE" *) main_control mc (.mux_inp(mux_inp),.opcode(opcode_out_d),.branch(branch),.memtoreg(memtoreg),.aluop(aluop),.memwrite(mem_write),.alusrc(alu_src),.reg_write(reg_write),.mem_read(mem_read));
endmodule
