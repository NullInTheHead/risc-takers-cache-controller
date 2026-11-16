// mem_interface.v -- Memory interface bridge between cache FSM and main memory
// Owner: Member 3 (Main-Memory Interface & Top-Level Integration)
//
// Translates the cache controller FSM's memory request signals into the
// main_memory module's req/ack protocol. On a read miss the FSM sends a
// block-aligned address; this module forwards the request and delivers the
// returned BLOCK_BITS-wide line back to the FSM / data_ram. On a write
// (write-through), it forwards the single word and its address.
//
// The interface latches the request at the IDLE -> BUSY transition, pulses
// mm_req to initiate the main-memory transaction, holds address/data stable,
// and asserts fsm_mem_ready combinationally when main memory asserts mm_ready.
// This prevents spurious re-triggering while the FSM transitions out of ALLOCATE.

`timescale 1ns/1ps

module mem_interface #(
    parameter ADDR_WIDTH    = 32,
    parameter CACHE_SIZE    = 1024,
    parameter BLOCK_SIZE    = 16,
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
    input  wire                     rst,

    // --- FSM side (directly connected to cache_controller_fsm) ---
    input  wire                     fsm_mem_req,    // FSM requesting memory access
    input  wire                     fsm_mem_wr,     // 0 = read, 1 = write
    input  wire [ADDR_WIDTH-1:0]    fsm_mem_addr,   // block-aligned for read; word addr for write
    input  wire [DATA_WIDTH-1:0]    fsm_mem_wdata,  // write data (single word)
    output wire                     fsm_mem_ready,  // pulsed when transaction completes

    // Read data back to cache storage (for refill)
    output wire [BLOCK_BITS-1:0]    refill_data,    // full block from main memory

    // --- Main-memory side ---
    output reg                      mm_req,
    output reg                      mm_wr,
    output reg  [ADDR_WIDTH-1:0]    mm_addr,
    output reg  [DATA_WIDTH-1:0]    mm_wdata,
    input  wire                     mm_ready,
    input  wire [BLOCK_BITS-1:0]    mm_rdata
);

    // ------------------------------------------------------------------
    // FSM State Encoding: IDLE -> BUSY (wait for mm_ready) -> IDLE
    // ------------------------------------------------------------------
    localparam MI_IDLE = 1'b0;
    localparam MI_BUSY = 1'b1;

    reg mi_state;

    // Ready signal is passed combinationally to FSM when memory finishes,
    // allowing FSM to advance to UPDATE / RESPOND on the very next clock edge.
    assign fsm_mem_ready = mm_ready && (mi_state == MI_BUSY);
    assign refill_data   = mm_rdata;    // pass block through

    always @(posedge clk) begin
        if (rst) begin
            mi_state <= MI_IDLE;
            mm_req   <= 1'b0;
            mm_wr    <= 1'b0;
            mm_addr  <= {ADDR_WIDTH{1'b0}};
            mm_wdata <= {DATA_WIDTH{1'b0}};
        end else begin
            case (mi_state)
                MI_IDLE: begin
                    if (fsm_mem_req) begin
                        mm_req   <= 1'b1;
                        mm_wr    <= fsm_mem_wr;
                        mm_addr  <= fsm_mem_addr;
                        mm_wdata <= fsm_mem_wdata;
                        mi_state <= MI_BUSY;
                    end
                end

                MI_BUSY: begin
                    // Deassert mm_req after main memory has sampled it
                    mm_req <= 1'b0;
                    if (mm_ready) begin
                        mi_state <= MI_IDLE;
                    end
                end

                default: mi_state <= MI_IDLE;
            endcase
        end
    end

endmodule
