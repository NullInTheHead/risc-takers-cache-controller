// data_ram.v -- cache data storage (NUM_LINES x BLOCK_BITS)
// Owner: Member 1 (Cache Architecture & Storage)
//
// Default: 64 lines x 128 bits (4 x 32-bit words per line) = 1 KB.
//
// * Read is combinational: rdata_word / rdata_line reflect line `index`
//   in the same cycle, so a read hit completes in one cycle.
// * we_line : write a full line (refill from main memory). Word 0 of the
//             block sits in wdata_line[31:0].
// * we_word : write a single word (CPU write hit, write-through policy).
// * If both are asserted, we_line wins.

`timescale 1ns/1ps

module data_ram #(
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
    input  wire                     clk,
    input  wire [INDEX_BITS-1:0]    index,
    input  wire [WORD_SEL_BITS-1:0] word_sel,
    input  wire                     we_word,
    input  wire [DATA_WIDTH-1:0]    wdata_word,
    input  wire                     we_line,
    input  wire [BLOCK_BITS-1:0]    wdata_line,
    output wire [DATA_WIDTH-1:0]    rdata_word,
    output wire [BLOCK_BITS-1:0]    rdata_line
);
    reg [BLOCK_BITS-1:0] mem [0:NUM_LINES-1];

    // Read path
    assign rdata_line = mem[index];
    assign rdata_word = rdata_line[word_sel*DATA_WIDTH +: DATA_WIDTH];

    // Write path (read-modify-write for single-word updates)
    reg [BLOCK_BITS-1:0] merged;
    always @(*) begin
        merged = rdata_line;
        merged[word_sel*DATA_WIDTH +: DATA_WIDTH] = wdata_word;
    end

    always @(posedge clk) begin
        if (we_line)
            mem[index] <= wdata_line;
        else if (we_word)
            mem[index] <= merged;
    end

    // Simulation only: start from a known state so waveforms are readable.
    // Correctness never depends on this -- the valid bits gate every hit.
    integer i;
    initial begin
        for (i = 0; i < NUM_LINES; i = i + 1)
            mem[i] = {BLOCK_BITS{1'b0}};
    end

endmodule
