// tb_main_memory.v -- Self-checking unit testbench for main_memory.v
// Owner: Member 3 (Main-Memory Interface & Top-Level Integration)

`timescale 1ns/1ps

module tb_main_memory;

    parameter ADDR_WIDTH    = 32;
    parameter CACHE_SIZE    = 1024;
    parameter BLOCK_SIZE    = 16;
    parameter MEM_FIRST_LAT = 10;
    parameter MEM_NEXT_LAT  = 1;

    localparam DATA_WIDTH    = 32;
    localparam BLOCK_BITS    = BLOCK_SIZE * 8;
    localparam WORDS_PER_BLK = BLOCK_SIZE / 4;

    reg                     clk;
    reg                     rst;
    reg                     mem_req;
    reg                     mem_wr;
    reg  [ADDR_WIDTH-1:0]   mem_addr;
    reg  [DATA_WIDTH-1:0]   mem_wdata;
    wire                    mem_ready;
    wire [BLOCK_BITS-1:0]   mem_rdata;

    main_memory #(
        .ADDR_WIDTH    (ADDR_WIDTH),
        .CACHE_SIZE    (CACHE_SIZE),
        .BLOCK_SIZE    (BLOCK_SIZE),
        .MEM_FIRST_LAT (MEM_FIRST_LAT),
        .MEM_NEXT_LAT  (MEM_NEXT_LAT)
    ) dut (
        .clk       (clk),
        .rst       (rst),
        .mem_req   (mem_req),
        .mem_wr    (mem_wr),
        .mem_addr  (mem_addr),
        .mem_wdata (mem_wdata),
        .mem_ready (mem_ready),
        .mem_rdata (mem_rdata)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer errors = 0;
    integer latency_count;

    task do_read_block(input [31:0] addr, output [127:0] rdata, output integer cycles);
        begin
            @(posedge clk);
            mem_req   = 1'b1;
            mem_wr    = 1'b0;
            mem_addr  = addr;
            mem_wdata = 32'h0;
            cycles    = 0;

            @(posedge clk);
            mem_req = 1'b0; // pulse request
            cycles  = cycles + 1;

            while (!mem_ready) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            rdata = mem_rdata;
            @(posedge clk);
        end
    endtask

    task do_write_word(input [31:0] addr, input [31:0] wdata, output integer cycles);
        begin
            @(posedge clk);
            mem_req   = 1'b1;
            mem_wr    = 1'b1;
            mem_addr  = addr;
            mem_wdata = wdata;
            cycles    = 0;

            @(posedge clk);
            mem_req = 1'b0;
            cycles  = cycles + 1;

            while (!mem_ready) begin
                @(posedge clk);
                cycles = cycles + 1;
            end
            @(posedge clk);
        end
    endtask

    reg [127:0] block_out;
    integer cyc;

    initial begin
        mem_req   = 0;
        mem_wr    = 0;
        mem_addr  = 0;
        mem_wdata = 0;

        rst = 1;
        repeat (5) @(posedge clk);
        rst = 0;
        @(posedge clk);

        // Test 1: Read block at 0x0000_0100 (words 0x40, 0x41, 0x42, 0x43)
        // Expected latency = 10 + 3*1 = 13 cycles
        do_read_block(32'h0000_0100, block_out, cyc);
        if (cyc !== 13) begin
            $display("FAIL: Read latency was %0d cycles, expected 13", cyc);
            errors = errors + 1;
        end else begin
            $display("PASS: Read burst latency is exactly 13 cycles");
        end

        // Check word contents: default pattern is word_addr * 4
        if (block_out[31:0]   !== 32'h0000_0100 ||
            block_out[63:32]  !== 32'h0000_0104 ||
            block_out[95:64]  !== 32'h0000_0108 ||
            block_out[127:96] !== 32'h0000_010C) begin
            $display("FAIL: Block data mismatch. Got 0x%032h", block_out);
            errors = errors + 1;
        end else begin
            $display("PASS: All 4 words in block match initialization pattern");
        end

        // Test 2: Write word at 0x0000_0104
        // Expected write latency = MEM_FIRST_LAT = 10 cycles
        do_write_word(32'h0000_0104, 32'hBEEF_CAFE, cyc);
        if (cyc !== 10) begin
            $display("FAIL: Write latency was %0d cycles, expected 10", cyc);
            errors = errors + 1;
        end else begin
            $display("PASS: Write latency is exactly 10 cycles");
        end

        // Test 3: Read back block to verify written word
        do_read_block(32'h0000_0100, block_out, cyc);
        if (block_out[63:32] !== 32'hBEEF_CAFE) begin
            $display("FAIL: Written word not reflected in read block! Got 0x%08h", block_out[63:32]);
            errors = errors + 1;
        end else begin
            $display("PASS: Written word verified via block read");
        end

        if (errors == 0)
            $display("PASS: tb_main_memory - all tests passed cleanly");
        else
            $display("FAIL: tb_main_memory - %0d error(s)", errors);

        $finish;
    end

endmodule
