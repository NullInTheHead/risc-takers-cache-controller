// tb_mem_interface.v -- Self-checking unit testbench for mem_interface.v
// Owner: Member 3 (Main-Memory Interface & Top-Level Integration)

`timescale 1ns/1ps

module tb_mem_interface;

    parameter ADDR_WIDTH    = 32;
    parameter CACHE_SIZE    = 1024;
    parameter BLOCK_SIZE    = 16;
    parameter MEM_FIRST_LAT = 10;
    parameter MEM_NEXT_LAT  = 1;

    localparam DATA_WIDTH    = 32;
    localparam BLOCK_BITS    = BLOCK_SIZE * 8;

    reg                     clk;
    reg                     rst;

    // FSM side
    reg                     fsm_mem_req;
    reg                     fsm_mem_wr;
    reg  [ADDR_WIDTH-1:0]   fsm_mem_addr;
    reg  [DATA_WIDTH-1:0]   fsm_mem_wdata;
    wire                    fsm_mem_ready;
    wire [BLOCK_BITS-1:0]   refill_data;

    // Main-memory side
    wire                    mm_req;
    wire                    mm_wr;
    wire [ADDR_WIDTH-1:0]   mm_addr;
    wire [DATA_WIDTH-1:0]   mm_wdata;
    wire                    mm_ready;
    wire [BLOCK_BITS-1:0]   mm_rdata;

    // Instantiate mem_interface
    mem_interface #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .CACHE_SIZE (CACHE_SIZE),
        .BLOCK_SIZE (BLOCK_SIZE)
    ) u_mem_if (
        .clk           (clk),
        .rst           (rst),
        .fsm_mem_req   (fsm_mem_req),
        .fsm_mem_wr    (fsm_mem_wr),
        .fsm_mem_addr  (fsm_mem_addr),
        .fsm_mem_wdata (fsm_mem_wdata),
        .fsm_mem_ready (fsm_mem_ready),
        .refill_data   (refill_data),
        .mm_req        (mm_req),
        .mm_wr         (mm_wr),
        .mm_addr       (mm_addr),
        .mm_wdata      (mm_wdata),
        .mm_ready      (mm_ready),
        .mm_rdata      (mm_rdata)
    );

    // Instantiate main_memory
    main_memory #(
        .ADDR_WIDTH    (ADDR_WIDTH),
        .CACHE_SIZE    (CACHE_SIZE),
        .BLOCK_SIZE    (BLOCK_SIZE),
        .MEM_FIRST_LAT (MEM_FIRST_LAT),
        .MEM_NEXT_LAT  (MEM_NEXT_LAT)
    ) u_main_mem (
        .clk       (clk),
        .rst       (rst),
        .mem_req   (mm_req),
        .mem_wr    (mm_wr),
        .mem_addr  (mm_addr),
        .mem_wdata (mm_wdata),
        .mem_ready (mm_ready),
        .mem_rdata (mm_rdata)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer errors = 0;
    integer cyc;

    initial begin
        fsm_mem_req   = 0;
        fsm_mem_wr    = 0;
        fsm_mem_addr  = 0;
        fsm_mem_wdata = 0;

        rst = 1;
        repeat (5) @(posedge clk);
        rst = 0;
        @(posedge clk);

        // Test 1: Read Refill Handshake
        // FSM asserts fsm_mem_req continuously during ALLOCATE state
        fsm_mem_req  = 1'b1;
        fsm_mem_wr   = 1'b0;
        fsm_mem_addr = 32'h0000_0200;
        cyc = 0;

        @(posedge clk);
        cyc = cyc + 1;
        while (!fsm_mem_ready) begin
            @(posedge clk);
            cyc = cyc + 1;
        end

        // FSM drops fsm_mem_req on the edge following fsm_mem_ready
        fsm_mem_req = 1'b0;
        @(posedge clk);

        if (refill_data[31:0] !== 32'h0000_0200) begin
            $display("FAIL: refill_data word 0 mismatch. Got 0x%08h", refill_data[31:0]);
            errors = errors + 1;
        end else begin
            $display("PASS: Read refill completed with valid data");
        end

        // Verify that memory does NOT retrigger (mm_req must be 0)
        repeat (5) begin
            @(posedge clk);
            if (mm_req !== 1'b0 || u_main_mem.mstate !== 2'd0) begin
                $display("FAIL: Phantom retrigger detected! mm_req=%b mstate=%0d", mm_req, u_main_mem.mstate);
                errors = errors + 1;
            end
        end

        // Test 2: Write-through Handshake
        fsm_mem_req   = 1'b1;
        fsm_mem_wr    = 1'b1;
        fsm_mem_addr  = 32'h0000_0204;
        fsm_mem_wdata = 32'h1234_5678;

        @(posedge clk);
        while (!fsm_mem_ready) @(posedge clk);
        fsm_mem_req = 1'b0;
        @(posedge clk);

        if (u_main_mem.mem_array[32'h0000_0204 >> 2] !== 32'h1234_5678) begin
            $display("FAIL: Write-through data not written into main memory");
            errors = errors + 1;
        end else begin
            $display("PASS: Write-through completed successfully");
        end

        if (errors == 0)
            $display("PASS: tb_mem_interface - all tests passed cleanly");
        else
            $display("FAIL: tb_mem_interface - %0d error(s)", errors);

        $finish;
    end

endmodule
