// tag_ram.v -- tag storage (NUM_LINES x TAG_BITS)
// Owner: Member 1 (Cache Architecture & Storage)
//
// Default: 64 entries x 22 bits.
// Combinational read of entry `index`; synchronous write on refill.

`timescale 1ns/1ps

module tag_ram #(
    parameter ADDR_WIDTH = 32,
    parameter CACHE_SIZE = 1024,
    parameter BLOCK_SIZE = 16,
    // ---- derived: do NOT override, they follow the three above ----
    parameter DATA_WIDTH    = 32,
    parameter NUM_LINES     = CACHE_SIZE / BLOCK_SIZE,
    parameter OFFSET_BITS   = $clog2(BLOCK_SIZE),
    parameter BYTE_OFF_BITS = 2,
    parameter WORD_SEL_BITS = OFFSET_BITS - BYTE_OFF_BITS,
    parameter INDEX_BITS    = $clog2(NUM_LINES),
    parameter TAG_BITS      = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS,
    parameter BLOCK_BITS    = BLOCK_SIZE * 8
) (
    input  wire                  clk,
    input  wire [INDEX_BITS-1:0] index,
    input  wire                  we,
    input  wire [TAG_BITS-1:0]   wtag,
    output wire [TAG_BITS-1:0]   rtag
);
    reg [TAG_BITS-1:0] mem [0:NUM_LINES-1];

    assign rtag = mem[index];

    always @(posedge clk) begin
        if (we)
            mem[index] <= wtag;
    end

    // Simulation only (see data_ram.v)
    integer i;
    initial begin
        for (i = 0; i < NUM_LINES; i = i + 1)
            mem[i] = {TAG_BITS{1'b0}};
    end

endmodule
