# Direct-Mapped Cache Controller in Verilog

**Team RISC Takers — Project 6 (Phase I)**  
An IEEE 1364-compliant, fully parameterised direct-mapped cache controller in synthesizable Verilog for 32-bit microprocessor architectures.

---

## 1. Architectural Specifications

| Parameter | Value | Description |
| :--- | :---: | :--- |
| **Cache Capacity** | **1 KB** (1024 Bytes) | Total data array storage |
| **Block / Line Size** | **16 Bytes** | 4 words $\times$ 32 bits per block |
| **Number of Lines** | **64 lines** | $1024\text{ B} / 16\text{ B} = 64$ lines |
| **Address Width** | **32 bits** | Standard byte-addressable space |
| **Offset Field** | **4 bits** `[3:0]` | Bits `[3:2]` select word (0–3); `[1:0]` byte offset |
| **Index Field** | **6 bits** `[9:4]` | Indexes one of 64 cache lines ($\log_2 64 = 6$) |
| **Tag Field** | **22 bits** `[31:10]` | Uniquely identifies memory block ($32 - 6 - 4 = 22$) |
| **Write Policy** | **Write-Through** | Write hit updates cache word and backing memory simultaneously |
| **Allocation Policy**| **No-Write-Allocate** | Write miss writes directly to memory; cache unchanged |
| **Hit Latency** | **1 clock cycle** | Asynchronous combinational read enables fast-path hits |
| **Miss Penalty** | **16 stall cycles** | 13-cycle DRAM burst refill + FSM allocate, update, respond |

### Address Field Layout
```text
 31                                 10 9            4 3      2 1     0
+-------------------------------------+--------------+--------+-------+
|              TAG (22)               |  INDEX (6)   | WORD(2)| BYTE(2)
+-------------------------------------+--------------+--------+-------+
```

---

## 2. Team Members & Roles

| Member | Role | Key Deliverables |
| :--- | :--- | :--- |
| **Niharika Chaudhary** | Cache Architecture & Storage | `address_decoder.v`, `data_ram.v`, `tag_ram.v`, `valid_ram.v`, `interfaces.md`, block diagram |
| **Karan Chillar** | Controller FSM & Tag Comparator | `tag_comparator.v`, `cache_controller_fsm.v`, `fsm_diagram`, Python verification suite |
| **Harshita Joshi** | Memory Interface & Integration | `main_memory.v`, `mem_interface.v`, `cache_top.v`, memory testbenches |
| **Shreshtha Gupta** | Verification & Traces | `gen_traces.py`, `ref_model.py`, benchmark traces (`*.mem`), `cache_tb.v` |
| **Soumya Tiwari** | Analysis, Synthesis & Documentation Lead | `analysis.py`, AMAT evaluation, IEEE conference report (`report.tex`, `report.pdf`), README |

---

## 3. Repository Structure

```text
risc-takers-cache-controller/
├── rtl/                        # Synthesizable RTL and memory models
│   ├── address_decoder.v       # Address bit splitter (Tag / Index / Word / Byte)
│   ├── all_in_one_design.v     # Bundled single-file RTL for online EDA simulation
│   ├── cache_controller_fsm.v  # 5-state synchronous controller FSM
│   ├── cache_top.v             # Full top-level integration wrapper
│   ├── data_ram.v              # 64 x 128-bit data array (read-modify-write)
│   ├── main_memory.v           # Configurable DRAM burst behavioural model
│   ├── mem_interface.v         # Request/acknowledge memory bridge
│   ├── tag_comparator.v        # Combinational tag equality comparator
│   ├── tag_ram.v               # 64 x 22-bit tag storage array
│   └── valid_ram.v             # 64-bit valid vector with single-cycle reset
├── tb/                         # Self-checking unit and system testbenches
│   ├── cache_tb.v              # System-level trace-driven testbench
│   ├── tb_cache_top.v          # Integration testbench
│   ├── tb_cache_controller_fsm.v
│   ├── tb_tag_comparator.v
│   ├── tb_data_ram.v
│   ├── tb_tag_ram.v
│   ├── tb_valid_ram.v
│   ├── tb_address_decoder.v
│   ├── tb_mem_interface.v
│   └── tb_main_memory.v
├── traces/                     # Memory-access benchmark trace files
│   ├── sequential.mem          # Spatial locality benchmark (200 accesses)
│   ├── loop.mem                # Temporal locality benchmark (324 accesses)
│   ├── random.mem              # Capacity stress benchmark (200 accesses)
│   └── conflict.mem            # Direct-mapped conflict thrashing (200 accesses)
├── scripts/                    # Verification and performance evaluation tools
│   ├── gen_traces.py           # Benchmark trace generator
│   ├── ref_model.py            # Software reference (golden) cache simulator
│   ├── analysis.py             # AMAT calculator and LaTeX table exporter
│   ├── verify_m2.py            # 97-point FSM functional assertion suite
│   ├── test_m1_m2_integration.py # Storage + control pipeline check
│   └── verify_all_traces.py    # 924-access bit-accurate regression runner
├── results/                    # Benchmark run outputs and AMAT tables
│   ├── ref_*.log               # Per-access hit/miss reference logs
│   ├── ref_*_summary.txt       # Benchmark summary statistics
│   └── amat_summary.txt        # Performance evaluation and AMAT summary table
├── synth/                      # Synthesis scripts
│   └── m1_storage_check.ys     # Yosys gate-level sanity check
├── docs/                       # Project documentation and manuscripts
│   ├── waveform_viewer.html    # Interactive cycle-accurate waveform analyzer
│   ├── report.pdf              # Compiled 6-page IEEE conference report
│   ├── report.tex              # Master LaTeX IEEEtran source
│   ├── interfaces.md           # Frozen inter-module signal specification
│   ├── figures/                # Vector block diagram and high-res FSM diagram
│   └── sections/               # Modular LaTeX section drafts
├── Makefile                    # Unified build and test automation
└── README.md                   # Project overview and execution guide
```

---

## 4. How to Run

### Prerequisites
* Python 3.8+ (no external dependencies required)
* Icarus Verilog (`iverilog`, `vvp`) and GTKWave *(optional, for Verilog simulation)*

### Step 1: Generate Benchmark Traces
Generates all four access traces in `traces/`:
```bash
make traces
# or: python3 scripts/gen_traces.py --output-dir traces/
```

### Step 2: Run Software Reference Model
Simulates the golden cache model and outputs logs to `results/`:
```bash
make ref-model
```

### Step 3: Run Full Functional Verification Suite
Runs the 97-point assertion suite, pipeline integration checks, and 924-access bit-accurate regression:
```bash
make m2-verify
```

### Step 4: Run AMAT Performance Analysis
Parses benchmark logs and calculates exact AMAT for each access pattern:
```bash
python3 scripts/analysis.py
```

### Step 5: Run Verilog RTL Testbenches (with Icarus Verilog)
```bash
# Unit test suites:
bash tb/run_m1_tests.sh
bash tb/run_m2_tests.sh
bash tb/run_m3_tests.sh

# Run system-level trace simulation:
make sim
```

---

## 5. Verification & AMAT Evaluation Results

All 924 benchmark memory accesses achieve a **100% bit-accurate match** between the RTL behavioural model and the Python reference model.

$$\text{AMAT} = t_{\text{hit}} + \text{Miss Rate} \times t_{\text{penalty}} = 1 + \text{Miss Rate} \times 16$$

| Benchmark Trace | Accesses | Hits | Misses | Hit Rate | Miss Rate | AMAT (cycles) | Dominant Behavior |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :--- |
| **Sequential** | 200 | 150 | 50 | **75.00%** | 25.00% | **5.00** | 1 compulsory miss + 3 spatial-locality hits per block |
| **Repeated Loop**| 324 | 305 | 19 | **94.14%** | 5.86% | **1.94** | 1st iteration cold misses; 100% temporal hits thereafter |
| **Random** | 200 | 0 | 200 | **0.00%** | 100.00% | **17.00** | Working set far exceeds 1 KB; capacity misses |
| **Conflict** | 200 | 0 | 200 | **0.00%** | 100.00% | **17.00** | Stride = 1 KB (ping-pong index collision thrashing) |
| **Total / Avg** | **924** | **455** | **469** | **49.24%** | **50.76%** | — | **All 924 accesses verified 100% bit-accurate** |

---

## 6. Project Documentation & Deliverables

* **Prototype Video Demonstration:** [Watch Video Demo (Google Drive)](https://drive.google.com/file/d/1ceX4_QyjNYQM-hh1mGNlkBPhGlVPJafL/view?usp=sharing)
* **Interactive Waveform Analyzer:** Open [`docs/waveform_viewer.html`](docs/waveform_viewer.html) in any browser to inspect cycle-accurate signal waveforms across all 5 operational scenarios (Read Hit, Read Miss Burst, Write Hit, Write Miss, and Conflict Thrashing).
* **IEEE Conference Report:** Full 6-page manuscript formatted with `IEEEtran` available at [`docs/report.pdf`](docs/report.pdf) (LaTeX source: [`docs/report.tex`](docs/report.tex)).
* **System Architecture Diagram:** [`docs/figures/block_diagram.pdf`](docs/figures/block_diagram.pdf).
* **FSM State Diagram:** [`docs/figures/fsm_diagram.png`](docs/figures/fsm_diagram.png).
* **Signal Interface Specification:** [`docs/interfaces.md`](docs/interfaces.md).
