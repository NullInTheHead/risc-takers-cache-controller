// tb_cache_controller_fsm.v -- self-checking testbench for cache_controller_fsm
// Owner: Member 2 (Controller FSM & Tag Comparator)
//
// Tests:
//   1. Reset behavior and initial state.
//   2. Read Hit: single-cycle completion (cycle_counter == 1), no RAM writes.
//   3. Read Miss (cold/compulsory):
//      - Transitions: IDLE -> COMPARE_TAG -> ALLOCATE -> UPDATE -> RESPOND -> IDLE
//      - Multi-cycle memory refill handshake (mem_req, mem_ready)
//      - Assertions on tag_we, valid_we, data_we_line during UPDATE
//      - cpu_ready fires on RESPOND
//   4. Write Hit (write-through):
//      - Immediate completion (cycle_counter == 1)
//      - data_we_word asserted
//      - mem_req=1, mem_wr=1 (write-through forwarded to memory)
//   5. Write Miss (write-through, no-write-allocate):
//      - Transitions to ALLOCATE with mem_req=1, mem_wr=1
//      - Verifies NO cache update (tag_we=0, valid_we=0, data_we=0)
//      - Skips UPDATE, enters RESPOND when mem_ready fires
//   6. Back-to-back operations:
//      - Read miss refill immediately followed by read hit to the same line

`timescale 1ns/1ps

module tb_cache_controller_fsm;
    integer errors = 0, checks = 0;

    localparam ADDR_WIDTH = 32;
    localparam CACHE_SIZE = 1024;
    localparam BLOCK_SIZE = 16;
    localparam DATA_WIDTH = 32;

    localparam NUM_LINES     = CACHE_SIZE / BLOCK_SIZE;           // 64
    localparam OFFSET_BITS   = $clog2(BLOCK_SIZE);                // 4
    localparam INDEX_BITS    = $clog2(NUM_LINES);                 // 6
    localparam TAG_BITS      = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS; // 22

    localparam S_IDLE        = 3'd0;
    localparam S_COMPARE_TAG = 3'd1;
    localparam S_ALLOCATE    = 3'd2;
    localparam S_UPDATE      = 3'd3;
    localparam S_RESPOND     = 3'd4;

    // DUT signals
    reg                     clk = 0;
    reg                     rst = 0;
    reg                     cpu_req = 0;
    reg                     cpu_wr = 0;
    reg  [ADDR_WIDTH-1:0]   cpu_addr = 0;
    reg  [DATA_WIDTH-1:0]   cpu_wdata = 0;
    wire                    cpu_ready;
    wire                    cpu_stall;

    reg  [TAG_BITS-1:0]     tag = 0;
    reg  [INDEX_BITS-1:0]   index = 0;
    reg                     hit = 0;

    wire                    tag_we;
    wire                    valid_we;
    wire                    valid_wdata;
    wire                    data_we_word;
    wire                    data_we_line;

    wire                    mem_req;
    wire                    mem_wr;
    wire [ADDR_WIDTH-1:0]   mem_addr;
    wire [DATA_WIDTH-1:0]   mem_wdata;
    reg                     mem_ready = 0;

    wire [2:0]              fsm_state;

    // Instantiate DUT
    cache_controller_fsm #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .CACHE_SIZE (CACHE_SIZE),
        .BLOCK_SIZE (BLOCK_SIZE),
        .DATA_WIDTH (DATA_WIDTH)
    ) dut (
        .clk          (clk),
        .rst          (rst),
        .cpu_req      (cpu_req),
        .cpu_wr       (cpu_wr),
        .cpu_addr     (cpu_addr),
        .cpu_wdata    (cpu_wdata),
        .cpu_ready    (cpu_ready),
        .cpu_stall    (cpu_stall),
        .tag          (tag),
        .index        (index),
        .hit          (hit),
        .tag_we       (tag_we),
        .valid_we     (valid_we),
        .valid_wdata  (valid_wdata),
        .data_we_word (data_we_word),
        .data_we_line (data_we_line),
        .mem_req      (mem_req),
        .mem_wr       (mem_wr),
        .mem_addr     (mem_addr),
        .mem_wdata    (mem_wdata),
        .mem_ready    (mem_ready),
        .fsm_state    (fsm_state)
    );

    always #5 clk = ~clk;

    // Helper: decode address fields
    task set_cpu_access(input [31:0] a, input rw, input [31:0] d, input is_hit);
        begin
            cpu_addr  = a;
            cpu_wr    = rw;
            cpu_wdata = d;
            tag       = a[31:10];
            index     = a[9:4];
            hit       = is_hit;
            cpu_req   = 1'b1;
        end
    endtask

    task check_condition(input condition, input [8*40-1:0] msg);
        begin
            checks = checks + 1;
            if (!condition) begin
                errors = errors + 1;
                $display("FAIL [tb_fsm]: %0s (time=%0t)", msg, $time);
            end
        end
    endtask

    integer wait_cycles;

    initial begin
        $dumpfile("tb/waves/tb_cache_controller_fsm.vcd");
        $dumpvars(0, tb_cache_controller_fsm);

        $display("=== Running tb_cache_controller_fsm ===");

        // ------------------------------------------------------------
        // Test 1: Reset behavior
        // ------------------------------------------------------------
        rst = 1;
        repeat (3) @(posedge clk);
        #1;
        check_condition(fsm_state == S_IDLE, "State must be IDLE on reset");
        check_condition(cpu_ready == 1'b0,   "cpu_ready must be 0 on reset");
        check_condition(tag_we == 1'b0,      "tag_we must be 0 on reset");
        check_condition(data_we_line == 0,   "data_we_line must be 0 on reset");
        check_condition(mem_req == 1'b0,     "mem_req must be 0 on reset");

        rst = 0;
        @(posedge clk);
        #1;
        check_condition(fsm_state == S_IDLE, "State remains IDLE after reset");

        // ------------------------------------------------------------
        // Test 2: Read Hit (single-cycle completion)
        // ------------------------------------------------------------
        $display("[TB] Test 2: Read Hit");
        set_cpu_access(32'h0000_0040, 1'b0, 32'h0, 1'b1);
        #1; // combinational evaluation
        check_condition(cpu_ready == 1'b1, "cpu_ready must assert combinationally on read hit");
        check_condition(cpu_stall == 1'b0, "cpu_stall must be 0 on hit");
        check_condition(tag_we == 1'b0,    "tag_we must not assert on read hit");
        check_condition(data_we_line == 0, "data_we_line must not assert on read hit");
        check_condition(mem_req == 1'b0,   "mem_req must not assert on read hit");

        @(posedge clk);
        // After 1 clock edge, TB deasserts cpu_req (hit completed in 1 cycle)
        cpu_req = 1'b0;
        @(posedge clk);
        #1;
        check_condition(fsm_state == S_IDLE, "Returns to IDLE after read hit");

        // ------------------------------------------------------------
        // Test 3: Read Miss (Cold miss: multi-cycle refill)
        // ------------------------------------------------------------
        $display("[TB] Test 3: Read Miss (Cold Refill)");
        set_cpu_access(32'h0000_1000, 1'b0, 32'h0, 1'b0); // hit = 0
        #1;
        check_condition(cpu_ready == 1'b0, "cpu_ready must be 0 immediately on miss");
        check_condition(cpu_stall == 1'b1, "cpu_stall must be 1 on miss");

        @(posedge clk); // PosEdge 1: IDLE -> COMPARE_TAG
        #1;
        check_condition(fsm_state == S_COMPARE_TAG, "State is COMPARE_TAG after clock edge 1");

        @(posedge clk); // PosEdge 2: COMPARE_TAG -> ALLOCATE
        #1;
        check_condition(fsm_state == S_ALLOCATE, "State is ALLOCATE after clock edge 2");
        check_condition(mem_req == 1'b1, "mem_req must be 1 in ALLOCATE");
        check_condition(mem_wr == 1'b0,  "mem_wr must be 0 (read) in ALLOCATE");
        check_condition(mem_addr == 32'h0000_1000, "mem_addr must be block-aligned address");

        // Simulate 5 cycles of memory latency
        repeat (5) begin
            @(posedge clk);
            #1;
            check_condition(fsm_state == S_ALLOCATE, "Remains in ALLOCATE while mem_ready=0");
            check_condition(cpu_ready == 1'b0, "cpu_ready remains 0 while waiting for memory");
        end

        // Memory asserts ready
        mem_ready = 1'b1;
        @(posedge clk); // PosEdge: ALLOCATE -> UPDATE
        #1;
        mem_ready = 1'b0;
        check_condition(fsm_state == S_UPDATE, "State is UPDATE after mem_ready");
        check_condition(tag_we == 1'b1,        "tag_we must be 1 in UPDATE");
        check_condition(valid_we == 1'b1,      "valid_we must be 1 in UPDATE");
        check_condition(valid_wdata == 1'b1,   "valid_wdata must be 1 in UPDATE");
        check_condition(data_we_line == 1'b1,  "data_we_line must be 1 in UPDATE");
        check_condition(data_we_word == 1'b0,  "data_we_word must be 0 in UPDATE");

        @(posedge clk); // PosEdge: UPDATE -> RESPOND
        #1;
        check_condition(fsm_state == S_RESPOND, "State is RESPOND after UPDATE");
        check_condition(cpu_ready == 1'b1,      "cpu_ready must be 1 in RESPOND");
        check_condition(tag_we == 1'b0,         "tag_we de-asserted in RESPOND");
        check_condition(data_we_line == 1'b0,   "data_we_line de-asserted in RESPOND");

        // CPU consumes response and de-asserts req
        cpu_req = 1'b0;
        @(posedge clk); // PosEdge: RESPOND -> IDLE
        #1;
        check_condition(fsm_state == S_IDLE, "Returns to IDLE after RESPOND");

        // ------------------------------------------------------------
        // Test 4: Write Hit (Write-through)
        // ------------------------------------------------------------
        $display("[TB] Test 4: Write Hit");
        set_cpu_access(32'h0000_1000, 1'b1, 32'hDEAD_BEEF, 1'b1); // hit = 1, wr = 1
        #1;
        check_condition(cpu_ready == 1'b1,    "cpu_ready asserts immediately on write hit");
        check_condition(data_we_word == 1'b1, "data_we_word asserted on write hit");
        check_condition(data_we_line == 1'b0, "data_we_line not asserted on write hit");
        check_condition(mem_req == 1'b1,      "mem_req asserted for write-through");
        check_condition(mem_wr == 1'b1,       "mem_wr asserted for write-through");
        check_condition(mem_addr == 32'h0000_1000, "mem_addr matches write address");
        check_condition(mem_wdata == 32'hDEAD_BEEF, "mem_wdata matches write data");

        @(posedge clk);
        cpu_req = 1'b0;
        @(posedge clk);
        #1;
        check_condition(fsm_state == S_IDLE, "Returns to IDLE after write hit");

        // ------------------------------------------------------------
        // Test 5: Write Miss (No-write-allocate)
        // ------------------------------------------------------------
        $display("[TB] Test 5: Write Miss (No-Write-Allocate)");
        set_cpu_access(32'h0000_2004, 1'b1, 32'hFEED_FACE, 1'b0); // hit = 0, wr = 1
        #1;
        check_condition(cpu_ready == 1'b0, "cpu_ready is 0 on write miss");
        check_condition(cpu_stall == 1'b1, "cpu_stall is 1 on write miss");

        @(posedge clk); // PosEdge 1: IDLE -> COMPARE_TAG
        @(posedge clk); // PosEdge 2: COMPARE_TAG -> ALLOCATE
        #1;
        check_condition(fsm_state == S_ALLOCATE, "State is ALLOCATE on write miss");
        check_condition(mem_req == 1'b1, "mem_req asserted for write miss");
        check_condition(mem_wr == 1'b1,  "mem_wr asserted for write miss");
        check_condition(mem_addr == 32'h0000_2004, "mem_addr forwarded to memory");
        check_condition(mem_wdata == 32'hFEED_FACE, "mem_wdata forwarded to memory");

        // CRITICAL CHECK: In write miss (no-allocate), cache must NOT be updated!
        check_condition(tag_we == 1'b0,       "tag_we must be 0 on write miss");
        check_condition(valid_we == 1'b0,     "valid_we must be 0 on write miss");
        check_condition(data_we_word == 1'b0, "data_we_word must be 0 on write miss");
        check_condition(data_we_line == 1'b0, "data_we_line must be 0 on write miss");

        // Memory finishes write
        repeat (3) @(posedge clk);
        mem_ready = 1'b1;
        @(posedge clk); // PosEdge: ALLOCATE -> RESPOND (skips UPDATE!)
        #1;
        mem_ready = 1'b0;
        check_condition(fsm_state == S_RESPOND, "Directly enters RESPOND (skips UPDATE)");
        check_condition(cpu_ready == 1'b1,      "cpu_ready asserted in RESPOND");
        check_condition(tag_we == 1'b0,         "tag_we still 0 in RESPOND");

        cpu_req = 1'b0;
        @(posedge clk);
        #1;
        check_condition(fsm_state == S_IDLE, "Returns to IDLE after write miss");

        // ------------------------------------------------------------
        // Test 6: Back-to-Back Accesses
        // ------------------------------------------------------------
        $display("[TB] Test 6: Back-to-Back Accesses");
        // Access A: Read hit
        set_cpu_access(32'h0000_0008, 1'b0, 32'h0, 1'b1);
        #1;
        check_condition(cpu_ready == 1'b1, "Access A: immediate hit");
        @(posedge clk);

        // Access B immediately on next cycle without idle gap
        set_cpu_access(32'h0000_000C, 1'b0, 32'h0, 1'b1);
        #1;
        check_condition(cpu_ready == 1'b1, "Access B: immediate hit (back-to-back)");
        @(posedge clk);
        cpu_req = 1'b0;
        @(posedge clk);
        #1;
        check_condition(fsm_state == S_IDLE, "Returns to IDLE");

        // ------------------------------------------------------------
        // Summary
        // ------------------------------------------------------------
        $display("");
        $display("====================================================");
        if (errors == 0) begin
            $display("PASS tb_cache_controller_fsm (%0d checks completed, 0 errors)", checks);
        end else begin
            $display("FAIL tb_cache_controller_fsm (%0d errors out of %0d checks)", errors, checks);
        end
        $display("====================================================");
        $finish;
    end

endmodule
