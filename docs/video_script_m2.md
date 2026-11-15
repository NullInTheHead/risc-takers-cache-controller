# Prototype Video Script -- Member 2 (Controller FSM & Tag Comparator)

**Assigned Segment:** 1:30 -- 2:20 (50 seconds)  
**Topic:** Cache Controller Finite State Machine & Hit vs. Miss Operational Paths  
**Visual Media:** `docs/figures/fsm_diagram.png` and GTKWave simulation waveforms.

---

## Detailed Cue & Voiceover Breakdown

| Time Stamp | Visual Display | Voiceover Script |
|---|---|---|
| **1:30 -- 1:40** | Slide showing `docs/figures/fsm_diagram.png` with **IDLE** and **COMPARE_TAG** highlighted. | *"Hi everyone, I'm Member 2, responsible for the Controller FSM and the Tag Comparator. The controller coordinates all hit/miss decisions, CPU stalls, and memory refilling. In our direct-mapped design, tag matching is purely combinational: hit is asserted only when the valid bit is one and the stored tag matches the CPU address."* |
| **1:40 -- 1:55** | Zoom into the green **Fast-Path Hit loop** on IDLE, then show a waveform with single-cycle `cpu_ready`. | *"For a read hit, because our storage RAMs read asynchronously, the tag comparison and data lookup complete in the very same clock cycle. The FSM asserts `cpu_ready` immediately, completing in just one cycle without stalling the CPU. For write hits under our write-through policy, we update the cache word and dispatch the write to memory in parallel."* |
| **1:55 -- 2:10** | Highlight the miss path: **ALLOCATE** $\rightarrow$ **UPDATE** $\rightarrow$ **RESPOND**. Show simulation waveform with 14 stall cycles. | *"When a miss occurs, the FSM transitions to ALLOCATE and issues a block request to main memory. It stalls the processor until the memory interface completes the burst refill. Once the full line arrives, the FSM enters UPDATE to write the data line, store the new tag, and set the valid bit—then signals RESPOND."* |
| **2:10 -- 2:20** | Show summary bullet: Write-through + No-Write-Allocate, transition to Member 3. | *"Write misses bypass the cache entirely, writing straight to memory without polluting our cache lines. Now, Member 3 will explain how the main-memory interface and burst refill are implemented."* |

---

## Recording Tips for Member 2
- **Speaking pace:** Steady, confident, approximately 130 words in 50 seconds.
- **Screen pointer:** Use your mouse cursor or a laser pointer tool to trace the arrows on `docs/figures/fsm_diagram.png`:
  1. Point to the comparator equation $\text{hit} = \text{valid} \land (\text{rtag} == \text{tag})$.
  2. Trace the single-cycle hit return to `IDLE`.
  3. Trace the miss loop through `ALLOCATE` $\rightarrow$ `UPDATE` $\rightarrow$ `RESPOND`.
