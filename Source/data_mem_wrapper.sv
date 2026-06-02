`timescale 1ns/1ps

module data_mem_wrapper (
    input  logic        clk,
    input  logic        reset,
    
    // CPU-facing Signals
    input  logic [31:0] addr,           // Calculated address from ALU
    input  logic [31:0] write_data,     // Raw rs2 data from CPU
    input  logic        mem_read_en,    // From Controller
    input  logic        mem_write_en,   // From Controller
    input  logic [6:0]  opcode,         // To identify Store (7'h23) vs Load (7'h03)
    input  logic [2:0]  fn3,            // B/H/W width and Sign/Zero extension
    
    // Output to CPU
    output logic [31:0] read_data_out   // Final data for Writeback (Aligned & Extended)
);

    // --- Internal Wires for the Storage Instance ---
    logic [3:0]  internal_be;
    logic [31:0] swizzled_write_data;
    logic [31:0] raw_mem_read_data;
    logic        cs_n;
    logic        we_n;

    // Control signals for the raw memory module
    assign cs_n = !(mem_read_en || mem_write_en);
    assign we_n = !mem_write_en;

    // --- 1. STORE LOGIC (Swizzling & Masking) ---
    always_comb begin
        internal_be         = 4'b0000;
        swizzled_write_data = 32'b0;

        if (mem_write_en && (opcode == 7'h23)) begin 
            case (fn3)
                3'b000: begin // SB
                    case (addr[1:0])
                        2'b00: begin internal_be = 4'b0001; swizzled_write_data[7:0]   = write_data[7:0]; end
                        2'b01: begin internal_be = 4'b0010; swizzled_write_data[15:8]  = write_data[7:0]; end
                        2'b10: begin internal_be = 4'b0100; swizzled_write_data[23:16] = write_data[7:0]; end
                        2'b11: begin internal_be = 4'b1000; swizzled_write_data[31:24] = write_data[7:0]; end
                    endcase
                end

                3'b001: begin // SH
                    case (addr[1])
                        1'b0:  begin internal_be = 4'b0011; swizzled_write_data[15:0]  = write_data[15:0]; end
                        1'b1:  begin internal_be = 4'b1100; swizzled_write_data[31:16] = write_data[15:0]; end
                    endcase
                end

                3'b010: begin // SW
                    internal_be         = 4'b1111;
                    swizzled_write_data = write_data;
                end
                
                default: internal_be = 4'b0000;
            endcase
        end
    end

    // --- 2. LOAD LOGIC (Extraction & Extension) ---
    logic [7:0]  byte_to_ext;
    logic [15:0] half_to_ext;

    always_comb begin
        // Select byte from the 32-bit word based on address LSBs
        case (addr[1:0])
            2'b00: byte_to_ext = raw_mem_read_data[7:0];
            2'b01: byte_to_ext = raw_mem_read_data[15:8];
            2'b10: byte_to_ext = raw_mem_read_data[23:16];
            2'b11: byte_to_ext = raw_mem_read_data[31:24];
        endcase

        // Select halfword
        case (addr[1])
            1'b0:  half_to_ext = raw_mem_read_data[15:0];
            1'b1:  half_to_ext = raw_mem_read_data[31:16];
        endcase

        read_data_out = 32'b0;
        if (mem_read_en && (opcode == 7'h03)) begin
            case (fn3)
                3'b000: read_data_out = {{24{byte_to_ext[7]}}, byte_to_ext}; // LB (Sign extended)
                3'b001: read_data_out = {{16{half_to_ext[15]}}, half_to_ext};// LH (Sign extended)
                3'h2:   read_data_out = raw_mem_read_data;                   // LW
                3'b100: read_data_out = {24'b0, byte_to_ext};                // LBU (Zero extended)
                3'b101: read_data_out = {16'b0, half_to_ext};                // LHU (Zero extended)
                default: read_data_out = 32'b0;
            endcase
        end
    end

    // --- 3. Instantiate the Raw Memory Module ---
    data_memory storage_inst (
        .clk         (clk),
        .cs_n        (cs_n),
        .we_n        (we_n),
        .addr        (addr),
        .write_data  (swizzled_write_data),
        .byte_enable (internal_be),
        .read_data   (raw_mem_read_data)
    );

endmodule