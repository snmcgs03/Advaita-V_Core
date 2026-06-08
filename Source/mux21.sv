 module mux21 
(
    input logic [31:0] a, b,
    input logic control,
    output logic [31:0] y
);

always_comb
y = control ? b : a;
endmodule
