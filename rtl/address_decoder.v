// address_decoder.v -- splits a CPU byte address into tag / index / offset
// Owner: Member 1 (Cache Architecture & Storage)
//
// Default layout (1 KB cache, 16 B blocks, 32-bit address):
//   [31:10] tag (22) | [9:4] index (6) | [3:2] word_sel (2) | [1:0] byte_off (2)
//
// Purely combinational; widths follow the parameters, so changing CACHE_SIZE
// or BLOCK_SIZE re-derives the fields automatically.

`timescale 1ns/1ps

module address_decoder #(
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
    input  wire [ADDR_WIDTH-1:0]    addr,
    output wire [TAG_BITS-1:0]      tag,
    output wire [INDEX_BITS-1:0]    index,
    output wire [WORD_SEL_BITS-1:0] word_sel,
    output wire [BYTE_OFF_BITS-1:0] byte_off
);
    assign byte_off = addr[BYTE_OFF_BITS-1:0];
    assign word_sel = addr[OFFSET_BITS-1:BYTE_OFF_BITS];
    assign index    = addr[OFFSET_BITS+INDEX_BITS-1:OFFSET_BITS];
    assign tag      = addr[ADDR_WIDTH-1:OFFSET_BITS+INDEX_BITS];

endmodule
