// tb_tag_comparator.v -- self-checking testbench for tag_comparator
// Owner: Member 2 (Controller FSM & Tag Comparator)
//
// Tests:
//   1. Default parameters (22-bit tag):
//      - Cold miss: valid = 0, tags match      -> hit must be 0
//      - Cold miss: valid = 0, tags mismatch   -> hit must be 0
//      - Valid hit: valid = 1, tags match      -> hit must be 1
//      - Valid miss: valid = 1, tags mismatch  -> hit must be 0
//      - Extreme values (all 0s, all 1s, alternating bit patterns)
//      - Single-bit differences (walking 1s)
//   2. Overridden parameters (2 KB cache, 32 B block -> 21-bit tag):
//      - Hits and misses under parameter sweep

`timescale 1ns/1ps

module tb_tag_comparator;
    integer errors = 0, checks = 0;

    // ----------------------------------------------------------------
    // Instance 1: Default configuration (1 KB cache, 16 B block -> 22-bit tag)
    // ----------------------------------------------------------------
    reg  [21:0] tag1;
    reg  [21:0] rtag1;
    reg         rvalid1;
    wire        hit1;

    tag_comparator #(
        .ADDR_WIDTH(32),
        .CACHE_SIZE(1024),
        .BLOCK_SIZE(16)
    ) dut_default (
        .tag    (tag1),
        .rtag   (rtag1),
        .rvalid (rvalid1),
        .hit    (hit1)
    );

    // ----------------------------------------------------------------
    // Instance 2: Scaled configuration (2 KB cache, 32 B block -> 21-bit tag)
    // ----------------------------------------------------------------
    reg  [20:0] tag2;
    reg  [20:0] rtag2;
    reg         rvalid2;
    wire        hit2;

    tag_comparator #(
        .ADDR_WIDTH(32),
        .CACHE_SIZE(2048),
        .BLOCK_SIZE(32)
    ) dut_scaled (
        .tag    (tag2),
        .rtag   (rtag2),
        .rvalid (rvalid2),
        .hit    (hit2)
    );

    task check_default(
        input [21:0] t,
        input [21:0] rt,
        input        v,
        input        exp_hit,
        input [8*28-1:0] note
    );
        begin
            tag1 = t; rtag1 = rt; rvalid1 = v;
            #1;
            checks = checks + 1;
            if (hit1 !== exp_hit) begin
                errors = errors + 1;
                $display("FAIL [default] tag=%h rtag=%h v=%b got hit=%b exp=%b (%0s)",
                         t, rt, v, hit1, exp_hit, note);
            end
        end
    endtask

    task check_scaled(
        input [20:0] t,
        input [20:0] rt,
        input        v,
        input        exp_hit,
        input [8*28-1:0] note
    );
        begin
            tag2 = t; rtag2 = rt; rvalid2 = v;
            #1;
            checks = checks + 1;
            if (hit2 !== exp_hit) begin
                errors = errors + 1;
                $display("FAIL [scaled] tag=%h rtag=%h v=%b got hit=%b exp=%b (%0s)",
                         t, rt, v, hit2, exp_hit, note);
            end
        end
    endtask

    integer b;
    reg [21:0] base_tag;

    initial begin
        $dumpfile("tb/waves/tb_tag_comparator.vcd");
        $dumpvars(0, tb_tag_comparator);

        $display("=== Running tb_tag_comparator ===");

        // ------------------------------------------------------------
        // Part 1: Default configuration checks
        // ------------------------------------------------------------
        // Cold misses: valid=0 MUST block hit, even when tags match
        check_default(22'h00_0000, 22'h00_0000, 1'b0, 1'b0, "cold miss: zero tag");
        check_default(22'h3F_FFFF, 22'h3F_FFFF, 1'b0, 1'b0, "cold miss: all-1s tag");
        check_default(22'h15_5555, 22'h15_5555, 1'b0, 1'b0, "cold miss: matching tag");
        check_default(22'h15_5555, 22'h2A_AAAA, 1'b0, 1'b0, "cold miss: mismatch tag");

        // Valid hits: valid=1 AND tags match exactly
        check_default(22'h00_0000, 22'h00_0000, 1'b1, 1'b1, "hit: all zeros");
        check_default(22'h3F_FFFF, 22'h3F_FFFF, 1'b1, 1'b1, "hit: all ones");
        check_default(22'h15_5555, 22'h15_5555, 1'b1, 1'b1, "hit: pattern 0x155555");
        check_default(22'h2A_AAAA, 22'h2A_AAAA, 1'b1, 1'b1, "hit: pattern 0x2AAAAA");
        check_default(22'h12_3456, 22'h12_3456, 1'b1, 1'b1, "hit: realistic tag");

        // Valid misses (conflict / capacity): valid=1 BUT tags mismatch
        check_default(22'h00_0000, 22'h00_0001, 1'b1, 1'b0, "miss: LSB difference");
        check_default(22'h20_0000, 22'h00_0000, 1'b1, 1'b0, "miss: MSB difference");
        check_default(22'h15_5555, 22'h2A_AAAA, 1'b1, 1'b0, "miss: inverted bits");
        check_default(22'h3F_FFFF, 22'h3F_FFFE, 1'b1, 1'b0, "miss: 1 bit difference");

        // Walking bit tests: single-bit difference across all 22 bit positions
        base_tag = 22'h1A_B0C3;
        for (b = 0; b < 22; b = b + 1) begin
            // Exact match -> hit
            check_default(base_tag ^ (1 << b), base_tag ^ (1 << b), 1'b1, 1'b1, "hit: bit sweep match");
            // 1 bit flipped between request and stored -> miss
            check_default(base_tag, base_tag ^ (1 << b), 1'b1, 1'b0, "miss: bit sweep flipped");
        end

        // ------------------------------------------------------------
        // Part 2: Scaled configuration checks (21-bit tag)
        // ------------------------------------------------------------
        check_scaled(21'h00_0000, 21'h00_0000, 1'b0, 1'b0, "scaled: cold miss");
        check_scaled(21'h1F_FFFF, 21'h1F_FFFF, 1'b1, 1'b1, "scaled: all-1s hit");
        check_scaled(21'h0A_AAAA, 21'h0A_AAAA, 1'b1, 1'b1, "scaled: valid hit");
        check_scaled(21'h0A_AAAA, 21'h0A_AAAB, 1'b1, 1'b0, "scaled: mismatch");

        // ------------------------------------------------------------
        // Summary
        // ------------------------------------------------------------
        if (errors == 0) begin
            $display("PASS tb_tag_comparator (%0d checks completed, 0 errors)", checks);
        end else begin
            $display("FAIL tb_tag_comparator (%0d errors out of %0d checks)", errors, checks);
        end
        $finish;
    end

endmodule
