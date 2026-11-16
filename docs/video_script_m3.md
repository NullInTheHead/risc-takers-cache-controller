# Prototype Video Script -- Member 3 (Main-Memory Interface & Top-Level Integration)

**Assigned Segment:** 2:20 -- 3:10 (50 seconds)  
**Topic:** Main-Memory Interface, 4-Word Burst Refill, and `cache_top` System Integration  
**Visual Media:** `docs/figures/block_diagram.png` (highlighting `main_memory`, `mem_interface`, `cache_top`), GTKWave waveform of a 13-cycle refill.

---

## Detailed Cue & Voiceover Breakdown

| Time Stamp | Visual Display | Voiceover Script |
|---|---|---|
| **2:20 -- 2:30** | Top-level block diagram highlighting `cache_top.v` and the blue blocks: `mem_interface.v` and `main_memory.v`. | *"Hello, I'm Member 3, responsible for the Main-Memory Interface and Top-Level Integration. While Member 1 built the storage and Member 2 built the FSM, my role was to connect all eight sub-modules into `cache_top.v` and manage the refill and write-through communication with main memory."* |
| **2:30 -- 2:45** | Waveform zoom-in on `tb/waves/cache_tb.vcd` showing a read miss refill across `mm_req`, `lat_cnt`, and `mm_ready`. | *"To accurately model synchronous DRAM, our behavioural memory model parameterises the latency: 10 cycles for the first word's row-buffer activation, and 1 cycle for each subsequent word in the burst. That makes exactly 13 memory cycles to refill a 16-byte block. The memory interface latches the address and delivers the 128-bit line directly into the data RAM."* |
| **2:45 -- 3:00** | Diagram illustrating write-through path and `mem_interface` handshake timing. | *"For writes, we implement write-through with no-write-allocate. On a write hit, the cache word is updated in 1 cycle while the memory interface concurrently writes through to main memory. On a write miss, the write goes directly to memory without disturbing the cache or allocating a line."* |
| **3:00 -- 3:10** | Return to full `cache_top` diagram with CPU signals: `cpu_req`, `cpu_addr`, `cpu_wdata` $\to$ `cpu_rdata`, `cpu_ready`. Transition to Member 4. | *"All internal buses are cleanly encapsulated inside `cache_top.v`, presenting an industry-standard CPU request-ready interface. Now Member 4 will walk through our verification suite and memory trace waveforms."* |

---

## Recording Tips for Member 3
- **Speaking pace:** Crisp and steady (approx. 135 words in 50 seconds).
- **Key numbers to emphasise clearly:**
  - 10 cycles first word + 3 cycles burst = **13-cycle memory refill**.
  - **16-byte block** = 4 words $\times$ 32 bits = **128-bit refill bus**.
  - **Write-through, no-write-allocate**.
- **Screen pointer:**
  1. Point to `mem_interface` and `main_memory` on the block diagram.
  2. In GTKWave, point to the 13-cycle window between `mm_req` and `mm_ready`.
