# Member 3 Interview Preparation Guide

**Role:** Main-Memory Interface & Top-Level Integration  
**Focus Areas from Project Plan:**
- Origin of the miss penalty (DRAM architecture & burst transfer)
- Write-through vs. write-back trade-offs
- Write-allocate vs. no-write-allocate
- Handshake protocol and integration in `cache_top.v`
- Cycle-by-cycle breakdown of the miss penalty and AMAT impact

---

## Question 1: What is the origin of the miss penalty, and why is it 13 memory cycles in our design?

### Answer:
The miss penalty originates from the fundamental physics and architecture of Dynamic RAM (DRAM):
1. **Row Activation & CAS Latency (First Word = 10 cycles):**
   - Main memory is organised into two-dimensional arrays of rows and columns.
   - When an address misses in cache, DRAM must first close any previously open row (precharge $t_{\mathrm{RP}}$), open the requested row into the sense amplifiers ($t_{\mathrm{RCD}}$, row-to-column delay), and select the starting column (CAS latency, $t_{\mathrm{CL}}$).
   - In our parameterised model, this initial latency is captured by `MEM_FIRST_LAT = 10` clock cycles.

2. **Column Burst Streaming (Subsequent Words = 1 cycle each):**
   - Once the row buffer is active, reading consecutive words within that same row does not require another row activation. The memory controller simply increments the column counter, delivering words at the maximum bus clock rate ($t_{\mathrm{CCD}} = 1\text{ cycle}$).
   - For a 16-byte block ($4\text{ words} \times 32\text{ bits}$), the first word takes 10 cycles, and the remaining 3 words take $3 \times 1 = 3\text{ cycles}$.
   - **Total memory refill latency:**
     $$\text{Refill Latency} = \text{MEM\_FIRST\_LAT} + (\text{WORDS\_PER\_BLK} - 1) \times \text{MEM\_NEXT\_LAT} = 10 + 3 \times 1 = 13\text{ cycles}$$

3. **System Miss Penalty (Total CPU Stall = 19 cycles):**
   - From the CPU's perspective, the full miss penalty includes:
     - 1 cycle `IDLE` (detect miss)
     - 1 cycle `COMPARE_TAG` (confirm miss)
     - 1 cycle `mem_interface` request latching
     - 13 cycles main memory burst refill
     - 1 cycle `UPDATE` (synchronous write into `data_ram`, `tag_ram`, `valid_ram`)
     - 1 cycle `RESPOND` (`cpu_ready` high)
     - **Total = 19 cycles** from request assertion to data valid.

---

## Question 2: Explain the trade-offs between Write-Through and Write-Back. Why did we choose Write-Through for Phase I, and how will Phase II extend it?

### Answer:
| Feature | Write-Through (Phase I) | Write-Back (Phase II) |
|---|---|---|
| **Memory Update Timing** | Every write immediately updates cache and memory. | Memory updated only upon eviction of a dirty block. |
| **Data Consistency** | Main memory is always completely consistent with cache. | Main memory can contain stale data while cache holds newer data. |
| **Eviction Overhead** | Zero cycles. Clean lines are simply overwritten on refill. | Two-phase miss: if evicted line is dirty, it must first be written back to memory. |
| **Tracking Overhead** | No dirty bit required (only Valid and Tag). | Requires 1 dirty bit per line ($64\text{ bits}$ total). |
| **Memory Bus Traffic** | High. Every store instruction accesses the bus. | Low. Multiple writes to the same line generate only 1 writeback on eviction. |

### Why Write-Through for Phase I:
It provides the simplest, most robust baseline:
- No dirty bits required.
- Refills on read misses are strictly 1-way transfers (memory $\to$ cache) with no eviction writeback.
- Verification is deterministic and clean.

### Phase II Extension:
We will add a 64-bit `dirty_ram.v` module. When a line is modified, its dirty bit is set. On a read or write miss, if the line being replaced has `dirty == 1`, the controller must first flush that 128-bit line to main memory before refilling the new block.

---

## Question 3: What is the difference between Write-Allocate and No-Write-Allocate? What happens on a write miss in our system?

### Answer:
- **Write-Allocate (Fetch-on-Write):** On a write miss, the controller loads the block from memory into cache, updates the targeted word, and marks it. Typically paired with write-back caches.
- **No-Write-Allocate (Write-Around):** On a write miss, the word is written directly to main memory, bypassing the cache entirely. The cache line is neither allocated nor updated.

### In Our System (Write-Through + No-Write-Allocate):
1. CPU issues write to address `0x0000_0500` with data `0xCAFEBABE`.
2. Tag comparison produces `hit = 0` (write miss).
3. FSM advances to `ALLOCATE`, driving `mem_req = 1`, `mem_wr = 1`, `mem_addr = 0x0000_0500`, `mem_wdata = 0xCAFEBABE`.
4. `mem_interface` dispatches the write to `main_memory`.
5. After `MEM_FIRST_LAT` (10 cycles), memory updates `mem_array[0x140] <= 0xCAFEBABE` and signals `mem_ready`.
6. FSM transitions directly to `RESPOND` (skipping `UPDATE`).
7. **Cache arrays remain completely untouched:** the valid bit stays invalid (or preserves the old tag/data of the resident block). No cache thrashing occurs from write misses.

---

## Question 4: How does `cache_top.v` integrate the modules, and what signals are exposed to the CPU?

### Answer:
`cache_top.v` is the top-level integration wrapper. It instantiates all 8 sub-modules across Members 1, 2, and 3:
- **M1 (Storage):** `address_decoder`, `tag_ram`, `valid_ram`, `data_ram`.
- **M2 (Control):** `tag_comparator`, `cache_controller_fsm`.
- **M3 (Memory & Bridge):** `mem_interface`, `main_memory`.

### CPU Interface:
All internal buses (tag match, RAM write enables, 128-bit refill bus, FSM-memory handshakes) are encapsulated. The processor only interacts through standard bus signals:
- `clk`, `rst`: Synchronous active-high reset.
- `cpu_req`: Master request strobe.
- `cpu_wr`: `0` for read, `1` for write.
- `cpu_addr [31:0]`: Word-aligned 32-bit address.
- `cpu_wdata [31:0]`: 32-bit word to write.
- `cpu_rdata [31:0]`: 32-bit word returned to CPU.
- `cpu_ready`: Single-cycle active-high pulse indicating transaction completion.

---

## Question 5: How does the memory interface prevent spurious re-triggering?

### Answer:
During a read miss, the FSM enters `ALLOCATE` and asserts `fsm_mem_req = 1`. In the initial implementation, when main memory signaled `mm_ready`, the memory interface transitioned to `IDLE` in the same clock cycle that it asserted `fsm_mem_ready`. Because the FSM's state register only updates on the subsequent clock edge, `fsm_mem_req` remained high while the memory interface was in `IDLE`, causing a false "second request" to trigger.

We resolved this by:
1. De-asserting `mm_req <= 1'b0` immediately on the clock edge following request latching (so memory only sees a 1-cycle strobe).
2. Passing `fsm_mem_ready = mm_ready && (mi_state == MI_BUSY)` combinationally.
3. Returning to `MI_IDLE` on the rising clock edge of `mm_ready`.
This guarantees a clean, single-transaction handshake with zero phantom requests.
