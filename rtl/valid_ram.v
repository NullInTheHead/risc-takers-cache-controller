// valid_ram.v -- one valid bit per cache line
// Owner: Member 1 (Cache Architecture & Storage)
//
// Stored as a NUM_LINES-bit register (not a RAM) so that every bit can be
// cleared in a single cycle on reset or flush. After reset every line is
// invalid, so the first access to any line is a compulsory (cold) miss even
// if the stale tag happens to match.
//
// Priority: rst > flush > we

`timescale 1ns/1ps

module valid_ram #(
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
    input  wire                  rst,
    input  wire                  flush,
    input  wire [INDEX_BITS-1:0] index,
    input  wire                  we,
    input  wire                  wvalid,
    output wire                  rvalid
);
    reg [NUM_LINES-1:0] valid_bits;

    assign rvalid = valid_bits[index];

    always @(posedge clk) begin
        if (rst || flush)
            valid_bits <= {NUM_LINES{1'b0}};
        else if (we)
            valid_bits[index] <= wvalid;
    end

endmodule
