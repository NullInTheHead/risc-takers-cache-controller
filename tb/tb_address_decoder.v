// tb_address_decoder.v -- self-checking test for address_decoder
// Owner: Member 1
// Checks the default 1 KB / 16 B config (22/6/2/2) and a second
// 2 KB / 32 B config (21/6/3/2) to prove the widths follow the parameters.

`timescale 1ns/1ps

module tb_address_decoder;
    integer errors = 0, checks = 0;

    // ---------- default config: 1 KB, 16 B blocks ----------
    reg  [31:0] addr;
    wire [21:0] tag;
    wire [5:0]  index;
    wire [1:0]  word_sel, byte_off;

    address_decoder dut (.addr(addr), .tag(tag), .index(index),
                         .word_sel(word_sel), .byte_off(byte_off));

    // ---------- alternate config: 2 KB, 32 B blocks ----------
    wire [20:0] tag2;
    wire [5:0]  index2;
    wire [2:0]  word_sel2;
    wire [1:0]  byte_off2;

    address_decoder #(.CACHE_SIZE(2048), .BLOCK_SIZE(32)) dut2 (
        .addr(addr), .tag(tag2), .index(index2),
        .word_sel(word_sel2), .byte_off(byte_off2));

    task check(input [31:0] a);
        begin
            addr = a; #1;
            checks = checks + 1;
            if (tag !== a[31:10] || index !== a[9:4] ||
                word_sel !== a[3:2] || byte_off !== a[1:0]) begin
                errors = errors + 1;
                $display("FAIL 1KB/16B addr=%h tag=%h idx=%0d word=%0d byte=%0d",
                         a, tag, index, word_sel, byte_off);
            end
            checks = checks + 1;
            if (tag2 !== a[31:11] || index2 !== a[10:5] ||
                word_sel2 !== a[4:2] || byte_off2 !== a[1:0]) begin
                errors = errors + 1;
                $display("FAIL 2KB/32B addr=%h", a);
            end
        end
    endtask

    integer k;
    initial begin
        $dumpfile("tb/waves/tb_address_decoder.vcd");
        $dumpvars(0, tb_address_decoder);

        // Hand-picked cases
        check(32'h0000_0000);
        check(32'hFFFF_FFFC);
        check(32'h0000_03F0);   // last line, word 0
        check(32'h0000_0400);   // wraps to index 0, tag 1 (1 KB apart)
        check(32'h1234_5678);
        check(32'hDEAD_BEEC);

        // Worked example printed for the report / video
        addr = 32'h1234_5678; #1;
        $display("Example: addr=0x%h -> tag=0x%h index=%0d word=%0d byte=%0d",
                 addr, tag, index, word_sel, byte_off);

        // Random sweep
        for (k = 0; k < 1000; k = k + 1)
            check($random);

        if (errors == 0) $display("PASS tb_address_decoder (%0d checks)", checks);
        else             $display("FAIL tb_address_decoder (%0d errors / %0d checks)", errors, checks);
        $finish;
    end
endmodule
