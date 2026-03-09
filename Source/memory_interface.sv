`timescale 1ns/1ps

module memory_interface (
    // --- CPU-facing Ports ---
    input  logic [6:0]   opcode,            // Opcode to identify Load/Store
    input  logic [2:0]   fn3,               // Funct3 for width (B/H/W)
    input  logic [31:0]  cpu_store_data,    // Raw data from rs2
    output logic [31:0]  cpu_writeback_data,// Aligned/Extended data for WB

    // --- Memory-facing Ports ---
    input  logic [1:0]   addr_lsb,          // ALU_out[1:0]
    input  logic [31:0]  mem_read_data,     // Raw word from Data Memory
    output logic [3:0]   byte_enable,       // Write mask (WE# per byte)
    output logic [31:0]  mem_write_data     // Swizzled data for memory
);

    // --- STORE LOGIC (Swizzling & Masking) ---
    // Maps the CPU data to the correct byte lanes based on alignment
    
    always_comb begin
        byte_enable    = 4'b0000;
        mem_write_data = 32'b0;

        if (opcode == 7'b0100011) begin // Store instructions
            case (fn3)
                3'b000: begin // SB (Store Byte)
                    case (addr_lsb)
                        2'b00: begin byte_enable = 4'b0001; mem_write_data[7:0]   = cpu_store_data[7:0]; end
                        2'b01: begin byte_enable = 4'b0010; mem_write_data[15:8]  = cpu_store_data[7:0]; end
                        2'b10: begin byte_enable = 4'b0100; mem_write_data[23:16] = cpu_store_data[7:0]; end
                        2'b11: begin byte_enable = 4'b1000; mem_write_data[31:24] = cpu_store_data[7:0]; end
                    endcase
                end

                3'b001: begin // SH (Store Halfword)
                    case (addr_lsb[1]) // Must be halfword aligned (0 or 2)
                        1'b0:  begin byte_enable = 4'b0011; mem_write_data[15:0]  = cpu_store_data[15:0]; end
                        1'b1:  begin byte_enable = 4'b1100; mem_write_data[31:16] = cpu_store_data[15:0]; end
                    endcase
                end

                3'b010: begin // SW (Store Word)
                    byte_enable    = 4'b1111;
                    mem_write_data = cpu_store_data;
                end
                
                default: begin byte_enable = 4'b0000; mem_write_data = 32'b0; end
            endcase
        end
    end

    // --- LOAD LOGIC (Selection & Extension) ---
    // Extracts the relevant byte/halfword and applies sign or zero extension
    
    logic [7:0]  byte_to_ext;
    logic [15:0] half_to_ext;

    always_comb begin
        // Select byte
        case (addr_lsb)
            2'b00: byte_to_ext = mem_read_data[7:0];
            2'b01: byte_to_ext = mem_read_data[15:8];
            2'b10: byte_to_ext = mem_read_data[23:16];
            2'b11: byte_to_ext = mem_read_data[31:24];
        endcase

        // Select halfword
        case (addr_lsb[1])
            1'b0:  half_to_ext = mem_read_data[15:0];
            1'b1:  half_to_ext = mem_read_data[31:16];
        endcase

        cpu_writeback_data = 32'b0;
        if (opcode == 7'b0000011) begin // Load instructions
            case (fn3)
                3'b000: cpu_writeback_data = {{24{byte_to_ext[7]}}, byte_to_ext}; // LB
                3'b001: cpu_writeback_data = {{16{half_to_ext[15]}}, half_to_ext};// LH
                3'b010: cpu_writeback_data = mem_read_data;                      // LW
                3'b100: cpu_writeback_data = {24'b0, byte_to_ext};               // LBU
                3'b101: cpu_writeback_data = {16'b0, half_to_ext};               // LHU
                default: cpu_writeback_data = 32'b0;
            endcase
        end
    end

endmodule
