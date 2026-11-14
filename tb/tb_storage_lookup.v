// tb_storage_lookup.v -- storage-path demo: decoder + tag/valid/data RAMs
// Owner: Member 1
//
// Shows that the Member-1 storage supports a full lookup before the FSM
// exists. The hit equation is written inline here; in the real design it
// lives in tag_comparator.v (Member 2) and the refill is driven by the FSM.
//
// Scenario (good for the Phase I video):
//   1. 0x0000_0040 after reset          -> MISS (cold, valid = 0) -> refill
//   2. 0x0000_0044 (same block)         -> HIT  (spatial locality)
//   3. 0x0000_0440 (same index, +1 KB)  -> MISS (conflict) -> refill evicts
//   4. 0x0000_0040 again                -> MISS (evicted by step 3)
//   5. flush, then 0x0000_0040          -> MISS (valid cleared)

`timescale 1ns/1ps

module tb_storage_lookup;
    integer errors = 0, hits = 0, misses = 0;

    reg          clk = 0, rst = 0, flush = 0;
    reg  [31:0]  addr = 0;
    reg          refill = 0;
    reg  [127:0] mem_line = 0;

    wire [21:0]  tag, rtag;
    wire [5:0]   index;
    wire [1:0]   word_sel, byte_off;
    wire         rvalid;
    wire [31:0]  rdata_word;
    wire [127:0] rdata_line;

    address_decoder dec (.addr(addr), .tag(tag), .index(index),
                         .word_sel(word_sel), .byte_off(byte_off));

    tag_ram   tags  (.clk(clk), .index(index), .we(refill), .wtag(tag), .rtag(rtag));
    valid_ram valid (.clk(clk), .rst(rst), .flush(flush), .index(index),
                     .we(refill), .wvalid(1'b1), .rvalid(rvalid));
    data_ram  data  (.clk(clk), .index(index), .word_sel(word_sel),
                     .we_word(1'b0), .wdata_word(32'd0),
                     .we_line(refill), .wdata_line(mem_line),
                     .rdata_word(rdata_word), .rdata_line(rdata_line));

    wire hit = rvalid && (rtag == tag);     // M2's tag_comparator equation

    always #5 clk = ~clk;

    // Fake main memory: each word's value is its own byte address
    function [127:0] mem_block(input [31:0] a);
        reg [31:0] base;
        begin
            base = {a[31:4], 4'b0000};
            mem_block = {base + 32'd12, base + 32'd8, base + 32'd4, base};
        end
    endfunction

    task access(input [31:0] a, input exp_hit, input [8*24-1:0] note);
        begin
            @(negedge clk); addr = a; #1;
            if (hit !== exp_hit) begin
                errors = errors + 1;
                $display("FAIL addr=%h expected %s", a, exp_hit ? "HIT" : "MISS");
            end
            if (hit) begin
                hits = hits + 1;
                $display("%h  tag=%h idx=%2d word=%0d  HIT   data=%h  %0s",
                         a, tag, index, word_sel, rdata_word, note);
                if (rdata_word !== a) begin
                    errors = errors + 1;
                    $display("FAIL wrong data on hit");
                end
            end else begin
                misses = misses + 1;
                $display("%h  tag=%h idx=%2d word=%0d  MISS  -> refill    %0s",
                         a, tag, index, word_sel, note);
                mem_line = mem_block(a); refill = 1;
                @(negedge clk); refill = 0; #1;
                if (!hit || rdata_word !== a) begin
                    errors = errors + 1;
                    $display("FAIL line not usable after refill");
                end
            end
        end
    endtask

    initial begin
        $dumpfile("tb/waves/tb_storage_lookup.vcd");
        $dumpvars(0, tb_storage_lookup);

        rst = 1; @(negedge clk); @(negedge clk); rst = 0;

        $display("address   fields                      result");
        access(32'h0000_0040, 1'b0, "cold miss");
        access(32'h0000_0044, 1'b1, "spatial locality");
        access(32'h0000_0048, 1'b1, "spatial locality");
        access(32'h0000_0440, 1'b0, "conflict (+1 KB)");
        access(32'h0000_0040, 1'b0, "evicted by conflict");
        access(32'h0000_0040, 1'b1, "temporal locality");
        @(negedge clk); flush = 1; @(negedge clk); flush = 0;
        access(32'h0000_0040, 1'b0, "after flush");

        $display("hits=%0d misses=%0d", hits, misses);
        if (errors == 0) $display("PASS tb_storage_lookup");
        else             $display("FAIL tb_storage_lookup (%0d errors)", errors);
        $finish;
    end
endmodule
