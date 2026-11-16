#!/usr/bin/env python3
"""
Reference model for a direct-mapped cache controller.

Simulates a direct-mapped, write-through, no-write-allocate cache and
predicts hit/miss for every access in a trace file.  Used to verify
RTL simulation output.

Cache defaults:
    ADDR_WIDTH  = 32
    CACHE_SIZE  = 1024 B  (1 KB)
    BLOCK_SIZE  = 16 B    (4 words x 32 bits)
    NUM_LINES   = 64
    OFFSET_BITS = 4
    INDEX_BITS  = 6
    TAG_BITS    = 22

Write policy: write-through, no-write-allocate
    - Read miss  : refill line (update valid + tag)
    - Read hit   : no state change
    - Write hit  : no state change (data forwarded to memory; line retained)
    - Write miss : no state change (write goes to memory only)

Trace format (.mem):
    Each line: ``RW ADDR``
        RW   — 0 = read, 1 = write
        ADDR — hexadecimal address (with or without ``0x`` prefix)
"""

import argparse
import math
import sys


# ---------------------------------------------------------------------------
# Cache model
# ---------------------------------------------------------------------------

class DirectMappedCache:
    """Behavioral model of a direct-mapped cache."""

    def __init__(self, cache_size: int = 1024, block_size: int = 16,
                 addr_width: int = 32):
        # Geometry
        self.cache_size = cache_size
        self.block_size = block_size
        self.addr_width = addr_width

        self.num_lines = cache_size // block_size
        self.offset_bits = int(math.log2(block_size))
        self.index_bits = int(math.log2(self.num_lines))
        self.tag_bits = addr_width - self.index_bits - self.offset_bits

        assert self.tag_bits > 0, (
            f"Tag width is non-positive ({self.tag_bits}).  "
            "Check cache-size / block-size / addr-width."
        )

        # State arrays
        self.valid = [False] * self.num_lines
        self.tags  = [0]     * self.num_lines

        # Statistics
        self.read_hits   = 0
        self.read_misses = 0
        self.write_hits  = 0
        self.write_misses = 0

    # -- helpers ------------------------------------------------------------

    def _extract(self, addr: int):
        """Return (tag, index) for *addr*."""
        index = (addr >> self.offset_bits) & ((1 << self.index_bits) - 1)
        tag   = addr >> (self.offset_bits + self.index_bits)
        return tag, index

    # -- access -------------------------------------------------------------

    def access(self, rw: int, addr: int):
        """
        Process one cache access.

        Parameters
        ----------
        rw   : 0 = read, 1 = write
        addr : full byte address

        Returns
        -------
        hit   : bool
        tag   : int
        index : int
        """
        tag, index = self._extract(addr)
        hit = self.valid[index] and (self.tags[index] == tag)

        if rw == 0:  # READ
            if hit:
                self.read_hits += 1
            else:
                self.read_misses += 1
                # Refill line on read miss
                self.valid[index] = True
                self.tags[index]  = tag
        else:        # WRITE
            if hit:
                self.write_hits += 1
                # Write-through: data goes to memory, line stays valid
            else:
                self.write_misses += 1
                # No-write-allocate: write goes to memory only, no refill

        return hit, tag, index

    # -- statistics ---------------------------------------------------------

    @property
    def total_accesses(self):
        return (self.read_hits + self.read_misses +
                self.write_hits + self.write_misses)

    @property
    def total_hits(self):
        return self.read_hits + self.write_hits

    @property
    def total_misses(self):
        return self.read_misses + self.write_misses

    def print_summary(self, file=sys.stdout):
        """Print human-readable statistics."""
        total = self.total_accesses
        total_reads = self.read_hits + self.read_misses

        print("=" * 55, file=file)
        print("  Direct-Mapped Cache — Reference Model Summary", file=file)
        print("=" * 55, file=file)
        print(f"  Cache size   : {self.cache_size} B", file=file)
        print(f"  Block size   : {self.block_size} B", file=file)
        print(f"  Num lines    : {self.num_lines}", file=file)
        print(f"  Addr width   : {self.addr_width}", file=file)
        print(f"  Tag bits     : {self.tag_bits}", file=file)
        print(f"  Index bits   : {self.index_bits}", file=file)
        print(f"  Offset bits  : {self.offset_bits}", file=file)
        print("-" * 55, file=file)
        print(f"  Total accesses : {total}", file=file)
        print(f"  Read hits      : {self.read_hits}", file=file)
        print(f"  Read misses    : {self.read_misses}", file=file)
        print(f"  Write hits     : {self.write_hits}", file=file)
        print(f"  Write misses   : {self.write_misses}", file=file)
        print("-" * 55, file=file)
        if total > 0:
            print(f"  Overall hit rate : "
                  f"{self.total_hits / total * 100:.2f}%", file=file)
        if total_reads > 0:
            print(f"  Read hit rate    : "
                  f"{self.read_hits / total_reads * 100:.2f}%", file=file)
        print("=" * 55, file=file)


# ---------------------------------------------------------------------------
# Trace reader
# ---------------------------------------------------------------------------

def read_trace(path: str):
    """
    Yield ``(rw, addr)`` tuples from a ``.mem`` trace file.

    Supports two formats:

    1. Single 33-bit hex value per line: ``{rw[32], addr[31:0]}``
       (e.g. ``000000010`` for read addr=0x10, ``100000010`` for write addr=0x10)
    2. Legacy two-column format: ``RW ADDR``

    Blank lines and lines starting with ``#`` or ``//`` are ignored.
    """
    with open(path, "r") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or line.startswith("//"):
                continue
            parts = line.split()
            if len(parts) >= 2:
                # Legacy format: RW ADDR
                rw   = int(parts[0])
                addr = int(parts[1], 16)
            else:
                # Single 33-bit hex value: {rw[32], addr[31:0]}
                val  = int(parts[0], 16)
                rw   = (val >> 32) & 1
                addr = val & 0xFFFFFFFF
            yield rw, addr


# ---------------------------------------------------------------------------
# Compare mode
# ---------------------------------------------------------------------------

def compare_results(ref_results, rtl_path: str):
    """
    Compare reference-model results against an RTL simulation log.

    The RTL log is expected to contain one character per line: ``H``
    (hit) or ``M`` (miss).

    Returns the number of mismatches.
    """
    mismatches = 0
    rtl_results = []

    with open(rtl_path, "r") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            rtl_results.append(line.upper())

    if len(rtl_results) != len(ref_results):
        print(f"[COMPARE] WARNING: RTL log has {len(rtl_results)} entries, "
              f"reference has {len(ref_results)} entries.")

    count = min(len(rtl_results), len(ref_results))
    for i in range(count):
        ref_hm = "H" if ref_results[i] else "M"
        rtl_hm = rtl_results[i]
        if ref_hm != rtl_hm:
            mismatches += 1
            print(f"  MISMATCH @ access {i}: ref={ref_hm}  rtl={rtl_hm}")

    if mismatches == 0:
        print(f"[COMPARE] PASS — all {count} accesses match.")
    else:
        print(f"[COMPARE] FAIL — {mismatches} mismatch(es) out of {count}.")

    return mismatches


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Direct-mapped cache reference model."
    )
    parser.add_argument(
        "--trace", required=True,
        help="Path to .mem trace file (required)."
    )
    parser.add_argument(
        "--cache-size", type=int, default=1024,
        help="Cache size in bytes (default: 1024)."
    )
    parser.add_argument(
        "--block-size", type=int, default=16,
        help="Block (line) size in bytes (default: 16)."
    )
    parser.add_argument(
        "--addr-width", type=int, default=32,
        help="Address width in bits (default: 32)."
    )
    parser.add_argument(
        "--output",
        help="Write per-access results to FILE."
    )
    parser.add_argument(
        "--compare",
        help="Compare reference output against RTL simulation log FILE."
    )

    args = parser.parse_args()

    # Build cache model
    cache = DirectMappedCache(
        cache_size=args.cache_size,
        block_size=args.block_size,
        addr_width=args.addr_width,
    )

    # Run trace
    results = []       # list of bools (True = hit)
    out_lines = []     # per-access text lines for --output

    for access_num, (rw, addr) in enumerate(read_trace(args.trace)):
        hit, tag, index = cache.access(rw, addr)
        results.append(hit)

        hm_str = "HIT" if hit else "MISS"
        rw_str = "R" if rw == 0 else "W"
        out_lines.append(
            f"{access_num} {rw_str} {addr:08X} {hm_str} "
            f"tag=0x{tag:X} idx={index}"
        )

    # Print summary to stdout
    cache.print_summary()

    # Optionally write per-access output
    if args.output:
        with open(args.output, "w") as fh:
            for line in out_lines:
                fh.write(line + "\n")
        print(f"\nPer-access results written to: {args.output}")

    # Optionally compare with RTL log
    if args.compare:
        print()
        mismatches = compare_results(results, args.compare)
        sys.exit(1 if mismatches else 0)


if __name__ == "__main__":
    main()
