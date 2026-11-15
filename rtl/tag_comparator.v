// tag_comparator.v -- tag matching logic for direct-mapped cache
// Owner: Member 2 (Controller FSM & Tag Comparator)
//
// Default: 22-bit tag comparator gated by valid bit.
// Purely combinational; computes:
//   hit = rvalid && (rtag == tag)
//
// A hit indicates that the requested address block is currently cached
// in the indexed line and is valid. When rvalid is low (e.g. after reset or
// line invalidation), hit is forced to 0 regardless of the stored tag value,
// correctly producing a compulsory (cold) miss.

`timescale 1ns/1ps

module tag_comparator #(
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
    input  wire [TAG_BITS-1:0] tag,      // Requested tag from address_decoder
    input  wire [TAG_BITS-1:0] rtag,     // Stored tag read from tag_ram
    input  wire                rvalid,   // Valid bit read from valid_ram
    output wire                hit       // 1 = hit (valid & tags match), 0 = miss
);

    assign hit = rvalid && (rtag == tag);

endmodule
