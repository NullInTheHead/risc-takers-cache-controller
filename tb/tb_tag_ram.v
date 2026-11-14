// tb_tag_ram.v -- self-checking test for tag_ram
// Owner: Member 1

`timescale 1ns/1ps

module tb_tag_ram;
    integer errors = 0, checks = 0;

    reg         clk = 0;
    reg  [5:0]  index = 0;
    reg         we = 0;
    reg  [21:0] wtag = 0;
    wire [21:0] rtag;

    tag_ram dut (.clk(clk), .index(index), .we(we), .wtag(wtag), .rtag(rtag));

    always #5 clk = ~clk;

    function [21:0] tag_of(input [5:0] i);
        tag_of = {i, 10'h2A5, i} ^ 22'h15_5555;   // unique per line
    endfunction

    task write_tag(input [5:0] i, input [21:0] t);
        begin
            @(negedge clk); index = i; wtag = t; we = 1;
            @(negedge clk); we = 0;
        end
    endtask

    task expect_tag(input [5:0] i, input [21:0] exp);
        begin
            index = i; #1; checks = checks + 1;
            if (rtag !== exp) begin
                errors = errors + 1;
                $display("FAIL tag[%0d]: got %h exp %h", i, rtag, exp);
            end
        end
    endtask

    integer i;
    initial begin
        $dumpfile("tb/waves/tb_tag_ram.vcd");
        $dumpvars(0, tb_tag_ram);

        // 1. Write a unique tag into every line, read all back
        for (i = 0; i < 64; i = i + 1) write_tag(i[5:0], tag_of(i[5:0]));
        for (i = 0; i < 64; i = i + 1) expect_tag(i[5:0], tag_of(i[5:0]));

        // 2. Overwrite line 10 (models a conflict-miss refill); others untouched
        write_tag(6'd10, 22'h3F_FFFF);
        expect_tag(10, 22'h3F_FFFF);
        expect_tag(9,  tag_of(6'd9));
        expect_tag(11, tag_of(6'd11));

        // 3. we = 0 must not write
        @(negedge clk); index = 6'd20; wtag = 22'h00_0001; we = 0;
        @(negedge clk);
        expect_tag(20, tag_of(6'd20));

        if (errors == 0) $display("PASS tb_tag_ram (%0d checks)", checks);
        else             $display("FAIL tb_tag_ram (%0d errors / %0d checks)", errors, checks);
        $finish;
    end
endmodule
