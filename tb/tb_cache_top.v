// tb_cache_top.v -- Self-checking integration testbench for cache_top.v
// Owner: Member 3 (Main-Memory Interface & Top-Level Integration)

`timescale 1ns/1ps

module tb_cache_top;

    parameter ADDR_WIDTH    = 32;
    parameter CACHE_SIZE    = 1024;
    parameter BLOCK_SIZE    = 16;
    parameter DATA_WIDTH    = 32;
    parameter MEM_FIRST_LAT = 10;
    parameter MEM_NEXT_LAT  = 1;

    reg                     clk;
    reg                     rst;
    reg                     cpu_req;
    reg                     cpu_wr;
    reg  [ADDR_WIDTH-1:0]   cpu_addr;
    reg  [DATA_WIDTH-1:0]   cpu_wdata;
    wire [DATA_WIDTH-1:0]   cpu_rdata;
    wire                    cpu_ready;

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

    initial clk = 0;
    always #5 clk = ~clk;

    integer errors = 0;

    task cpu_access(input rw, input [31:0] addr, input [31:0] wdata, output [31:0] rdata, output integer cycles);
        begin
            cpu_req   = 1'b1;
            cpu_wr    = rw;
            cpu_addr  = addr;
            cpu_wdata = wdata;
            cycles    = 0;

            @(posedge clk);
            cycles = cycles + 1;
            while (!cpu_ready) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            rdata   = cpu_rdata;
            cpu_req = 1'b0;
            cpu_wr  = 1'b0;
            @(posedge clk); // idle gap
        end
    endtask

    reg [31:0] rd_data;
    integer cyc;

    initial begin
        cpu_req   = 0;
        cpu_wr    = 0;
        cpu_addr  = 0;
        cpu_wdata = 0;

        rst = 1;
        repeat (5) @(posedge clk);
        rst = 0;
        @(posedge clk);

        // -------------------------------------------------------------
        // 1. Cold Read Miss
        // -------------------------------------------------------------
        cpu_access(0, 32'h0000_0100, 32'h0, rd_data, cyc);
        if (rd_data !== 32'h0000_0100) begin
            $display("FAIL: Cold read miss data mismatch. Got 0x%08h, expected 0x100", rd_data);
            errors = errors + 1;
        end
        if (cyc !== 19) begin
            $display("FAIL: Cold read miss took %0d cycles, expected 19", cyc);
            errors = errors + 1;
        end else begin
            $display("PASS: Cold read miss completed in 19 cycles with correct data");
        end

        // -------------------------------------------------------------
        // 2. Read Hit (same word)
        // -------------------------------------------------------------
        cpu_access(0, 32'h0000_0100, 32'h0, rd_data, cyc);
        if (rd_data !== 32'h0000_0100 || cyc !== 1) begin
            $display("FAIL: Read hit failed. cyc=%0d, data=0x%08h", cyc, rd_data);
            errors = errors + 1;
        end else begin
            $display("PASS: Read hit completed in 1 cycle");
        end

        // -------------------------------------------------------------
        // 3. Spatial Locality (other words in the same 16B block)
        // -------------------------------------------------------------
        cpu_access(0, 32'h0000_0104, 32'h0, rd_data, cyc);
        if (rd_data !== 32'h0000_0104 || cyc !== 1) errors = errors + 1;

        cpu_access(0, 32'h0000_0108, 32'h0, rd_data, cyc);
        if (rd_data !== 32'h0000_0108 || cyc !== 1) errors = errors + 1;

        cpu_access(0, 32'h0000_010C, 32'h0, rd_data, cyc);
        if (rd_data !== 32'h0000_010C || cyc !== 1) errors = errors + 1;

        if (errors == 0)
            $display("PASS: All 3 remaining block words hit in 1 cycle (spatial locality)");

        // -------------------------------------------------------------
        // 4. Write Hit (write-through)
        // -------------------------------------------------------------
        cpu_access(1, 32'h0000_0100, 32'hDEAD_BEEF, rd_data, cyc);
        if (cyc !== 1) begin
            $display("FAIL: Write hit took %0d cycles, expected 1", cyc);
            errors = errors + 1;
        end

        // Wait for write-through to finish in main memory
        repeat (15) @(posedge clk);

        // Read cache: must have new data
        cpu_access(0, 32'h0000_0100, 32'h0, rd_data, cyc);
        if (rd_data !== 32'hDEAD_BEEF || cyc !== 1) begin
            $display("FAIL: Cache did not retain written word. Got 0x%08h", rd_data);
            errors = errors + 1;
        end

        // Check main memory backing store
        if (dut.u_main_mem.mem_array[32'h0000_0100 >> 2] !== 32'hDEAD_BEEF) begin
            $display("FAIL: Write-through did not update main memory");
            errors = errors + 1;
        end else begin
            $display("PASS: Write hit updated cache and main memory (write-through)");
        end

        // -------------------------------------------------------------
        // 5. Write Miss (no-write-allocate)
        // -------------------------------------------------------------
        // Address 0x500 has index 16 (same as 0x100), but different tag (tag 1 vs 0)
        cpu_access(1, 32'h0000_0500, 32'hCAFE_BABE, rd_data, cyc);

        // Main memory must be updated
        if (dut.u_main_mem.mem_array[32'h0000_0500 >> 2] !== 32'hCAFE_BABE) begin
            $display("FAIL: Write miss did not update main memory");
            errors = errors + 1;
        end

        // Cache line must NOT be replaced (index 16 must still hold tag 0 of 0x100)
        if (dut.u_tag_ram.mem[16] !== 22'd0) begin
            $display("FAIL: Cache line replaced on write miss (violated no-write-allocate)");
            errors = errors + 1;
        end else begin
            $display("PASS: Write miss wrote through to memory without allocating in cache");
        end

        // -------------------------------------------------------------
        // 6. Conflict Miss & Thrashing (addresses exactly 1 KB apart)
        // -------------------------------------------------------------
        // 0x100 and 0x500 are exactly 1024 bytes (1 KB) apart, mapping to index 16.
        // Reading 0x500 will evict 0x100.
        cpu_access(0, 32'h0000_0500, 32'h0, rd_data, cyc);
        if (rd_data !== 32'hCAFE_BABE || cyc !== 19) begin
            $display("FAIL: Conflict read miss failed. cyc=%0d, data=0x%08h", cyc, rd_data);
            errors = errors + 1;
        end

        // Line 16 now holds tag 1 (0x500). Reading 0x100 again must miss.
        cpu_access(0, 32'h0000_0100, 32'h0, rd_data, cyc);
        if (cyc !== 19) begin
            $display("FAIL: Re-access to 0x100 was expected to miss, took %0d cycles", cyc);
            errors = errors + 1;
        end else begin
            $display("PASS: Conflict miss / thrashing behavior verified (1 KB aliasing)");
        end

        // -------------------------------------------------------------
        // Final Status
        // -------------------------------------------------------------
        if (errors == 0)
            $display("PASS: tb_cache_top - all integration tests passed cleanly");
        else
            $display("FAIL: tb_cache_top - %0d error(s)", errors);

        $finish;
    end

endmodule
