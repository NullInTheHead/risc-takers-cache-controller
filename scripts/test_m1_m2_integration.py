#!/usr/bin/env python3
"""
test_m1_m2_integration.py -- Integration check of M1 storage and M2 control.
Owner: Member 2 (Controller FSM & Tag Comparator)

Simulates the end-to-end lookup and refill pipeline:
  address_decoder -> tag/valid/data RAMs -> tag_comparator -> cache_controller_fsm
"""

import sys

def run_integration():
    print("Testing M1 Storage + M2 Control pipeline...")

    # Cache geometry: 1 KB, 16 B blocks, 64 lines
    num_lines = 64
    valid_array = [0] * num_lines
    tag_array   = [0] * num_lines
    data_array  = [[0]*4 for _ in range(num_lines)] # 4 words per line

    def decode(addr):
        tag = (addr >> 10) & 0x3FFFFF
        idx = (addr >> 4) & 0x3F
        word_sel = (addr >> 2) & 0x3
        return tag, idx, word_sel

    def access(addr, rw, wdata=0, mem_block_fn=None):
        tag, idx, wsel = decode(addr)
        # Combinational tag comparison (M2 tag_comparator equation)
        rvalid = valid_array[idx]
        rtag = tag_array[idx]
        hit = 1 if (rvalid == 1 and (rtag == tag)) else 0

        if rw == 0: # READ
            if hit:
                return "HIT", data_array[idx][wsel]
            else:
                # Miss: FSM ALLOCATE -> UPDATE
                # Main memory returns line
                refill_line = mem_block_fn(addr) if mem_block_fn else [addr, addr+4, addr+8, addr+12]
                # UPDATE state: write tag, valid, data_line
                tag_array[idx] = tag
                valid_array[idx] = 1
                data_array[idx] = refill_line
                return "MISS_REFILLED", data_array[idx][wsel]
        else: # WRITE
            if hit:
                # Write hit: update cache word (data_we_word) + write through to memory
                data_array[idx][wsel] = wdata
                return "WRITE_HIT", None
            else:
                # Write miss: no allocation, write through to memory only
                return "WRITE_MISS", None

    # Scenario:
    # 1. Read 0x00000040 (Cold miss)
    res, val = access(0x00000040, 0)
    assert res == "MISS_REFILLED"
    print("  0x00000040 -> Cold Miss (Line refilled): OK")

    # 2. Read 0x00000044 (Spatial locality hit)
    res, val = access(0x00000044, 0)
    assert res == "HIT"
    print("  0x00000044 -> Spatial Locality Hit: OK")

    # 3. Write 0x00000040 with 0xCAFEBABE (Write hit)
    res, _ = access(0x00000040, 1, wdata=0xCAFEBABE)
    assert res == "WRITE_HIT"
    print("  0x00000040 -> Write Hit (Cache word updated): OK")

    # 4. Read 0x00000040 (Verify updated data on hit)
    res, val = access(0x00000040, 0)
    assert res == "HIT" and val == 0xCAFEBABE
    print("  0x00000040 -> Temporal Hit with updated data: OK")

    # 5. Read 0x00000440 (Conflict miss: same index 4, different tag)
    res, val = access(0x00000440, 0)
    assert res == "MISS_REFILLED"
    print("  0x00000440 -> Conflict Miss (Eviction & Refill): OK")

    # 6. Read 0x00000040 again (Must miss because it was evicted by step 5)
    res, val = access(0x00000040, 0)
    assert res == "MISS_REFILLED"
    print("  0x00000040 -> Re-access after eviction (Conflict Miss): OK")

    print("Pipeline integration check: ALL PASSED!\n")

if __name__ == "__main__":
    run_integration()
