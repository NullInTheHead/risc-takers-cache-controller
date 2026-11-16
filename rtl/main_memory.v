// main_memory.v -- Behavioural main-memory model with configurable latency
// Owner: Member 3 (Main-Memory Interface & Top-Level Integration)
//
// Models a simple main memory that:
//   - Accepts read (block) and write (single word) requests via req/ack.
//   - Returns a full BLOCK_SIZE block for reads after a configurable latency:
//       MEM_FIRST_LAT cycles for the first word, MEM_NEXT_LAT per subsequent
//       word  =>  total read latency = MEM_FIRST_LAT + (WORDS_PER_BLK-1)*MEM_NEXT_LAT.
//   - Returns ack after MEM_FIRST_LAT cycles for writes (single word, write-through).
//   - Stores data in a flat byte-addressable array (word-aligned access only).
//
// This is a behavioural simulation model — it will NOT be synthesised.

`timescale 1ns/1ps

module main_memory #(
    parameter ADDR_WIDTH    = 32,
    parameter CACHE_SIZE    = 1024,
    parameter BLOCK_SIZE    = 16,
    parameter MEM_FIRST_LAT = 10,       // first-word latency (cycles)
    parameter MEM_NEXT_LAT  = 1,        // subsequent-word latency (cycles)
    // ---- derived: do NOT override, they follow the three above ----
    parameter DATA_WIDTH    = 32,
    parameter NUM_LINES     = CACHE_SIZE / BLOCK_SIZE,
    parameter OFFSET_BITS   = $clog2(BLOCK_SIZE),
    parameter BYTE_OFF_BITS = 2,
    parameter WORD_SEL_BITS = OFFSET_BITS - BYTE_OFF_BITS,
    parameter INDEX_BITS    = $clog2(NUM_LINES),
    parameter TAG_BITS      = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS,
    parameter BLOCK_BITS    = BLOCK_SIZE * 8,
    parameter WORDS_PER_BLK = BLOCK_SIZE / 4,
    parameter MEM_DEPTH     = 65536     // number of 32-bit words in main memory
) (
    input  wire                     clk,
    input  wire                     rst,

    // Request interface (active-high handshake)
    input  wire                     mem_req,    // request strobe
    input  wire                     mem_wr,     // 0 = read (block), 1 = write (word)
    input  wire [ADDR_WIDTH-1:0]    mem_addr,   // byte address (block-aligned for reads)
    input  wire [DATA_WIDTH-1:0]    mem_wdata,  // write data (single word)

    // Response interface
    output reg                      mem_ready,  // one-cycle pulse when done
    output reg  [BLOCK_BITS-1:0]    mem_rdata   // read data (full block, valid on mem_ready)
);

    // ------------------------------------------------------------------
    // Internal memory array (simulation only — sized to cover trace space)
    // ------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] mem_array [0:MEM_DEPTH-1];

    // ------------------------------------------------------------------
    // Latency counter FSM
    // ------------------------------------------------------------------
    localparam S_MEM_IDLE  = 2'd0;
    localparam S_MEM_FIRST = 2'd1;      // counting first-word latency
    localparam S_MEM_BURST = 2'd2;      // counting subsequent words
    localparam S_MEM_DONE  = 2'd3;

    reg [1:0]               mstate;
    reg [31:0]              lat_cnt;     // latency counter
    reg [31:0]              word_cnt;    // burst word counter
    reg [ADDR_WIDTH-1:0]    saved_addr;
    reg [DATA_WIDTH-1:0]    saved_wdata;
    reg                     saved_wr;
    reg [BLOCK_BITS-1:0]    rdata_build; // assembled block during burst

    always @(posedge clk) begin
        if (rst) begin
            mstate    <= S_MEM_IDLE;
            mem_ready <= 1'b0;
            mem_rdata <= {BLOCK_BITS{1'b0}};
            lat_cnt   <= 0;
            word_cnt  <= 0;
        end else begin
            mem_ready <= 1'b0;  // default: de-assert

            case (mstate)
                // -------------------------------------------------
                S_MEM_IDLE: begin
                    if (mem_req) begin
                        saved_addr  <= mem_addr;
                        saved_wdata <= mem_wdata;
                        saved_wr    <= mem_wr;
                        lat_cnt     <= 1;       // start counting from 1
                        word_cnt    <= 0;
                        rdata_build <= {BLOCK_BITS{1'b0}};
                        mstate      <= S_MEM_FIRST;
                    end
                end

                // -------------------------------------------------
                S_MEM_FIRST: begin
                    if (lat_cnt >= MEM_FIRST_LAT) begin
                        if (saved_wr) begin
                            // Write: store word & complete
                            mem_array[saved_addr[ADDR_WIDTH-1:2] % MEM_DEPTH] <= saved_wdata;
                            mem_ready <= 1'b1;
                            mstate    <= S_MEM_IDLE;
                        end else begin
                            // Read: first word is ready — grab it
                            rdata_build[0 +: DATA_WIDTH] <=
                                mem_array[saved_addr[ADDR_WIDTH-1:2] % MEM_DEPTH];
                            word_cnt <= 1;
                            if (WORDS_PER_BLK == 1) begin
                                // Single-word block: done immediately
                                mem_rdata <= {BLOCK_BITS{1'b0}};
                                mem_rdata[0 +: DATA_WIDTH] <=
                                    mem_array[saved_addr[ADDR_WIDTH-1:2] % MEM_DEPTH];
                                mem_ready <= 1'b1;
                                mstate    <= S_MEM_IDLE;
                            end else begin
                                lat_cnt <= 1;   // reset counter for burst words
                                mstate  <= S_MEM_BURST;
                            end
                        end
                    end else begin
                        lat_cnt <= lat_cnt + 1;
                    end
                end

                // -------------------------------------------------
                S_MEM_BURST: begin
                    if (lat_cnt >= MEM_NEXT_LAT) begin
                        // Grab next word
                        rdata_build[word_cnt*DATA_WIDTH +: DATA_WIDTH] <=
                            mem_array[(saved_addr[ADDR_WIDTH-1:2] + word_cnt) % MEM_DEPTH];
                        word_cnt <= word_cnt + 1;

                        if (word_cnt + 1 >= WORDS_PER_BLK) begin
                            // All words collected — pack and signal ready
                            // Build final output: words already in rdata_build,
                            // plus the last word we just read
                            mem_rdata <= rdata_build;
                            mem_rdata[word_cnt*DATA_WIDTH +: DATA_WIDTH] <=
                                mem_array[(saved_addr[ADDR_WIDTH-1:2] + word_cnt) % MEM_DEPTH];
                            mem_ready <= 1'b1;
                            mstate    <= S_MEM_IDLE;
                        end else begin
                            lat_cnt <= 1;   // reset for next word
                        end
                    end else begin
                        lat_cnt <= lat_cnt + 1;
                    end
                end

                // -------------------------------------------------
                default: mstate <= S_MEM_IDLE;
            endcase
        end
    end

    // ------------------------------------------------------------------
    // Initialise memory with a predictable pattern so reads return known
    // values that the testbench / reference model can reproduce.
    //   Pattern: mem_array[word_addr] = word_addr * 4  (i.e. the byte address)
    // ------------------------------------------------------------------
    integer k;
    initial begin
        for (k = 0; k < MEM_DEPTH; k = k + 1)
            mem_array[k] = k * 4;  // byte address of that word
    end

endmodule
