#!/usr/bin/env python3
"""
gen_traces.py – Trace generator for a direct-mapped cache controller.

Generates four .mem trace files suitable for $readmemh in Verilog testbenches.
Each line has the format:  RW ADDR
  - RW   : 0 = read, 1 = write
  - ADDR : 32-bit hex address (word-aligned, addr[1:0] == 00)

Trace types
-----------
  sequential.mem  – Sequential scan, ~75 % hit rate (cold misses on new blocks)
  loop.mem        – Repeated loop over 16 blocks, ~100 % hits after warm-up
  random.mem      – Random addresses, low hit rate
  conflict.mem    – Conflict/thrashing on one index, ~0 % hit rate

Cache defaults
--------------
  ADDR_WIDTH  = 32
  CACHE_SIZE  = 1024 B  (1 KB)
  BLOCK_SIZE  = 16  B   (4 words × 32 bits)
  NUM_LINES   = 64
  Write policy: write-through, no-write-allocate
"""

import argparse
import math
import os
import random

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _word_aligned(addr):
    """Return True if *addr* is word-aligned (low 2 bits zero)."""
    return (addr & 0x3) == 0


def _fmt_line(rw, addr):
    """Format one trace line: 'RW ADDR' in hex."""
    assert rw in (0, 1), f"rw must be 0 or 1, got {rw}"
    assert _word_aligned(addr), f"address 0x{addr:08X} is not word-aligned"
    return f"{rw} {addr:08X}"


def _write_trace(path, lines, label, expected_hit_rate):
    """Write *lines* to *path* and print a short summary."""
    with open(path, "w") as fh:
        for line in lines:
            fh.write(line + "\n")
    print(f"  {label:20s}  {len(lines):5d} accesses  "
          f"(expected ~{expected_hit_rate}% hit rate)  -> {path}")


# ---------------------------------------------------------------------------
# Trace generators
# ---------------------------------------------------------------------------

def gen_sequential(num_lines, block_size, words_per_block):
    """Sequential scan – walk word-by-word through consecutive blocks.

    The first word of each new block is a compulsory (cold) miss; the
    remaining (words_per_block - 1) words in the same block are hits.
    Expected hit rate ≈ (words_per_block - 1) / words_per_block = 75 %.
    """
    traces = []
    # ~200 accesses → 200 / words_per_block blocks ≈ 50 blocks
    num_blocks = 200 // words_per_block
    base_addr = 0x00000000
    for blk in range(num_blocks):
        for w in range(words_per_block):
            addr = base_addr + blk * block_size + w * 4
            traces.append(_fmt_line(0, addr))          # all reads
    return traces


def gen_loop(num_lines, block_size, words_per_block):
    """Repeated loop over a small working set that fits in cache.

    16 unique blocks are accessed; the loop repeats 5 times total (1 cold
    pass + 4 warm passes).  Some writes are mixed in (~20 % of accesses).
    Expected overall hit rate ≈ 80 %  (cold pass is all misses, warm
    passes are ~100 % hits).
    """
    random.seed(0xCAFE)                # reproducible "random" writes

    num_unique_blocks = 16
    iterations = 7                     # 1 cold + 6 warm
    # Build the working-set addresses: pick blocks at different indices so
    # they don't conflict (stride by block_size, starting at 0).
    block_addrs = [i * block_size for i in range(num_unique_blocks)]

    traces = []
    for _it in range(iterations):
        for baddr in block_addrs:
            # Access 2–4 words inside each block to vary the pattern
            num_words = random.randint(2, words_per_block)
            for w in range(num_words):
                addr = baddr + w * 4
                rw = 1 if random.random() < 0.20 else 0   # ~20 % writes
                traces.append(_fmt_line(rw, addr))
    return traces


def gen_random(addr_width):
    """Random word-aligned addresses over a large range – low hit rate."""
    random.seed(42)                    # fixed seed for reproducibility

    num_accesses = 200
    max_addr = 0x3FFFFFFF              # upper bound (inclusive)
    traces = []
    for _ in range(num_accesses):
        addr = random.randint(0, max_addr) & ~0x3   # force word-align
        rw = random.choice([0, 0, 0, 1])            # ~25 % writes
        traces.append(_fmt_line(rw, addr))
    return traces


def gen_conflict(cache_size, block_size, words_per_block):
    """Conflict / thrashing – addresses map to the same cache index.

    Addresses are spaced exactly CACHE_SIZE apart, so they all share
    index 0.  In a direct-mapped cache every new address evicts the
    previous one → ~0 % hit rate after the very first access.
    """
    num_streams = 5                    # 5 distinct addresses on same index
    accesses_per_round = num_streams   # one access from each stream
    num_rounds = 200 // accesses_per_round  # ≈ 40 rounds → 200 accesses

    base_addrs = [i * cache_size for i in range(num_streams)]

    traces = []
    for _r in range(num_rounds):
        for ba in base_addrs:
            # Pick a random word inside the block to vary things slightly
            w = random.randint(0, words_per_block - 1)
            addr = ba + w * 4
            rw = 0                     # all reads – thrashing is the point
            traces.append(_fmt_line(rw, addr))
    return traces


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Generate .mem trace files for a direct-mapped cache controller.")
    parser.add_argument("--cache-size", type=int, default=1024,
                        help="Cache size in bytes (default: 1024)")
    parser.add_argument("--block-size", type=int, default=16,
                        help="Block (cache-line) size in bytes (default: 16)")
    parser.add_argument("--addr-width", type=int, default=32,
                        help="Address width in bits (default: 32)")
    parser.add_argument("--output-dir", type=str, default="traces/",
                        help="Output directory for trace files (default: traces/)")
    args = parser.parse_args()

    cache_size      = args.cache_size
    block_size      = args.block_size
    addr_width      = args.addr_width
    output_dir      = args.output_dir

    # Derived parameters
    num_lines       = cache_size // block_size
    words_per_block = block_size // 4          # 4 bytes per word
    offset_bits     = int(math.log2(block_size))
    index_bits      = int(math.log2(num_lines))
    tag_bits        = addr_width - index_bits - offset_bits

    # Print cache geometry summary
    print("=" * 60)
    print("  Direct-Mapped Cache Trace Generator")
    print("=" * 60)
    print(f"  ADDR_WIDTH   = {addr_width}")
    print(f"  CACHE_SIZE   = {cache_size} B")
    print(f"  BLOCK_SIZE   = {block_size} B  ({words_per_block} words)")
    print(f"  NUM_LINES    = {num_lines}")
    print(f"  OFFSET_BITS  = {offset_bits}  (word-sel {int(math.log2(words_per_block))}"
          f" + byte-off 2)")
    print(f"  INDEX_BITS   = {index_bits}")
    print(f"  TAG_BITS     = {tag_bits}")
    print(f"  Address fmt  : Tag[{addr_width-1}:{index_bits+offset_bits}]"
          f" | Index[{index_bits+offset_bits-1}:{offset_bits}]"
          f" | Offset[{offset_bits-1}:0]")
    print(f"  Write policy : write-through, no-write-allocate")
    print("=" * 60)

    # Ensure output directory exists
    os.makedirs(output_dir, exist_ok=True)

    print("\nGenerating traces …\n")

    # 1. Sequential
    seq = gen_sequential(num_lines, block_size, words_per_block)
    _write_trace(os.path.join(output_dir, "sequential.mem"), seq,
                 "sequential.mem", 75)

    # 2. Loop
    loop = gen_loop(num_lines, block_size, words_per_block)
    _write_trace(os.path.join(output_dir, "loop.mem"), loop,
                 "loop.mem", 85)

    # 3. Random
    rand = gen_random(addr_width)
    _write_trace(os.path.join(output_dir, "random.mem"), rand,
                 "random.mem", "< 5")

    # 4. Conflict
    conf = gen_conflict(cache_size, block_size, words_per_block)
    _write_trace(os.path.join(output_dir, "conflict.mem"), conf,
                 "conflict.mem", "~0")

    print("\nDone. All trace files written to:", os.path.abspath(output_dir))


if __name__ == "__main__":
    main()
