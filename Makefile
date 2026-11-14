# Makefile -- build and test targets for cache-controller
# Targets relevant to M4 (Verification & Memory-Access Traces)

PYTHON  ?= python3
IVERILOG ?= iverilog
VVP      ?= vvp

TRACES  = traces/sequential.mem traces/loop.mem traces/random.mem traces/conflict.mem
RTL     = rtl/address_decoder.v rtl/data_ram.v rtl/tag_ram.v rtl/valid_ram.v

.PHONY: traces ref-model sim clean

# Generate all trace files
traces: $(TRACES)

$(TRACES): scripts/gen_traces.py
	$(PYTHON) scripts/gen_traces.py --output-dir traces/

# Run reference model on all traces
ref-model: traces
	@for t in sequential loop random conflict; do \
		echo "=== ref_model: $$t ==="; \
		$(PYTHON) scripts/ref_model.py --trace traces/$$t.mem --output results/ref_$$t.log; \
	done

# Simulate (uncomment when M2/M3 RTL is ready)
# sim: traces
#	mkdir -p tb/waves results
#	$(IVERILOG) -g2012 -o tb/waves/cache_sim $(RTL) rtl/tag_comparator.v \
#		rtl/cache_controller_fsm.v rtl/main_memory.v rtl/mem_interface.v \
#		rtl/cache_top.v tb/cache_tb.v
#	$(VVP) tb/waves/cache_sim

clean:
	rm -f traces/*.mem results/*.log tb/waves/*.vcd tb/waves/cache_sim
