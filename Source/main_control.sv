module main_control (
    input logic [6:0] opcode,
    output logic branch,
    output logic mux_inp,
    output logic memread,
    output logic [1:0] memtoreg,
    output logic memwrite,
    output logic alusrc,
    output logic reg_write,
    output logic [2:0]aluop
);

always @(*) begin
    // Default values
    branch = 0;
    memread = 0;
    memtoreg = 2'b11; 
    memwrite = 0;
    alusrc = 0;
    reg_write = 0;
    aluop = 3'b000;
    mux_inp = 1'b0;
    
    case (opcode)
        7'b0110011: // R-type
        begin
            branch = 0;
            memread = 0;
            memtoreg = 2'b00;
            memwrite = 0;
            alusrc = 0;
            reg_write = 1;
            aluop = 3'b000;
            mux_inp = 1'b0;
        end

        7'b0010011: // I-type
        begin 
            branch = 0;
            memread = 0;
            memtoreg = 2'b00;
            memwrite = 0;
            alusrc = 1;
            reg_write = 1;
            aluop = 3'b001;
            mux_inp = 1'b0;
        end

        7'b0000011: // Load
        begin
            branch = 0;
            memread = 1;
            memtoreg = 2'b01; 
            memwrite = 0;
            alusrc = 1;
            reg_write = 1;
            aluop = 3'b010;
            mux_inp = 1'b0;
        end

        7'b0100011: // Store
        begin
            branch = 0;
            memread = 0;
            memtoreg = 2'b11; 
            memwrite=1; 
            alusrc = 1; 
            reg_write = 0; 
            aluop = 3'b011; 
            mux_inp = 1'b0;
        end

        7'b1100011: // Branch
        begin
            branch = 1; 
            memread = 0; 
            memtoreg = 2'b00; 
            memwrite = 0; 
            alusrc = 0; 
            reg_write = 0; 
            aluop = 3'b100; 
            mux_inp = 1'b0;
        end

        7'b1101111: // JAL
        begin
            branch = 0; 
            memread = 0; 
            memtoreg = 2'b10; 
            memwrite = 0; 
            alusrc = 1; 
            reg_write = 1; 
            aluop = 3'b101;
            mux_inp = 1'b0; 
        end
        
         7'b1100111: // JALR
        begin
            branch = 0; 
            memread = 0; 
            memtoreg = 2'b10; 
            memwrite = 0; 
            alusrc = 1; 
            reg_write = 1; 
            aluop = 3'b001; 
            mux_inp = 1'b1;
        end

        // U-type instruction handling lui
        7'b0110111: 
        begin
            branch = 0; 
            memread = 0; 
            memtoreg = 2'b10; 
            memwrite = 0; 
            alusrc = 1; 
            reg_write = 1; 
            aluop = 3'b110; 
            mux_inp = 1'b0;
        end
        
         // U-type instruction handling auipc
        7'b0010111: 
        begin
            branch = 0; 
            memread = 0; 
            memtoreg = 2'b10; 
            memwrite = 0; 
            alusrc = 1; 
            reg_write = 1; 
            aluop = 3'b000; 
            mux_inp = 1'b0;
        end
        
        default: // Handle unspecified opcodes
        begin
            branch     = 1'b0;
            memread    = 1'b0;
            memtoreg   = 2'b11;  
            memwrite   = 1'b0;
            alusrc     = 1'b0;
            reg_write  = 1'b0;
            aluop      = 3'b000;  
            mux_inp    = 1'b0;

         end
    endcase
end

endmodule
