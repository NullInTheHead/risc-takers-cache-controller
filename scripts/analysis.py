#!/usr/bin/env python3
"""
analysis.py -- AMAT Performance Analysis Suite
Reads reference model logs, computes AMAT for each benchmark trace,
and formats human-readable summary tables and evaluation reports.

Usage:
    python3 scripts/analysis.py
"""

import os, re, sys

# -----------------------------------------------------------------------
# Cache and memory parameters (match the design)
# -----------------------------------------------------------------------
T_HIT         = 1          # single-cycle combinational hit
MEM_FIRST_LAT = 10         # cycles for first word
MEM_NEXT_LAT  = 1          # cycles per subsequent burst word
WORDS_PER_BLK = 4
# Miss penalty breakdown:
#   IDLE→COMPARE_TAG (1) + ALLOCATE entry (1) + memory burst (13) + UPDATE (1) + RESPOND (1) = 17
# However the FSM overlaps: COMPARE_TAG and first ALLOCATE overlap with mem latency start,
# so the total stall cycles are:  COMPARE_TAG(1) + ALLOCATE-mem-wait(13) + UPDATE(1) + RESPOND(1) = 16
# Total cycles for a read miss = 1 (IDLE, miss detected) + 16 stall = 17 cycles
# Miss penalty as seen by CPU = cycles - T_HIT = 16
MISS_PENALTY  = 1 + 13 + 1 + 1   # COMPARE_TAG + burst + UPDATE + RESPOND  = 16 stall cycles

TRACES = ["sequential", "loop", "random", "conflict"]
RESULTS_DIR = "results"

TRACE_PATTERN_DESC = {
    "sequential": "Linear word scan (spatial locality)",
    "loop"      : "Repeated small loop (temporal locality)",
    "random"    : "Uniform random 32-bit address range",
    "conflict"  : "Stride = cache size (ping-pong thrashing)",
}

DOMINANT_MISS = {
    "sequential": "Compulsory",
    "loop"      : "Compulsory (1st pass only)",
    "random"    : "Capacity",
    "conflict"  : "Conflict",
}

def parse_log(path):
    """Parse either the per-line log OR the summary file."""
    data = {}
    with open(path) as f:
        txt = f.read()
    patterns = {
        "total" : r"Total accesses\s*:\s*(\d+)",
        "rhits" : r"Read hits\s*:\s*(\d+)",
        "rmiss" : r"Read misses\s*:\s*(\d+)",
        "whits" : r"Write hits\s*:\s*(\d+)",
        "wmiss" : r"Write misses\s*:\s*(\d+)",
        "hitrate": r"Overall hit rate\s*:\s*([\d.]+)",
    }
    for key, pat in patterns.items():
        m = re.search(pat, txt)
        data[key] = float(m.group(1)) if m else 0.0
    # If the per-line log was stored (no summary block), count manually
    if data["total"] == 0:
        lines_data = txt.strip().splitlines()
        rh = rm = wh = wm = 0
        for line in lines_data:
            parts = line.split()
            if len(parts) < 4:
                continue
            rw = parts[1]
            outcome = parts[3]
            if rw == 'R':
                if outcome == 'HIT': rh += 1
                else:                rm += 1
            elif rw == 'W':
                if outcome == 'HIT': wh += 1
                else:                wm += 1
        total = rh + rm + wh + wm
        data = {
            "total"  : float(total),
            "rhits"  : float(rh),
            "rmiss"  : float(rm),
            "whits"  : float(wh),
            "wmiss"  : float(wm),
            "hitrate": (rh + wh) / total * 100.0 if total else 0.0,
        }
    return data

def amat(hit_rate):
    miss_rate = 1.0 - hit_rate / 100.0
    return T_HIT + miss_rate * MISS_PENALTY

def main():
    os.makedirs(RESULTS_DIR, exist_ok=True)
    rows = []

    print("=" * 72)
    print("  DIRECT-MAPPED CACHE CONTROLLER -- AMAT ANALYSIS REPORT")
    print("  Parameters: T_hit=1 cycle | Miss penalty=%d cycles" % MISS_PENALTY)
    print("  Formula:    AMAT = T_hit + Miss_Rate × Miss_Penalty")
    print("=" * 72)

    for t in TRACES:
        log_path = os.path.join(RESULTS_DIR, f"ref_{t}.log")
        if not os.path.exists(log_path):
            print(f"[WARN] Missing {log_path} — skipping.")
            continue
        d = parse_log(log_path)
        hr = d["hitrate"]
        mr = 100.0 - hr
        am = amat(hr)
        total = int(d["total"])
        hits  = int(d["rhits"]) + int(d["whits"])
        misses= int(d["rmiss"]) + int(d["wmiss"])

        print(f"\n  Trace: {t.upper():<12} ({TRACE_PATTERN_DESC[t]})")
        print(f"    Total accesses : {total}")
        print(f"    Hits           : {hits}  |  Misses: {misses}")
        print(f"    Hit rate       : {hr:.2f}%  |  Miss rate: {mr:.2f}%")
        print(f"    AMAT           : {T_HIT} + {mr/100:.4f} × {MISS_PENALTY} = {am:.4f} cycles")
        rows.append((t, total, hits, misses, hr, mr, am, DOMINANT_MISS[t]))

    print("\n" + "=" * 72)

    # --- Write Human-Readable Plain Text Summary Table ----------------
    txt_lines = []
    txt_lines.append("=" * 96)
    txt_lines.append("                  DIRECT-MAPPED CACHE CONTROLLER -- AMAT PERFORMANCE SUMMARY")
    txt_lines.append("=" * 96)
    txt_lines.append("Architecture : 1 KB Capacity | 16-byte Block | 64 Lines | Write-Through, No-Write-Allocate")
    txt_lines.append(f"Timing       : Hit Latency = {T_HIT} cycle | Miss Penalty = {MISS_PENALTY} stall cycles")
    txt_lines.append(f"Formula      : AMAT = Hit_Latency + (Miss_Rate * Miss_Penalty)")
    txt_lines.append("-" * 96)
    txt_lines.append(f"{'Trace':<12} {'Accesses':>10} {'Hits':>8} {'Misses':>8} {'Hit Rate':>11} {'Miss Rate':>11} {'AMAT (cycles)':>15}  {'Dominant Miss':<16}")
    txt_lines.append("-" * 96)
    total_acc = sum(r[1] for r in rows)
    total_hits = sum(r[2] for r in rows)
    total_misses = sum(r[3] for r in rows)
    for (t, total, hits, misses, hr, mr, am, dom) in rows:
        txt_lines.append(
            f"{t.capitalize():<12} {total:>10} {hits:>8} {misses:>8} {hr:>10.2f}% {mr:>10.2f}% {am:>15.4f}  {dom:<16}"
        )
    txt_lines.append("-" * 96)
    overall_hr = (total_hits / total_acc * 100.0) if total_acc else 0.0
    overall_mr = 100.0 - overall_hr
    txt_lines.append(
        f"{'Total / Avg':<12} {total_acc:>10} {total_hits:>8} {total_misses:>8} {overall_hr:>10.2f}% {overall_mr:>10.2f}% {'--':>15}  {'All Traces Pass':<16}"
    )
    txt_lines.append("=" * 96)

    out_path = os.path.join(RESULTS_DIR, "amat_summary.txt")
    with open(out_path, "w") as f:
        f.write("\n".join(txt_lines) + "\n")
    print(f"\n  Human-readable summary table saved to: {out_path}")
    print("=" * 72)

if __name__ == "__main__":
    main()
