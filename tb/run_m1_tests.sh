#!/usr/bin/env bash
# run_m1_tests.sh -- compile and run all Member-1 unit tests with Icarus Verilog
# Usage (from the repo root):  bash tb/run_m1_tests.sh
set -e
mkdir -p tb/waves build

RTL="rtl/address_decoder.v rtl/data_ram.v rtl/tag_ram.v rtl/valid_ram.v"
TESTS="tb_address_decoder tb_data_ram tb_tag_ram tb_valid_ram tb_storage_lookup"

fail=0
for t in $TESTS; do
    iverilog -g2005 -Wall -o build/$t $RTL tb/$t.v
    out=$(vvp -n build/$t)
    echo "$out" | grep -v "VCD info"
    echo "$out" | grep -q "^PASS" || fail=1
    echo
done

if [ $fail -eq 0 ]; then echo "ALL M1 TESTS PASSED"; else echo "SOME TESTS FAILED"; exit 1; fi
