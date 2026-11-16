# Makefile -- build and test targets for cache-controller
# Targets relevant to M4 (Verification & Memory-Access Traces)

PYTHON  ?= python3
IVERILOG ?= iverilog
VVP      ?= vvp

TRACES  = traces/sequential.mem traces/loop.mem traces/random.mem traces/conflict.mem
RTL     = rtl/address_decoder.v rtl/data_ram.v rtl/tag_ram.v rtl/valid_ram.v \
          rtl/tag_comparator.v rtl/cache_controller_fsm.v \
          rtl/main_memory.v rtl/mem_interface.v rtl/cache_top.v

.PHONY: traces ref-model sim m2-verify m3-verify clean

# Generate all trace files
traces: $(TRACES)

$(TRACES): scripts/gen_traces.py
	$(PYTHON) scripts/gen_traces.py --output-dir traces/

# Run reference model on all traces
ref-model: traces
	@mkdir -p results
	@for t in sequential loop random conflict; do \
		echo "=== ref_model: $$t ==="; \
		$(PYTHON) scripts/ref_model.py --trace traces/$$t.mem --output results/ref_$$t.log; \
	done

# Member 2 standalone verification suite
m2-verify:
	$(PYTHON) scripts/verify_m2.py
	$(PYTHON) scripts/test_m1_m2_integration.py
	$(PYTHON) scripts/verify_all_traces.py

# Member 3 standalone verification suite
m3-verify:
	bash tb/run_m3_tests.sh

# Simulate full system (M3 integrated) — override TRACE_FILE on command line
sim: traces
	mkdir -p tb/waves results
	$(IVERILOG) -g2012 -o tb/waves/cache_sim $(RTL) tb/cache_tb.v
	$(VVP) tb/waves/cache_sim

clean:
	rm -f traces/*.mem results/*.log tb/waves/*.vcd tb/waves/cache_sim
