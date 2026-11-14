// cache_tb.v -- system-level trace-driven testbench for cache_top
// Owner: Member 4 (Verification & Memory-Access Traces)
//
// Loads a memory-access trace from a hex file and feeds each entry to the
// cache_top module one at a time.  Tracks hit/miss statistics and writes
// per-access results to both the console and a log file for comparison
// with the Python reference model.
//
// Trace format (one hex value per line, 33 bits encoded in 9 hex digits):
//   bit [32]    : 0 = read, 1 = write
//   bits [31:0] : byte address (word-aligned)
//
// Select a trace at compile time:
//   iverilog -DTRACE_FILE=\"traces/loop.mem\" ...
//
// Hit/miss determination: count the number of cycles cpu_req is held
// high until cpu_ready fires.  1 cycle => hit; >1 cycle => miss.

`timescale 1ns/1ps

module cache_tb;

    // ----------------------------------------------------------------
    // Parameters
    // ----------------------------------------------------------------
    parameter ADDR_WIDTH    = 32;
    parameter CACHE_SIZE    = 1024;       // bytes
    parameter BLOCK_SIZE    = 16;         // bytes per cache line
    parameter DATA_WIDTH    = 32;
    parameter MEM_FIRST_LAT = 10;         // main-memory first-word latency
    parameter MEM_NEXT_LAT  = 1;          // main-memory subsequent-word latency
    parameter MAX_TRACE     = 1024;       // max entries in trace file

    // Derived (must match cache_top / address_decoder derivation)
    localparam NUM_LINES    = CACHE_SIZE / BLOCK_SIZE;           // 64
    localparam OFFSET_BITS  = $clog2(BLOCK_SIZE);                // 4
    localparam INDEX_BITS   = $clog2(NUM_LINES);                 // 6
    localparam TAG_BITS     = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS; // 22
    localparam BLOCK_BITS   = BLOCK_SIZE * 8;                    // 128
    localparam WORDS_PER_BLK = BLOCK_SIZE / 4;                   // 4

    // Clock period
    localparam CLK_PERIOD   = 10;         // ns  (5 ns high + 5 ns low)
    localparam HALF_PERIOD  = CLK_PERIOD / 2;

    // Trace file — overridable at compile time
    `ifndef TRACE_FILE
        `define TRACE_FILE "traces/sequential.mem"
    `endif

    // ----------------------------------------------------------------
    // Clock & reset
    // ----------------------------------------------------------------
    reg clk;
    reg rst;

    initial clk = 1'b0;
    always #(HALF_PERIOD) clk = ~clk;

    // ----------------------------------------------------------------
    // DUT signals
    // ----------------------------------------------------------------
    reg                     cpu_req;
    reg                     cpu_wr;
    reg  [ADDR_WIDTH-1:0]   cpu_addr;
    reg  [DATA_WIDTH-1:0]   cpu_wdata;
    wire [DATA_WIDTH-1:0]   cpu_rdata;
    wire                    cpu_ready;

    // ----------------------------------------------------------------
    // Instantiate DUT
    // ----------------------------------------------------------------
    cache_top #(
        .ADDR_WIDTH    (ADDR_WIDTH),
        .CACHE_SIZE    (CACHE_SIZE),
        .BLOCK_SIZE    (BLOCK_SIZE),
        .DATA_WIDTH    (DATA_WIDTH),
        .MEM_FIRST_LAT (MEM_FIRST_LAT),
        .MEM_NEXT_LAT  (MEM_NEXT_LAT)
    ) dut (
        .clk       (clk),
        .rst       (rst),
        .cpu_req   (cpu_req),
        .cpu_wr    (cpu_wr),
        .cpu_addr  (cpu_addr),
        .cpu_wdata (cpu_wdata),
        .cpu_rdata (cpu_rdata),
        .cpu_ready (cpu_ready)
    );

    // ----------------------------------------------------------------
    // Trace storage
    // ----------------------------------------------------------------
    // Each entry is 33 bits: { rw (1 bit), address (32 bits) }
    reg [32:0] trace_mem [0:MAX_TRACE-1];

    // ----------------------------------------------------------------
    // Statistics counters
    // ----------------------------------------------------------------
    integer total_accesses;
    integer read_hits;
    integer read_misses;
    integer write_hits;
    integer write_misses;
    integer total_cycles;       // clock cycles from first to last access
    integer cycle_counter;      // per-access cycle count
    integer first_access_time;  // $time at first access posedge
    integer last_access_time;   // $time at last access completion

    // ----------------------------------------------------------------
    // Log file handle
    // ----------------------------------------------------------------
    integer log_fd;

    // ----------------------------------------------------------------
    // Loop / temp variables
    // ----------------------------------------------------------------
    integer trace_idx;
    reg     current_rw;         // 0 = read, 1 = write
    reg [ADDR_WIDTH-1:0] current_addr;

    // ----------------------------------------------------------------
    // Waveform dump
    // ----------------------------------------------------------------
    initial begin
        $dumpfile("tb/waves/cache_tb.vcd");
        $dumpvars(0, cache_tb);
    end

    // ----------------------------------------------------------------
    // Main stimulus
    // ----------------------------------------------------------------
    initial begin
        // -- Initialise signals ------------------------------------------
        cpu_req   = 1'b0;
        cpu_wr    = 1'b0;
        cpu_addr  = {ADDR_WIDTH{1'b0}};
        cpu_wdata = {DATA_WIDTH{1'b0}};

        total_accesses = 0;
        read_hits      = 0;
        read_misses    = 0;
        write_hits     = 0;
        write_misses   = 0;
        total_cycles   = 0;
        first_access_time = 0;
        last_access_time  = 0;

        // -- Load trace --------------------------------------------------
        $readmemh(`TRACE_FILE, trace_mem);

        // -- Open log file -----------------------------------------------
        log_fd = $fopen("results/rtl_results.log", "w");
        if (log_fd == 0) begin
            $display("ERROR: could not open results/rtl_results.log for writing");
            $finish;
        end

        // -- Reset -------------------------------------------------------
        rst = 1'b1;
        repeat (5) @(posedge clk);
        rst = 1'b0;
        @(posedge clk);  // one idle cycle after reset de-assert

        // -- Feed trace entries ------------------------------------------
        begin : trace_loop
            for (trace_idx = 0; trace_idx < MAX_TRACE; trace_idx = trace_idx + 1) begin

                // End-of-trace detection: stop when the entry is all X
                if (trace_mem[trace_idx] === {33{1'bx}}) begin
                    $display("[TB] End of trace detected at entry %0d.", trace_idx);
                    disable trace_loop;
                end

                // Record timestamp of first access
                if (trace_idx == 0)
                    first_access_time = $time;

                // Decode trace entry
                current_rw   = trace_mem[trace_idx][32];
                current_addr = trace_mem[trace_idx][31:0];

                // Drive DUT inputs
                cpu_wr    = current_rw;
                cpu_addr  = current_addr;
                cpu_wdata = current_addr + 32'hCAFE_0000;  // simple write-data pattern
                cpu_req   = 1'b1;

                // Wait for cpu_ready, counting cycles
                cycle_counter = 0;
                begin : wait_ready
                    forever begin
                        @(posedge clk);
                        cycle_counter = cycle_counter + 1;
                        if (cpu_ready === 1'b1)
                            disable wait_ready;
                    end
                end

                // Record last-access completion time
                last_access_time = $time;

                // Determine hit or miss
                if (cycle_counter == 1) begin
                    // HIT
                    if (current_rw == 1'b0)
                        read_hits = read_hits + 1;
                    else
                        write_hits = write_hits + 1;

                    $display("[TB] Access %0d: %s  addr=0x%08h  HIT   (%0d cycle)",
                             trace_idx, (current_rw ? "WR" : "RD"),
                             current_addr, cycle_counter);
                    $fwrite(log_fd, "H\n");
                end else begin
                    // MISS
                    if (current_rw == 1'b0)
                        read_misses = read_misses + 1;
                    else
                        write_misses = write_misses + 1;

                    $display("[TB] Access %0d: %s  addr=0x%08h  MISS  (%0d cycles)",
                             trace_idx, (current_rw ? "WR" : "RD"),
                             current_addr, cycle_counter);
                    $fwrite(log_fd, "M\n");
                end

                total_accesses = total_accesses + 1;

                // De-assert cpu_req for one idle cycle before next access
                cpu_req = 1'b0;
                @(posedge clk);
            end
        end // trace_loop

        // -- Compute total cycles ----------------------------------------
        total_cycles = (last_access_time - first_access_time) / CLK_PERIOD;

        // -- Summary -----------------------------------------------------
        $display("");
        $display("====================================================");
        $display("              CACHE TESTBENCH SUMMARY");
        $display("====================================================");
        $display("  Trace file      : %s", `TRACE_FILE);
        $display("  Total accesses  : %0d", total_accesses);
        $display("  Read  hits      : %0d", read_hits);
        $display("  Read  misses    : %0d", read_misses);
        $display("  Write hits      : %0d", write_hits);
        $display("  Write misses    : %0d", write_misses);
        $display("  Total hits      : %0d", read_hits + write_hits);
        $display("  Total misses    : %0d", read_misses + write_misses);
        if (total_accesses > 0)
            $display("  Hit rate        : %0d%%",
                     (read_hits + write_hits) * 100 / total_accesses);
        else
            $display("  Hit rate        : N/A (no accesses)");
        $display("  Total cycles    : %0d", total_cycles);
        $display("====================================================");
        $display("");

        // -- Clean up ----------------------------------------------------
        $fclose(log_fd);
        $finish;
    end

    // ----------------------------------------------------------------
    // Safety timeout — prevent infinite simulation
    // ----------------------------------------------------------------
    initial begin
        #(CLK_PERIOD * 500_000);
        $display("[TB] ERROR: simulation timed out after %0d cycles", 500_000);
        $fclose(log_fd);
        $finish;
    end

endmodule
