// tb_valid_ram.v -- self-checking test for valid_ram
// Owner: Member 1
// Tests: reset clears all, set/clear individual bits, flush, rst > we priority.

`timescale 1ns/1ps

module tb_valid_ram;
    integer errors = 0, checks = 0;

    reg        clk = 0, rst = 0, flush = 0, we = 0, wvalid = 0;
    reg  [5:0] index = 0;
    wire       rvalid;

    valid_ram dut (.clk(clk), .rst(rst), .flush(flush), .index(index),
                   .we(we), .wvalid(wvalid), .rvalid(rvalid));

    always #5 clk = ~clk;

    task expect_v(input [5:0] i, input exp);
        begin
            index = i; #1; checks = checks + 1;
            if (rvalid !== exp) begin
                errors = errors + 1;
                $display("FAIL valid[%0d]: got %b exp %b", i, rvalid, exp);
            end
        end
    endtask

    task set_v(input [5:0] i, input v);
        begin
            @(negedge clk); index = i; wvalid = v; we = 1;
            @(negedge clk); we = 0;
        end
    endtask

    task expect_all(input exp);
        integer j;
        begin
            for (j = 0; j < 64; j = j + 1) expect_v(j[5:0], exp);
        end
    endtask

    integer i;
    initial begin
        $dumpfile("tb/waves/tb_valid_ram.vcd");
        $dumpvars(0, tb_valid_ram);

        // 1. Reset -> every line invalid
        rst = 1; @(negedge clk); @(negedge clk); rst = 0;
        expect_all(1'b0);

        // 2. Set even lines only
        for (i = 0; i < 64; i = i + 2) set_v(i[5:0], 1'b1);
        for (i = 0; i < 64; i = i + 1) expect_v(i[5:0], (i % 2 == 0));

        // 3. Clear one line
        set_v(6'd4, 1'b0);
        expect_v(4, 1'b0);
        expect_v(6, 1'b1);

        // 4. Flush invalidates everything
        @(negedge clk); flush = 1; @(negedge clk); flush = 0;
        expect_all(1'b0);

        // 5. Reset beats a simultaneous write
        set_v(6'd33, 1'b1);
        @(negedge clk); rst = 1; index = 6'd34; wvalid = 1; we = 1;
        @(negedge clk); rst = 0; we = 0;
        expect_v(33, 1'b0);
        expect_v(34, 1'b0);

        if (errors == 0) $display("PASS tb_valid_ram (%0d checks)", checks);
        else             $display("FAIL tb_valid_ram (%0d errors / %0d checks)", errors, checks);
        $finish;
    end
endmodule
