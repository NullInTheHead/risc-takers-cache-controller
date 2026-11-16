# risc-takers-cache-controller
Team RISC Takers – Project 6: Direct-Mapped Cache Controller (Verilog)

## Architecture Overview
- **Capacity:** 1 KB
- **Block size:** 16 B (4 words $\times$ 32 bits)
- **Lines:** 64
- **Address width:** 32 bits (Tag: 22 bits, Index: 6 bits, Offset: 4 bits)
- **Write policy:** Write-through, no-write-allocate

## Team Roles & Deliverables
- **M1 – Cache Architecture & Storage:** `address_decoder.v`, `tag_ram.v`, `valid_ram.v`, `data_ram.v`
- **M2 – Controller FSM & Tag Comparator:** `tag_comparator.v`, `cache_controller_fsm.v`, `fsm_diagram`, `m2.tex`
- **M3 – Main-Memory Interface & Integration:** `main_memory.v`, `mem_interface.v`, `cache_top.v`, `m3.tex`
- **M4 – Verification & Memory-Access Traces:** `cache_tb.v`, `gen_traces.py`, `ref_model.py`, traces
- **M5 – Analysis, Synthesis & Documentation Lead:** synthesis scripts, IEEE report assembly, README

## Member 2 (Controller FSM & Tag Comparator)
### Modules Owned:
1. `rtl/tag_comparator.v`: Pure combinational tag comparison gated by line valid bit:
   $$\text{hit} = \text{rvalid} \land (\text{rtag} == \text{tag})$$
2. `rtl/cache_controller_fsm.v`: 5-state synchronous controller FSM implementing single-cycle fast hits and multi-cycle miss refills.
   - States: `IDLE`, `COMPARE_TAG`, `ALLOCATE`, `UPDATE`, `RESPOND`.

### Running Member 2 Verification:
```bash
make m2-verify
# Or run with Icarus Verilog test runner:
bash tb/run_m2_tests.sh
```

## Member 3 (Main-Memory Interface & Top-Level Integration)
### Modules Owned:
1. `rtl/main_memory.v`: Behavioural main-memory model with configurable burst latency:
   - First-word latency (`MEM_FIRST_LAT = 10` cycles) + subsequent words (`MEM_NEXT_LAT = 1` cycle/word)
   - 4-word block refill: $10 + 3 \times 1 = 13\text{ cycles}$
   - Single-word write: $10\text{ cycles}$
2. `rtl/mem_interface.v`: Memory interface bridge translating FSM memory requests into the `main_memory` req/ack handshake:
   - Eliminates phantom re-triggering via pulse request latching
   - Combines 128-bit refill bus directly into `data_ram.wdata_line`
3. `rtl/cache_top.v`: Top-level integration module encapsulating all 8 sub-modules:
   - Exposes clean CPU request/ready interface: `cpu_req`, `cpu_wr`, `cpu_addr`, `cpu_wdata` $\to$ `cpu_rdata`, `cpu_ready`
   - Verified single-cycle hit path and deterministic 19-cycle miss path

### Running Member 3 Verification:
```bash
make m3-verify
# Or run unit test suite directly:
bash tb/run_m3_tests.sh

# Run full system trace simulation:
make sim
```
