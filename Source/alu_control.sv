module alu_control(alu_op,control_out,fn3,imm11_5,fn7_5);
input logic [2:0]alu_op;
input logic [2:0]fn3;
input logic [6:0]imm11_5;
output logic [3:0]control_out;
input logic fn7_5;

always_comb
begin

control_out = 0;
case(alu_op)

3'b000:     //R-Type
begin

if(fn3==3'b000 && fn7_5==0)
control_out = 4'b0000;  // add

else if(fn3==3'b000 && fn7_5 == 1)
control_out = 4'b0001;  //sub

else if (fn3==3'b100)
control_out = 4'b0010;  //xor

else if(fn3==3'b110)
control_out = 4'b0011;  //or

else if(fn3==3'b111)
control_out = 4'b0100;  //and

else if(fn3==3'b001)
control_out = 4'b0101;  //sll

else if(fn3==3'b101 && fn7_5 == 0)
control_out = 4'b0110;  //srl

else if(fn3==3'b101 && fn7_5 == 1)
control_out = 4'b0111;  //sra

else if(fn3==3'b010)
control_out = 4'b1000;  //slt

else if(fn3==3'b011)
control_out = 4'b1001;  //sltu
end



3'b001: //I-  type
begin

if(fn3 == 3'b000)
control_out = 4'b0000;  //addi + jalr

else if(fn3 == 3'b100)
control_out = 4'b0010;  //xori

else if(fn3 == 3'b110)
control_out = 4'b0011;  //ori

else if(fn3 == 3'b111)
control_out = 4'b0100;  //andi

else if(fn3 == 3'b001)
control_out = 4'b0101;  //slli

else if(fn3 == 3'b101 && imm11_5 == 7'h00)
control_out = 4'b0110;  //srli

else if(fn3 == 3'b101 && imm11_5 == 7'h20)
control_out = 4'b0111;  //srai

else if(fn3 == 3'b010)
control_out = 4'b1000;  //slti

else if(fn3 == 3'b011)
control_out = 4'b1001;  //sltiu
end


3'b010: //load

begin
if(fn3 == 3'b000)
control_out = 4'b0000;  //load byte

else if(fn3 == 3'b001)
control_out = 4'b0000;  //load half

else if(fn3 == 3'b010)
control_out = 4'b0000;  //load word

else if(fn3 == 3'b100)
control_out = 4'b0000;  //lbu

else if(fn3 == 3'b101)
control_out = 4'b0000;  //lhu
end



3'b011: //S-Type

begin
if(fn3 == 3'b000)
control_out = 4'b0000;  //sb

else if(fn3 == 3'b001)
control_out = 4'b0000;  //sh

else if(fn3 == 3'b010)
control_out = 4'b0000;  //sw
end


3'b100: //B-Type

begin
if(fn3 == 3'b000)
control_out = 4'b1010;  //beq

else if(fn3 == 3'b001)
control_out = 4'b1011;  //bne

else if(fn3 == 3'b100)
control_out = 4'b1100;  //blt

else if(fn3 == 3'b101)
control_out = 4'b1101;  //bge

else if(fn3 == 3'b110)
control_out = 4'b1110;  //bltu

else if(fn3 == 3'b111)
control_out = 4'b1111;  //bgeu
end

3'b101: //Jal and jalr
begin
if(fn3 == 3'b000)
//control_out = 4'b0000;  //jal
//else
control_out = 4'b0000;  //jalr
end

default: control_out = 4'b0000;
endcase
end
endmodule
