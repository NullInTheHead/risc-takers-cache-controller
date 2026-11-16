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
// cache_controller_fsm.v -- Cache Controller Finite State Machine
// Owner: Member 2 (Controller FSM & Tag Comparator)
//
// Direct-mapped cache controller implementing write-through, no-write-allocate
// policy. Interfaces with:
//   - CPU / Master (cpu_req, cpu_wr, cpu_addr, cpu_wdata, cpu_ready, cpu_stall)
//   - Storage RAMs (tag_we, valid_we, valid_wdata, data_we_word, data_we_line)
//   - Tag Comparator (hit)
//   - Main-Memory Interface (mem_req, mem_wr, mem_addr, mem_wdata, mem_ready)
//
// FSM State Machine:
//   IDLE        : Waiting for CPU request.
//   COMPARE_TAG : Evaluates hit/miss outcome. Fast-path hits complete in 1 cycle.
//   ALLOCATE    : On read miss, requests full block refill from memory.
//                 On write miss, sends write-through to memory (no-write-allocate).
//   UPDATE      : Refill block received; writes data line, tag, and sets valid bit.
//   RESPOND     : Asserts cpu_ready and delivers requested data to CPU.

`timescale 1ns/1ps

module cache_controller_fsm #(
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
    // Clock and Synchronous Active-High Reset
    input  wire                     clk,
    input  wire                     rst,

    // CPU / Master Interface
    input  wire                     cpu_req,
    input  wire                     cpu_wr,
    input  wire [ADDR_WIDTH-1:0]    cpu_addr,
    input  wire [DATA_WIDTH-1:0]    cpu_wdata,
    output wire                     cpu_ready,
    output wire                     cpu_stall,

    // Tag Comparator & Address Decoder Inputs
    input  wire [TAG_BITS-1:0]      tag,
    input  wire [INDEX_BITS-1:0]    index,
    input  wire                     hit,

    // Storage Array Controls (Member 1 modules)
    output reg                      tag_we,
    output reg                      valid_we,
    output reg                      valid_wdata,
    output reg                      data_we_word,
    output reg                      data_we_line,

    // Main-Memory Interface (Member 3 module)
    output reg                      mem_req,
    output reg                      mem_wr,
    output reg  [ADDR_WIDTH-1:0]    mem_addr,
    output reg  [DATA_WIDTH-1:0]    mem_wdata,
    input  wire                     mem_ready,

    // State / Monitoring output
    output wire [2:0]               fsm_state
);

    // ----------------------------------------------------------------
    // FSM State Encoding
    // ----------------------------------------------------------------
    localparam S_IDLE        = 3'd0;
    localparam S_COMPARE_TAG = 3'd1;
    localparam S_ALLOCATE    = 3'd2; // Refill / memory wait
    localparam S_UPDATE      = 3'd3; // Write line, tag, valid
    localparam S_RESPOND     = 3'd4; // Signal completion

    reg [2:0] state, next_state;
    assign fsm_state = state;

    // ----------------------------------------------------------------
    // Request Latching (guarantees address/data stability during stalls)
    // ----------------------------------------------------------------
    reg [ADDR_WIDTH-1:0] saved_addr;
    reg [DATA_WIDTH-1:0] saved_wdata;
    reg                  saved_wr;

    always @(posedge clk) begin
        if (rst) begin
            saved_addr  <= {ADDR_WIDTH{1'b0}};
            saved_wdata <= {DATA_WIDTH{1'b0}};
            saved_wr    <= 1'b0;
        end else if (state == S_IDLE && cpu_req) begin
            saved_addr  <= cpu_addr;
            saved_wdata <= cpu_wdata;
            saved_wr    <= cpu_wr;
        end
    end

    wire [TAG_BITS-1:0]   saved_tag   = saved_addr[ADDR_WIDTH-1 : OFFSET_BITS+INDEX_BITS];
    wire [INDEX_BITS-1:0] saved_index = saved_addr[OFFSET_BITS+INDEX_BITS-1 : OFFSET_BITS];

    // ----------------------------------------------------------------
    // Next-State Logic
    // ----------------------------------------------------------------
    always @(*) begin
        next_state = state;
        case (state)
            S_IDLE: begin
                if (cpu_req) begin
                    if (hit) begin
                        // Hit fast-path: completes in 1 cycle
                        next_state = S_IDLE;
                    end else begin
                        // Miss: proceed to tag comparison / refill allocation
                        next_state = S_COMPARE_TAG;
                    end
                end else begin
                    next_state = S_IDLE;
                end
            end

            S_COMPARE_TAG: begin
                // In COMPARE_TAG, if hit occurs (e.g. multi-cycle request), respond
                if (hit) begin
                    next_state = S_RESPOND;
                end else begin
                    // Read miss -> ALLOCATE refill block
                    // Write miss -> ALLOCATE send write-through
                    next_state = S_ALLOCATE;
                end
            end

            S_ALLOCATE: begin
                // Wait for main memory to complete transaction
                if (mem_ready) begin
                    if (!saved_wr)
                        next_state = S_UPDATE;  // Read miss: write refill into cache
                    else
                        next_state = S_RESPOND; // Write miss: memory updated, respond
                end else begin
                    next_state = S_ALLOCATE;
                end
            end

            S_UPDATE: begin
                // Synchronous cache write completes on next clock edge
                next_state = S_RESPOND;
            end

            S_RESPOND: begin
                next_state = S_IDLE;
            end

            default: next_state = S_IDLE;
        endcase
    end

    // ----------------------------------------------------------------
    // Sequential State Register
    // ----------------------------------------------------------------
    always @(posedge clk) begin
        if (rst)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    // ----------------------------------------------------------------
    // Combinational Output Logic
    // ----------------------------------------------------------------
    // Fast-path hit detection in IDLE:
    wire hit_in_idle = (state == S_IDLE) && cpu_req && hit;
    wire hit_in_comp = (state == S_COMPARE_TAG) && hit;

    // CPU Ready: asserted on fast-path hit or in RESPOND state
    assign cpu_ready = hit_in_idle || (state == S_RESPOND);
    assign cpu_stall = cpu_req && !cpu_ready;

    always @(*) begin
        // Default control signal assignments
        tag_we        = 1'b0;
        valid_we      = 1'b0;
        valid_wdata   = 1'b0;
        data_we_word  = 1'b0;
        data_we_line  = 1'b0;
        mem_req       = 1'b0;
        mem_wr        = 1'b0;
        mem_addr      = {ADDR_WIDTH{1'b0}};
        mem_wdata     = {DATA_WIDTH{1'b0}};

        case (state)
            S_IDLE: begin
                if (cpu_req) begin
                    if (hit) begin
                        if (cpu_wr) begin
                            // Write hit: update cache word & forward to memory
                            data_we_word = 1'b1;
                            mem_req      = 1'b1;
                            mem_wr       = 1'b1;
                            mem_addr     = cpu_addr;
                            mem_wdata    = cpu_wdata;
                        end
                    end
                end
            end

            S_COMPARE_TAG: begin
                if (hit && saved_wr) begin
                    data_we_word = 1'b1;
                    mem_req      = 1'b1;
                    mem_wr       = 1'b1;
                    mem_addr     = saved_addr;
                    mem_wdata    = saved_wdata;
                end
            end

            S_ALLOCATE: begin
                mem_req   = 1'b1;
                mem_wr    = saved_wr;
                if (!saved_wr) begin
                    // Read refill: request block-aligned line from memory
                    mem_addr  = {saved_tag, saved_index, {OFFSET_BITS{1'b0}}};
                    mem_wdata = {DATA_WIDTH{1'b0}};
                end else begin
                    // Write miss: write-through single word to memory (no-write-allocate)
                    mem_addr  = saved_addr;
                    mem_wdata = saved_wdata;
                end
            end

            S_UPDATE: begin
                // Update cache with the refilled block from memory
                data_we_line = 1'b1;
                tag_we       = 1'b1;
                valid_we     = 1'b1;
                valid_wdata  = 1'b1;
            end

            S_RESPOND: begin
                // Ready signal is driven by assign cpu_ready
            end

            default: ;
        endcase
    end

endmodule
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

    reg [1:0]               mstate;
    reg [31:0]              lat_cnt;     // latency counter
    reg [31:0]              word_cnt;    // burst word counter
    reg [ADDR_WIDTH-1:0]    saved_addr;
    reg [DATA_WIDTH-1:0]    saved_wdata;
    reg                     saved_wr;
    reg [BLOCK_BITS-1:0]    rdata_build; // assembled block during burst

    always @(posedge clk) begin
        if (rst) begin
            mstate      <= S_MEM_IDLE;
            mem_ready   <= 1'b0;
            mem_rdata   <= {BLOCK_BITS{1'b0}};
            lat_cnt     <= 0;
            word_cnt    <= 0;
            rdata_build <= {BLOCK_BITS{1'b0}};
        end else begin
            mem_ready <= 1'b0;  // default: de-assert

            case (mstate)
                // -------------------------------------------------
                S_MEM_IDLE: begin
                    if (mem_req) begin
                        saved_addr  <= mem_addr;
                        saved_wdata <= mem_wdata;
                        saved_wr    <= mem_wr;
                        lat_cnt     <= 2;       // cycle 1 elapsed on request latch
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
                        rdata_build[word_cnt*DATA_WIDTH +: DATA_WIDTH] <=
                            mem_array[(saved_addr[ADDR_WIDTH-1:2] + word_cnt) % MEM_DEPTH];
                        word_cnt <= word_cnt + 1;

                        if (word_cnt + 1 >= WORDS_PER_BLK) begin
                            // All words collected — pack and signal ready
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
// cache_top.v -- Top-level integration of all cache modules
// Owner: Member 3 (Main-Memory Interface & Top-Level Integration)
//
// Instantiates and connects:
//   - address_decoder  (M1)  : splits CPU address into tag / index / offset
//   - tag_ram          (M1)  : stores tags
//   - valid_ram        (M1)  : stores valid bits
//   - data_ram         (M1)  : stores cache data lines
//   - tag_comparator   (M2)  : hit = valid && (stored_tag == request_tag)
//   - cache_controller_fsm (M2) : controller state machine
//   - mem_interface    (M3)  : bridges FSM ↔ main memory
//   - main_memory      (M3)  : behavioural main-memory model
//
// External interface (CPU side):
//   clk, rst, cpu_req, cpu_wr, cpu_addr, cpu_wdata  →  cpu_rdata, cpu_ready

`timescale 1ns/1ps

module cache_top #(
    parameter ADDR_WIDTH    = 32,
    parameter CACHE_SIZE    = 1024,
    parameter BLOCK_SIZE    = 16,
    parameter DATA_WIDTH    = 32,
    parameter MEM_FIRST_LAT = 10,
    parameter MEM_NEXT_LAT  = 1,
    // ---- derived: do NOT override, they follow the three above ----
    parameter NUM_LINES     = CACHE_SIZE / BLOCK_SIZE,
    parameter OFFSET_BITS   = $clog2(BLOCK_SIZE),
    parameter BYTE_OFF_BITS = 2,
    parameter WORD_SEL_BITS = OFFSET_BITS - BYTE_OFF_BITS,
    parameter INDEX_BITS    = $clog2(NUM_LINES),
    parameter TAG_BITS      = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS,
    parameter BLOCK_BITS    = BLOCK_SIZE * 8,
    parameter WORDS_PER_BLK = BLOCK_SIZE / 4
) (
    input  wire                     clk,
    input  wire                     rst,

    // CPU / Master interface
    input  wire                     cpu_req,
    input  wire                     cpu_wr,
    input  wire [ADDR_WIDTH-1:0]    cpu_addr,
    input  wire [DATA_WIDTH-1:0]    cpu_wdata,
    output wire [DATA_WIDTH-1:0]    cpu_rdata,
    output wire                     cpu_ready
);

    // ==================================================================
    // Internal wires
    // ==================================================================

    // Address decoder outputs
    wire [TAG_BITS-1:0]      dec_tag;
    wire [INDEX_BITS-1:0]    dec_index;
    wire [WORD_SEL_BITS-1:0] dec_word_sel;
    wire [BYTE_OFF_BITS-1:0] dec_byte_off;   // unused in Phase I

    // Tag RAM outputs
    wire [TAG_BITS-1:0]      stored_tag;

    // Valid RAM output
    wire                     stored_valid;

    // Data RAM outputs
    wire [DATA_WIDTH-1:0]    cache_rdata_word;
    wire [BLOCK_BITS-1:0]    cache_rdata_line; // unused externally

    // Tag comparator output
    wire                     hit;

    // FSM → storage control signals
    wire                     tag_we;
    wire                     valid_we;
    wire                     valid_wdata;
    wire                     data_we_word;
    wire                     data_we_line;

    // FSM → memory interface
    wire                     fsm_mem_req;
    wire                     fsm_mem_wr;
    wire [ADDR_WIDTH-1:0]    fsm_mem_addr;
    wire [DATA_WIDTH-1:0]    fsm_mem_wdata;
    wire                     fsm_mem_ready;

    // Memory interface → main memory
    wire                     mm_req;
    wire                     mm_wr;
    wire [ADDR_WIDTH-1:0]    mm_addr;
    wire [DATA_WIDTH-1:0]    mm_wdata;
    wire                     mm_ready;
    wire [BLOCK_BITS-1:0]    mm_rdata;

    // Refill data path (mem_interface → data_ram)
    wire [BLOCK_BITS-1:0]    refill_data;

    // FSM state (for monitoring / waveform)
    wire [2:0]               fsm_state;

    // ==================================================================
    // CPU read data — comes from the data RAM word output
    // ==================================================================
    assign cpu_rdata = cache_rdata_word;

    // ==================================================================
    // Module instantiations
    // ==================================================================

    // --- Address Decoder (M1) -----------------------------------------
    address_decoder #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .CACHE_SIZE (CACHE_SIZE),
        .BLOCK_SIZE (BLOCK_SIZE)
    ) u_addr_dec (
        .addr     (cpu_addr),
        .tag      (dec_tag),
        .index    (dec_index),
        .word_sel (dec_word_sel),
        .byte_off (dec_byte_off)
    );

    // --- Tag RAM (M1) -------------------------------------------------
    tag_ram #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .CACHE_SIZE (CACHE_SIZE),
        .BLOCK_SIZE (BLOCK_SIZE)
    ) u_tag_ram (
        .clk   (clk),
        .index (dec_index),
        .we    (tag_we),
        .wtag  (dec_tag),
        .rtag  (stored_tag)
    );

    // --- Valid RAM (M1) -----------------------------------------------
    valid_ram #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .CACHE_SIZE (CACHE_SIZE),
        .BLOCK_SIZE (BLOCK_SIZE)
    ) u_valid_ram (
        .clk    (clk),
        .rst    (rst),
        .flush  (1'b0),         // no flush in Phase I
        .index  (dec_index),
        .we     (valid_we),
        .wvalid (valid_wdata),
        .rvalid (stored_valid)
    );

    // --- Data RAM (M1) ------------------------------------------------
    data_ram #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .CACHE_SIZE (CACHE_SIZE),
        .BLOCK_SIZE (BLOCK_SIZE)
    ) u_data_ram (
        .clk        (clk),
        .index      (dec_index),
        .word_sel   (dec_word_sel),
        .we_word    (data_we_word),
        .wdata_word (cpu_wdata),
        .we_line    (data_we_line),
        .wdata_line (refill_data),
        .rdata_word (cache_rdata_word),
        .rdata_line (cache_rdata_line)
    );

    // --- Tag Comparator (M2) ------------------------------------------
    tag_comparator #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .CACHE_SIZE (CACHE_SIZE),
        .BLOCK_SIZE (BLOCK_SIZE)
    ) u_tag_cmp (
        .tag    (dec_tag),
        .rtag   (stored_tag),
        .rvalid (stored_valid),
        .hit    (hit)
    );

    // --- Cache Controller FSM (M2) ------------------------------------
    cache_controller_fsm #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .CACHE_SIZE (CACHE_SIZE),
        .BLOCK_SIZE (BLOCK_SIZE)
    ) u_fsm (
        .clk          (clk),
        .rst          (rst),

        // CPU side
        .cpu_req      (cpu_req),
        .cpu_wr       (cpu_wr),
        .cpu_addr     (cpu_addr),
        .cpu_wdata    (cpu_wdata),
        .cpu_ready    (cpu_ready),
        .cpu_stall    (),               // unused at top level (info only)

        // Tag comparator & decoder
        .tag          (dec_tag),
        .index        (dec_index),
        .hit          (hit),

        // Storage controls
        .tag_we       (tag_we),
        .valid_we     (valid_we),
        .valid_wdata  (valid_wdata),
        .data_we_word (data_we_word),
        .data_we_line (data_we_line),

        // Memory interface
        .mem_req      (fsm_mem_req),
        .mem_wr       (fsm_mem_wr),
        .mem_addr     (fsm_mem_addr),
        .mem_wdata    (fsm_mem_wdata),
        .mem_ready    (fsm_mem_ready),

        // Monitoring
        .fsm_state    (fsm_state)
    );

    // --- Memory Interface (M3) ----------------------------------------
    mem_interface #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .CACHE_SIZE (CACHE_SIZE),
        .BLOCK_SIZE (BLOCK_SIZE)
    ) u_mem_if (
        .clk            (clk),
        .rst            (rst),

        // FSM side
        .fsm_mem_req    (fsm_mem_req),
        .fsm_mem_wr     (fsm_mem_wr),
        .fsm_mem_addr   (fsm_mem_addr),
        .fsm_mem_wdata  (fsm_mem_wdata),
        .fsm_mem_ready  (fsm_mem_ready),

        // Refill data to data_ram
        .refill_data    (refill_data),

        // Main-memory side
        .mm_req         (mm_req),
        .mm_wr          (mm_wr),
        .mm_addr        (mm_addr),
        .mm_wdata       (mm_wdata),
        .mm_ready       (mm_ready),
        .mm_rdata       (mm_rdata)
    );

    // --- Main Memory (M3, behavioural) --------------------------------
    main_memory #(
        .ADDR_WIDTH    (ADDR_WIDTH),
        .CACHE_SIZE    (CACHE_SIZE),
        .BLOCK_SIZE    (BLOCK_SIZE),
        .MEM_FIRST_LAT (MEM_FIRST_LAT),
        .MEM_NEXT_LAT  (MEM_NEXT_LAT)
    ) u_main_mem (
        .clk       (clk),
        .rst       (rst),
        .mem_req   (mm_req),
        .mem_wr    (mm_wr),
        .mem_addr  (mm_addr),
        .mem_wdata (mm_wdata),
        .mem_ready (mm_ready),
        .mem_rdata (mm_rdata)
    );

endmodule

