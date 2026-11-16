// cache_top.v -- Top-level integration of all cache modules
// Owner: Member 3 (Main-Memory Interface & Top-Level Integration)
//
// Instantiates and connects:
//   - address_decoder  (M1)  : splits CPU address into tag / index / offset
//   - tag_ram          (M1)  : stores tags
//   - valid_ram        (M1)  : stores valid bits
//   - data_ram         (M1)  : stores cache data lines
//   - tag_comparator   (M2)  : hit = valid && (stored_tag == request_tag)
//   - cache_controller_fsm (M2) : controller state machine
//   - mem_interface    (M3)  : bridges FSM ↔ main memory
//   - main_memory      (M3)  : behavioural main-memory model
//
// External interface (CPU side):
//   clk, rst, cpu_req, cpu_wr, cpu_addr, cpu_wdata  →  cpu_rdata, cpu_ready

`timescale 1ns/1ps

module cache_top #(
    parameter ADDR_WIDTH    = 32,
    parameter CACHE_SIZE    = 1024,
    parameter BLOCK_SIZE    = 16,
    parameter DATA_WIDTH    = 32,
    parameter MEM_FIRST_LAT = 10,
    parameter MEM_NEXT_LAT  = 1,
    // ---- derived: do NOT override, they follow the three above ----
    parameter NUM_LINES     = CACHE_SIZE / BLOCK_SIZE,
    parameter OFFSET_BITS   = $clog2(BLOCK_SIZE),
    parameter BYTE_OFF_BITS = 2,
    parameter WORD_SEL_BITS = OFFSET_BITS - BYTE_OFF_BITS,
    parameter INDEX_BITS    = $clog2(NUM_LINES),
    parameter TAG_BITS      = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS,
    parameter BLOCK_BITS    = BLOCK_SIZE * 8,
    parameter WORDS_PER_BLK = BLOCK_SIZE / 4
) (
    input  wire                     clk,
    input  wire                     rst,

    // CPU / Master interface
    input  wire                     cpu_req,
    input  wire                     cpu_wr,
    input  wire [ADDR_WIDTH-1:0]    cpu_addr,
    input  wire [DATA_WIDTH-1:0]    cpu_wdata,
    output wire [DATA_WIDTH-1:0]    cpu_rdata,
    output wire                     cpu_ready
);

    // ==================================================================
    // Internal wires
    // ==================================================================

    // Address decoder outputs
    wire [TAG_BITS-1:0]      dec_tag;
    wire [INDEX_BITS-1:0]    dec_index;
    wire [WORD_SEL_BITS-1:0] dec_word_sel;
    wire [BYTE_OFF_BITS-1:0] dec_byte_off;   // unused in Phase I

    // Tag RAM outputs
    wire [TAG_BITS-1:0]      stored_tag;

    // Valid RAM output
    wire                     stored_valid;

    // Data RAM outputs
    wire [DATA_WIDTH-1:0]    cache_rdata_word;
    wire [BLOCK_BITS-1:0]    cache_rdata_line; // unused externally

    // Tag comparator output
    wire                     hit;

    // FSM → storage control signals
    wire                     tag_we;
    wire                     valid_we;
    wire                     valid_wdata;
    wire                     data_we_word;
    wire                     data_we_line;

    // FSM → memory interface
    wire                     fsm_mem_req;
    wire                     fsm_mem_wr;
    wire [ADDR_WIDTH-1:0]    fsm_mem_addr;
    wire [DATA_WIDTH-1:0]    fsm_mem_wdata;
    wire                     fsm_mem_ready;

    // Memory interface → main memory
    wire                     mm_req;
    wire                     mm_wr;
    wire [ADDR_WIDTH-1:0]    mm_addr;
    wire [DATA_WIDTH-1:0]    mm_wdata;
    wire                     mm_ready;
    wire [BLOCK_BITS-1:0]    mm_rdata;

    // Refill data path (mem_interface → data_ram)
    wire [BLOCK_BITS-1:0]    refill_data;

    // FSM state (for monitoring / waveform)
    wire [2:0]               fsm_state;

    // ==================================================================
    // CPU read data — comes from the data RAM word output
    // ==================================================================
    assign cpu_rdata = cache_rdata_word;

    // ==================================================================
    // Module instantiations
    // ==================================================================

    // --- Address Decoder (M1) -----------------------------------------
    address_decoder #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .CACHE_SIZE (CACHE_SIZE),
        .BLOCK_SIZE (BLOCK_SIZE)
    ) u_addr_dec (
        .addr     (cpu_addr),
        .tag      (dec_tag),
        .index    (dec_index),
        .word_sel (dec_word_sel),
        .byte_off (dec_byte_off)
    );

    // --- Tag RAM (M1) -------------------------------------------------
    tag_ram #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .CACHE_SIZE (CACHE_SIZE),
        .BLOCK_SIZE (BLOCK_SIZE)
    ) u_tag_ram (
        .clk   (clk),
        .index (dec_index),
        .we    (tag_we),
        .wtag  (dec_tag),
        .rtag  (stored_tag)
    );

    // --- Valid RAM (M1) -----------------------------------------------
    valid_ram #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .CACHE_SIZE (CACHE_SIZE),
        .BLOCK_SIZE (BLOCK_SIZE)
    ) u_valid_ram (
        .clk    (clk),
        .rst    (rst),
        .flush  (1'b0),         // no flush in Phase I
        .index  (dec_index),
        .we     (valid_we),
        .wvalid (valid_wdata),
        .rvalid (stored_valid)
    );

    // --- Data RAM (M1) ------------------------------------------------
    data_ram #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .CACHE_SIZE (CACHE_SIZE),
        .BLOCK_SIZE (BLOCK_SIZE)
    ) u_data_ram (
        .clk        (clk),
        .index      (dec_index),
        .word_sel   (dec_word_sel),
        .we_word    (data_we_word),
        .wdata_word (cpu_wdata),
        .we_line    (data_we_line),
        .wdata_line (refill_data),
        .rdata_word (cache_rdata_word),
        .rdata_line (cache_rdata_line)
    );

    // --- Tag Comparator (M2) ------------------------------------------
    tag_comparator #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .CACHE_SIZE (CACHE_SIZE),
        .BLOCK_SIZE (BLOCK_SIZE)
    ) u_tag_cmp (
        .tag    (dec_tag),
        .rtag   (stored_tag),
        .rvalid (stored_valid),
        .hit    (hit)
    );

    // --- Cache Controller FSM (M2) ------------------------------------
    cache_controller_fsm #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .CACHE_SIZE (CACHE_SIZE),
        .BLOCK_SIZE (BLOCK_SIZE)
    ) u_fsm (
        .clk          (clk),
        .rst          (rst),

        // CPU side
        .cpu_req      (cpu_req),
        .cpu_wr       (cpu_wr),
        .cpu_addr     (cpu_addr),
        .cpu_wdata    (cpu_wdata),
        .cpu_ready    (cpu_ready),
        .cpu_stall    (),               // unused at top level (info only)

        // Tag comparator & decoder
        .tag          (dec_tag),
        .index        (dec_index),
        .hit          (hit),

        // Storage controls
        .tag_we       (tag_we),
        .valid_we     (valid_we),
        .valid_wdata  (valid_wdata),
        .data_we_word (data_we_word),
        .data_we_line (data_we_line),

        // Memory interface
        .mem_req      (fsm_mem_req),
        .mem_wr       (fsm_mem_wr),
        .mem_addr     (fsm_mem_addr),
        .mem_wdata    (fsm_mem_wdata),
        .mem_ready    (fsm_mem_ready),

        // Monitoring
        .fsm_state    (fsm_state)
    );

    // --- Memory Interface (M3) ----------------------------------------
    mem_interface #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .CACHE_SIZE (CACHE_SIZE),
        .BLOCK_SIZE (BLOCK_SIZE)
    ) u_mem_if (
        .clk            (clk),
        .rst            (rst),

        // FSM side
        .fsm_mem_req    (fsm_mem_req),
        .fsm_mem_wr     (fsm_mem_wr),
        .fsm_mem_addr   (fsm_mem_addr),
        .fsm_mem_wdata  (fsm_mem_wdata),
        .fsm_mem_ready  (fsm_mem_ready),

        // Refill data to data_ram
        .refill_data    (refill_data),

        // Main-memory side
        .mm_req         (mm_req),
        .mm_wr          (mm_wr),
        .mm_addr        (mm_addr),
        .mm_wdata       (mm_wdata),
        .mm_ready       (mm_ready),
        .mm_rdata       (mm_rdata)
    );

    // --- Main Memory (M3, behavioural) --------------------------------
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

endmodule
