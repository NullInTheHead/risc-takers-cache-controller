#!/usr/bin/env bash
# run_m3_tests.sh -- compile and run all Member-3 unit & integration tests
# Usage (from repo root): bash tb/run_m3_tests.sh
set -e
mkdir -p tb/waves build

RTL_ALL="rtl/address_decoder.v rtl/data_ram.v rtl/tag_ram.v rtl/valid_ram.v rtl/tag_comparator.v rtl/cache_controller_fsm.v rtl/main_memory.v rtl/mem_interface.v rtl/cache_top.v"
TESTS="tb_main_memory tb_mem_interface tb_cache_top"

fail=0
for t in $TESTS; do
    echo "=== Running $t ==="
    iverilog -g2012 -Wall -o build/$t $RTL_ALL tb/$t.v
    out=$(vvp -n build/$t)
    echo "$out" | grep -v "VCD info"
    echo "$out" | grep -q "^PASS" || fail=1
    echo
done

if [ $fail -eq 0 ]; then
    echo "===================================================="
    echo "ALL M3 TESTS PASSED"
    echo "===================================================="
else
    echo "===================================================="
    echo "SOME M3 TESTS FAILED"
    echo "===================================================="
    exit 1
fi
