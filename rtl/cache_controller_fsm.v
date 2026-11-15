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
