# Member 2 Interview Preparation Guide

**Role:** Controller FSM & Tag Comparator  
**Focus Areas from Project Plan:**
- Cycle-by-cycle walk-through of a miss
- Handling of cold misses
- 22/6/4 address breakdown and scalability
- AMAT interpretation across traces

---

## Question 1: How is a 32-bit address split into tag, index, and offset, and why? What happens if block size doubles?

### Answer:
The address partitioning is mathematically derived from the cache capacity ($C = 1024\text{ B}$), block size ($B = 16\text{ B}$), and address width ($A = 32\text{ bits}$):
1. **Offset Bits ($\log_2 B$):** With $B = 16\text{ bytes}$, $\log_2(16) = 4\text{ bits}$ (`addr[3:0]`).
   - `addr[1:0]` (2 bits) select the byte within a 32-bit word (always `00` for word-aligned accesses).
   - `addr[3:2]` (2 bits) select one of the 4 words within the 16-byte block (`word_sel`).
2. **Index Bits ($\log_2 N$):** The number of lines is $N = C / B = 1024 / 16 = 64\text{ lines}$.
   - $\log_2(64) = 6\text{ bits}$ (`addr[9:4]`). This directly addresses one of the 64 entries in the direct-mapped RAMs.
3. **Tag Bits ($A - \text{Index} - \text{Offset}$):** The remaining upper bits identify which block from memory resides in that line:
   - $32 - 6 - 4 = 22\text{ bits}$ (`addr[31:10]`).

### If Block Size Doubles ($B = 32\text{ B}$, keeping $C = 1\text{ KB}$ constant):
- Offset bits increase from 4 to 5 ($\log_2 32 = 5$).
- Number of lines halves from 64 to 32 ($1024 / 32 = 32$), so index bits decrease from 6 to 5 ($\log_2 32 = 5$).
- Tag bits stay at: $32 - 5 - 5 = 22\text{ bits}$!
- **Trade-off:** Exploits greater spatial locality (each miss brings 8 words instead of 4), but increases the miss penalty (longer burst transfer from DRAM) and reduces the total number of distinct blocks that can be held simultaneously (increasing conflict misses).

---

## Question 2: What does the FSM do, cycle by cycle, on a miss?

### Answer (Cycle-by-Cycle Walk-Through):
Assume a Read Miss to address `0x0000_1004` (Tag `0x000004`, Index `0`, Word `1`) with main-memory latency of 10 cycles for the first word and 1 cycle for each subsequent word ($10 + 3 = 13\text{ cycles}$ for a 4-word refill):

- **Cycle 0 (`S_IDLE`):**
  - CPU asserts `cpu_req = 1`, `cpu_wr = 0`, `cpu_addr = 0x0000_1004`.
  - Asynchronous read from `valid_ram` produces `rvalid = 0` (or `rtag != tag`).
  - `tag_comparator` evaluates `hit = rvalid && (rtag == tag) = 0`.
  - Because `hit = 0`, fast-path ready is not asserted (`cpu_ready = 0`). The controller asserts `cpu_stall = 1`.
  - On the rising clock edge, the FSM latches `saved_addr <= cpu_addr` and advances to `S_COMPARE_TAG`.

- **Cycle 1 (`S_COMPARE_TAG`):**
  - Miss is formally registered.
  - On the rising clock edge, the FSM transitions to `S_ALLOCATE`.

- **Cycle 2 (`S_ALLOCATE`):**
  - FSM initiates main-memory access: asserts `mem_req = 1`, `mem_wr = 0`.
  - Drives block-aligned memory address: `mem_addr = {saved_tag, saved_index, 4'b0000} = 0x0000_1000`.
  - `cpu_stall` remains asserted (`cpu_ready = 0`).

- **Cycles 3 to 14 (`S_ALLOCATE` Wait Loop):**
  - The FSM holds in `S_ALLOCATE` with `mem_req = 1` while DRAM processes the access.
  - First-word latency = 10 cycles; subsequent 3 words = 3 cycles (total 13 cycles).
  - During Cycle 14, `mem_interface` asserts `mem_ready = 1` with the complete 128-bit block on `mem_rdata_line`.
  - On the rising clock edge, seeing `mem_ready = 1`, the FSM transitions to `S_UPDATE`.

- **Cycle 15 (`S_UPDATE`):**
  - FSM updates cache storage:
    - Asserts `data_we_line = 1` (writes 128-bit line to `data_ram[saved_index]`).
    - Asserts `tag_we = 1` (writes `saved_tag` to `tag_ram[saved_index]`).
    - Asserts `valid_we = 1`, `valid_wdata = 1` (sets line valid).
  - On the rising clock edge, all three RAMs update simultaneously, and the FSM transitions to `S_RESPOND`.

- **Cycle 16 (`S_RESPOND`):**
  - FSM asserts `cpu_ready = 1`, de-asserting `cpu_stall`.
  - The newly updated cache line combinationally outputs word 1 on `cpu_rdata`.
  - CPU registers data and de-asserts `cpu_req`.
  - On the next clock edge, the FSM returns to `S_IDLE`.

**Total latency:** $15\text{ cycles}$ from request to response ($14\text{ stall cycles}$ + $1\text{ hit cycle}$).

---

## Question 3: How are cold (compulsory) misses handled? Why is `valid[index]` necessary?

### Answer:
- When a system powers on or resets, the memory cells in `tag_ram` contain arbitrary random values (or zeros).
- If `valid_ram` did not exist, a CPU read to address `0x0000_0000` right after reset would read stored tag `0x000000`. The comparator would find `tag == rtag` and declare a false HIT, returning garbage data!
- To prevent this, `valid_ram` maintains a single valid bit per line, implemented as a register array that is **cleared to all zeros in a single cycle on synchronous reset or flush**:
  ```verilog
  if (rst || flush) valid_bits <= 64'd0;
  ```
- The comparator equation strictly enforces:
  $$\mathrm{hit} = \mathrm{rvalid} \;\land\; (\mathrm{rtag} == \mathrm{tag})$$
- Because `rvalid = 0` for all 64 lines after reset, the first access to any line is guaranteed to evaluate `hit = 0` (compulsory miss). The valid bit is only set to `1` in state `S_UPDATE` after main memory has successfully loaded legitimate data.

---

## Question 4: How does write handling work in Phase I? What is write-through vs. write-back?

### Answer:
1. **Write Policy in Phase I:** Write-through with No-Write-Allocate.
   - **Write Hit:** The updated word is written into the cache line (`data_we_word = 1`) and simultaneously forwarded to main memory (`mem_req = 1`, `mem_wr = 1`). `cpu_ready` completes in 1 cycle.
   - **Write Miss:** The cache line is **not** allocated (no refill). The write is dispatched straight to main memory. Cache contents and tags remain undisturbed, preventing cache pollution by write-once data.
2. **Phase II Extension (Write-Back with Write-Allocate):**
   - In write-back, writes only update the cache; memory is not updated until the line is evicted.
   - A `dirty` bit must be added to each line.
   - On a miss to a dirty line, the controller must perform a two-phase operation: write back the dirty block to memory first, then refill the new block.

---

## Question 5: How is AMAT calculated, and what does it show for each trace?

### Formula:
$$\mathrm{AMAT} = \text{Hit Time} + \text{Miss Rate} \times \text{Miss Penalty}$$
With $\text{Hit Time} = 1\text{ cycle}$ and $\text{Miss Penalty} = 14\text{ stall cycles}$:
$$\mathrm{AMAT} = 1 + (1 - \text{Hit Rate}) \times 14$$

### Results for Traces:
1. **Sequential Trace (Hit Rate = 75.0%):**
   - Accesses walk word-by-word (4 words per block). First word is a compulsory miss; next 3 words hit.
   - $\mathrm{AMAT} = 1 + (1 - 0.75) \times 14 = 1 + 3.5 = 4.5\text{ cycles}$.
2. **Repeated Loop Trace (Hit Rate = 94.1%):**
   - Working set fits within 16 blocks. Pass 1 incurs cold misses; subsequent passes hit 100%.
   - $\mathrm{AMAT} = 1 + (1 - 0.941) \times 14 = 1 + 0.82 = 1.82\text{ cycles}$ (approaches 1 cycle as loop iterations grow).
3. **Random Trace (Hit Rate = 0.0%):**
   - Addresses distributed uniformly across 4 GB address space. 64 lines cannot retain working set.
   - $\mathrm{AMAT} = 1 + 1.0 \times 14 = 15.0\text{ cycles}$.
4. **Conflict / Thrashing Trace (Hit Rate = 0.0%):**
   - Successive addresses differ by exactly $1\text{ KB}$ (e.g. `0x000`, `0x400`, `0x800`).
   - All map to index 0, continuously evicting each other. Every single access misses.
   - Demonstrates the fundamental weakness of direct mapping, motivating set associativity.
