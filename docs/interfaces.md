# Interface Specification (frozen for Phase I)

Owner: Member 1. Everyone codes against this file. If you need a change, raise it
in the group first, then update this file in the same commit as the RTL change.

## 1. Parameters

| Parameter     | Default | Meaning                          |
|---------------|---------|----------------------------------|
| `ADDR_WIDTH`  | 32      | CPU address width (byte address) |
| `DATA_WIDTH`  | 32      | Word size (fixed at 32)          |
| `CACHE_SIZE`  | 1024    | Cache data capacity in bytes     |
| `BLOCK_SIZE`  | 16      | Block (line) size in bytes       |

Derived values. Every module declares these as extra parameters after the
three above, with defaults computed from them. **Only ever override
`ADDR_WIDTH`, `CACHE_SIZE`, `BLOCK_SIZE`**; never override or hard-code the
derived ones. Copy the parameter block from any M1 module into your own module.

| Name            | Formula                                  | Default |
|-----------------|------------------------------------------|---------|
| `NUM_LINES`     | `CACHE_SIZE / BLOCK_SIZE`                | 64      |
| `WORDS_PER_BLK` | `BLOCK_SIZE / 4`                         | 4       |
| `OFFSET_BITS`   | `$clog2(BLOCK_SIZE)`                     | 4       |
| `BYTE_OFF_BITS` | 2                                        | 2       |
| `WORD_SEL_BITS` | `OFFSET_BITS - 2`                        | 2       |
| `INDEX_BITS`    | `$clog2(NUM_LINES)`                      | 6       |
| `TAG_BITS`      | `ADDR_WIDTH - INDEX_BITS - OFFSET_BITS`  | 22      |
| `BLOCK_BITS`    | `BLOCK_SIZE * 8`                         | 128     |

Constraints: `CACHE_SIZE` and `BLOCK_SIZE` must be powers of two, and
`BLOCK_SIZE >= 8` (at least 2 words per block).

Address layout (defaults):

```
 31                     10 9        4 3      2 1     0
+-------------------------+----------+--------+-------+
|        TAG (22)         | INDEX (6)| WORD(2)| BYTE(2)|
+-------------------------+----------+--------+-------+
```

## 2. Global conventions

- **Clock:** single clock `clk`, all writes on the rising edge.
- **Reset:** `rst`, synchronous, active-high. Only `valid_ram` needs it; all
  valid bits are cleared on reset.
- **Accesses:** 32-bit, word-aligned (`addr[1:0] == 2'b00`). No byte writes in
  Phase I.
- **Reads:** all storage RAMs read **combinationally** (asynchronous read).
  Tag, valid bit and data for the current `index` are available in the same
  cycle, so the comparator can decide hit/miss in one cycle.
- **Write policy (Phase I):** write-through, no-write-allocate.
  - Write hit: update the word in the cache **and** send it to memory.
  - Write miss: send it to memory only; cache unchanged.
  - Read miss: refill the whole line from memory, write tag, set valid.
- **Main-memory latency (for AMAT):** 10 cycles for the first word,
  1 cycle for each following word -> refill of a 4-word block = 13 cycles.
  (Owner: Member 3. Must stay parameterised as `MEM_FIRST_LAT`, `MEM_NEXT_LAT`.)

## 3. Module ports (Member 1)

### `address_decoder` (combinational)

| Port       | Dir | Width           | Description          |
|------------|-----|-----------------|----------------------|
| `addr`     | in  | `ADDR_WIDTH`    | CPU byte address     |
| `tag`      | out | `TAG_BITS`      | `addr[31:10]`        |
| `index`    | out | `INDEX_BITS`    | `addr[9:4]`          |
| `word_sel` | out | `WORD_SEL_BITS` | `addr[3:2]`          |
| `byte_off` | out | 2               | `addr[1:0]`          |

### `data_ram`

| Port         | Dir | Width           | Description                                   |
|--------------|-----|-----------------|-----------------------------------------------|
| `clk`        | in  | 1               | Clock                                         |
| `index`      | in  | `INDEX_BITS`    | Line select                                   |
| `word_sel`   | in  | `WORD_SEL_BITS` | Word select within line                       |
| `we_word`    | in  | 1               | Write one word (CPU write hit)                |
| `wdata_word` | in  | 32              | Word to write                                 |
| `we_line`    | in  | 1               | Write whole line (refill). Priority over word |
| `wdata_line` | in  | `BLOCK_BITS`    | Line from memory; word 0 in bits [31:0]       |
| `rdata_word` | out | 32              | Selected word (combinational)                 |
| `rdata_line` | out | `BLOCK_BITS`    | Whole line (combinational)                    |

### `tag_ram`

| Port    | Dir | Width        | Description              |
|---------|-----|--------------|--------------------------|
| `clk`   | in  | 1            | Clock                    |
| `index` | in  | `INDEX_BITS` | Line select              |
| `we`    | in  | 1            | Write tag (on refill)    |
| `wtag`  | in  | `TAG_BITS`   | Tag to store             |
| `rtag`  | out | `TAG_BITS`   | Stored tag (combinational) |

### `valid_ram`

| Port     | Dir | Width        | Description                                  |
|----------|-----|--------------|----------------------------------------------|
| `clk`    | in  | 1            | Clock                                        |
| `rst`    | in  | 1            | Sync reset: clears all valid bits            |
| `flush`  | in  | 1            | Invalidate all lines (same effect as reset)  |
| `index`  | in  | `INDEX_BITS` | Line select                                  |
| `we`     | in  | 1            | Write valid bit                              |
| `wvalid` | in  | 1            | Value to write (1 on refill)                 |
| `rvalid` | out | 1            | Valid bit of line `index` (combinational)    |

Priority in `valid_ram`: `rst` > `flush` > `we`.

## 4. How the other modules connect (for M2 / M3)

```
hit = rvalid && (rtag == tag);           // tag_comparator (M2)

Read hit    : CPU gets rdata_word in the same cycle.
Read miss   : FSM (M2) asks mem_interface (M3) for the line at
              {tag, index, {OFFSET_BITS{1'b0}}}; when the line arrives:
              we_line=1, tag_ram.we=1 (wtag=tag), valid_ram.we=1 (wvalid=1).
Write hit   : we_word=1 and write-through to memory.
Write miss  : write-through to memory only.
```

Hit/miss/refill counters live in the testbench (M4), not in these modules.
