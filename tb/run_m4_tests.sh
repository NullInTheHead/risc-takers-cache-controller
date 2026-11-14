#!/bin/bash
# run_m4_tests.sh -- Run all M4 verification tasks
# Owner: Member 4 (Verification & Memory-Access Traces)
#
# Usage: bash tb/run_m4_tests.sh [TRACE]
#   TRACE = sequential | loop | random | conflict | all (default: all)

set -e
cd "$(dirname "$0")/.."

TRACE=${1:-all}
PROJ_ROOT=$(pwd)

# Create output directories
mkdir -p traces results tb/waves

# Step 1: Generate traces
echo "=== Generating traces ==="
python3 scripts/gen_traces.py --output-dir traces/
echo ""

# Step 2: Run reference model for each trace
run_one() {
    local name=$1
    echo "=== Running reference model on ${name}.mem ==="
    python3 scripts/ref_model.py --trace traces/${name}.mem \
        --output results/ref_${name}.log
    echo ""

    # Step 3: Compile and simulate (requires cache_top.v from M3)
    # Uncomment once M2 and M3 deliver their modules:
    # echo "=== Compiling RTL + testbench for ${name} ==="
    # iverilog -g2012 -o tb/waves/cache_tb_${name} \
    #     -DTRACE_FILE=\"traces/${name}.mem\" \
    #     rtl/address_decoder.v rtl/data_ram.v rtl/tag_ram.v rtl/valid_ram.v \
    #     rtl/tag_comparator.v rtl/cache_controller_fsm.v \
    #     rtl/main_memory.v rtl/mem_interface.v rtl/cache_top.v \
    #     tb/cache_tb.v
    # echo "=== Simulating ${name} ==="
    # vvp tb/waves/cache_tb_${name}
    # echo ""
    #
    # echo "=== Comparing RTL vs reference model for ${name} ==="
    # python3 scripts/ref_model.py --trace traces/${name}.mem \
    #     --compare results/rtl_results.log
    # echo ""
}

if [ "$TRACE" = "all" ]; then
    for t in sequential loop random conflict; do
        run_one $t
    done
else
    run_one $TRACE
fi

echo "=== All M4 tasks complete ==="
echo "Traces:     traces/"
echo "Ref logs:   results/ref_*.log"
echo "Waveforms:  tb/waves/ (once RTL is ready)"
