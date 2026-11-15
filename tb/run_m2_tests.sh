#!/usr/bin/env bash
# run_m2_tests.sh -- compile and run all Member-2 unit tests with Icarus Verilog
# Usage (from repo root): bash tb/run_m2_tests.sh
set -e
mkdir -p tb/waves build

RTL="rtl/tag_comparator.v rtl/cache_controller_fsm.v"
TESTS="tb_tag_comparator tb_cache_controller_fsm"

fail=0
for t in $TESTS; do
    echo "=== Running $t ==="
    iverilog -g2012 -Wall -o build/$t $RTL tb/$t.v
    out=$(vvp -n build/$t)
    echo "$out" | grep -v "VCD info"
    echo "$out" | grep -q "^PASS" || fail=1
    echo
done

if [ $fail -eq 0 ]; then
    echo "===================================================="
    echo "ALL M2 TESTS PASSED"
    echo "===================================================="
else
    echo "===================================================="
    echo "SOME M2 TESTS FAILED"
    echo "===================================================="
    exit 1
fi
