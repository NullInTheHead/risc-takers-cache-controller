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
- **M3 – Main-Memory Interface & Integration:** `main_memory.v`, `mem_interface.v`, `cache_top.v`
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
