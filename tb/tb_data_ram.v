// tb_data_ram.v -- self-checking test for data_ram
// Owner: Member 1
// Tests: line write + word reads, single-word write leaves other words
// intact, line-over-word priority, no cross-line corruption, full fill.

`timescale 1ns/1ps

module tb_data_ram;
    integer errors = 0, checks = 0;

    reg          clk = 0;
    reg  [5:0]   index = 0;
    reg  [1:0]   word_sel = 0;
    reg          we_word = 0, we_line = 0;
    reg  [31:0]  wdata_word = 0;
    reg  [127:0] wdata_line = 0;
    wire [31:0]  rdata_word;
    wire [127:0] rdata_line;

    data_ram dut (.clk(clk), .index(index), .word_sel(word_sel),
                  .we_word(we_word), .wdata_word(wdata_word),
                  .we_line(we_line), .wdata_line(wdata_line),
                  .rdata_word(rdata_word), .rdata_line(rdata_line));

    always #5 clk = ~clk;

    task expect_word(input [5:0] i, input [1:0] w, input [31:0] exp);
        begin
            index = i; word_sel = w; #1;
            checks = checks + 1;
            if (rdata_word !== exp) begin
                errors = errors + 1;
                $display("FAIL line %0d word %0d: got %h exp %h", i, w, rdata_word, exp);
            end
        end
    endtask

    task write_line(input [5:0] i, input [127:0] d);
        begin
            @(negedge clk); index = i; wdata_line = d; we_line = 1;
            @(negedge clk); we_line = 0;
        end
    endtask

    task write_word(input [5:0] i, input [1:0] w, input [31:0] d);
        begin
            @(negedge clk); index = i; word_sel = w; wdata_word = d; we_word = 1;
            @(negedge clk); we_word = 0;
        end
    endtask

    function [127:0] pattern(input [5:0] i);
        pattern = {8'hA0 | i[3:0], 18'd0, i, 8'hB0 | i[3:0], 18'd0, i,
                   8'hC0 | i[3:0], 18'd0, i, 8'hD0 | i[3:0], 18'd0, i};
    endfunction

    integer i, w;
    initial begin
        $dumpfile("tb/waves/tb_data_ram.vcd");
        $dumpvars(0, tb_data_ram);

        // 1. Refill line 5, read each word (word 0 = bits [31:0])
        write_line(6'd5, {32'h3333_3333, 32'h2222_2222, 32'h1111_1111, 32'h0000_0000});
        expect_word(5, 0, 32'h0000_0000);
        expect_word(5, 1, 32'h1111_1111);
        expect_word(5, 2, 32'h2222_2222);
        expect_word(5, 3, 32'h3333_3333);

        // 2. Write-hit on word 2 only; words 0,1,3 must not change
        write_word(6'd5, 2'd2, 32'hCAFE_F00D);
        expect_word(5, 0, 32'h0000_0000);
        expect_word(5, 1, 32'h1111_1111);
        expect_word(5, 2, 32'hCAFE_F00D);
        expect_word(5, 3, 32'h3333_3333);

        // 3. we_line has priority over we_word
        @(negedge clk);
        index = 6'd7; word_sel = 2'd0;
        wdata_line = {4{32'hAAAA_AAAA}}; we_line = 1;
        wdata_word = 32'h5555_5555;       we_word = 1;
        @(negedge clk); we_line = 0; we_word = 0;
        expect_word(7, 0, 32'hAAAA_AAAA);

        // 4. Writing line 6 must not touch line 5
        write_line(6'd6, {4{32'hFFFF_FFFF}});
        expect_word(5, 2, 32'hCAFE_F00D);

        // 5. Fill all 64 lines with a unique pattern and read everything back
        for (i = 0; i < 64; i = i + 1) write_line(i[5:0], pattern(i[5:0]));
        for (i = 0; i < 64; i = i + 1)
            for (w = 0; w < 4; w = w + 1)
                expect_word(i[5:0], w[1:0], pattern(i[5:0]) >> (32*w));

        if (errors == 0) $display("PASS tb_data_ram (%0d checks)", checks);
        else             $display("FAIL tb_data_ram (%0d errors / %0d checks)", errors, checks);
        $finish;
    end
endmodule
