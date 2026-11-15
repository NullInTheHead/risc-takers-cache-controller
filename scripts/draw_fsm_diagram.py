#!/usr/bin/env python3
"""
draw_fsm_diagram.py -- Renders high-resolution PNG of the Cache Controller FSM.
Owner: Member 2 (Controller FSM & Tag Comparator)
Output: docs/figures/fsm_diagram.png
"""

import matplotlib.pyplot as plt
import matplotlib.patches as patches
import os

def render_fsm():
    fig, ax = plt.subplots(figsize=(12, 6.5), dpi=300)
    ax.set_xlim(-1, 13)
    ax.set_ylim(-5, 3.5)
    ax.axis("off")

    # State definitions: (name, state_bits, actions, (x, y))
    states = {
        "IDLE": ("IDLE", "3'b000", "cpu_ready = (hit & req)", (1.5, 1.2)),
        "COMPARE_TAG": ("COMPARE_TAG", "3'b001", "eval hit/miss\nsaved_addr <= addr", (5.8, 1.2)),
        "ALLOCATE": ("ALLOCATE", "3'b010", "mem_req = 1\nwait mem_ready", (10.2, 1.2)),
        "UPDATE": ("UPDATE", "3'b011", "tag_we=1, valid_we=1\ndata_we_line=1", (10.2, -2.5)),
        "RESPOND": ("RESPOND", "3'b100", "cpu_ready = 1\ndeliver rdata_word", (4.2, -2.5)),
    }

    box_w, box_h = 2.4, 1.4

    # Draw state boxes
    for key, (name, bits, action, (x, y)) in states.items():
        box = patches.FancyBboxPatch(
            (x - box_w/2, y - box_h/2), box_w, box_h,
            boxstyle="round,pad=0.1,rounding_size=0.15",
            facecolor="#FFE6CC", edgecolor="#D79B00", linewidth=2.0
        )
        ax.add_patch(box)
        ax.text(x, y + 0.35, f"{name} [{bits}]", ha="center", va="center",
                fontsize=10.5, fontweight="bold", color="#222222")
        ax.text(x, y - 0.2, action, ha="center", va="center",
                fontsize=8.5, color="#003366", style="italic")

    # Draw arrows
    def draw_arrow(x1, y1, x2, y2, label="", rad=0.0, dashed=False, label_offset=(0, 0.2), ha="center"):
        style = "Simple,tail_width=0.8,head_width=5,head_length=6"
        ls = "dashed" if dashed else "solid"
        color = "#B85450" if dashed else "#333333"
        arrow = patches.FancyArrowPatch(
            (x1, y1), (x2, y2),
            connectionstyle=f"arc3,rad={rad}",
            arrowstyle="-|>",
            mutation_scale=14,
            linewidth=1.8,
            linestyle=ls,
            color=color
        )
        ax.add_patch(arrow)
        if label:
            mx = (x1 + x2)/2 + label_offset[0]
            my = (y1 + y2)/2 + label_offset[1]
            ax.text(mx, my, label, ha=ha, va="center",
                    fontsize=8.0, fontweight="semibold",
                    bbox=dict(boxstyle="round,pad=0.2", facecolor="white", edgecolor="none", alpha=0.9))

    # Reset arrow
    draw_arrow(-0.5, 1.2, 0.3, 1.2, label="rst = 1", label_offset=(-0.1, 0.25))

    # IDLE self loop (!cpu_req)
    draw_arrow(1.1, 1.9, 1.9, 1.9, label="!cpu_req", rad=-0.7, label_offset=(0, 0.45))

    # Fast-path hit (cpu_req & hit)
    draw_arrow(1.9, 0.5, 1.1, 0.5, label="cpu_req & hit\n(1-cycle fast hit)", rad=-0.7, dashed=True, label_offset=(0, -0.45))

    # IDLE -> COMPARE_TAG (cpu_req & !hit)
    draw_arrow(2.7, 1.2, 4.6, 1.2, label="cpu_req & !hit", label_offset=(0, 0.25))

    # COMPARE_TAG -> ALLOCATE (!hit)
    draw_arrow(7.0, 1.2, 9.0, 1.2, label="miss (!hit)", label_offset=(0, 0.25))

    # COMPARE_TAG -> RESPOND (hit)
    draw_arrow(5.5, 0.5, 4.5, -1.8, label="hit (multi-cycle)", label_offset=(-0.6, 0.1), ha="right")

    # ALLOCATE self loop (!mem_ready)
    draw_arrow(9.8, 1.9, 10.6, 1.9, label="!mem_ready (wait latency)", rad=-0.7, label_offset=(0, 0.45))

    # ALLOCATE -> UPDATE (mem_ready & !cpu_wr)
    draw_arrow(10.2, 0.5, 10.2, -1.8, label="mem_ready & !cpu_wr\n(Read Refill)", label_offset=(0.85, 0.0), ha="left")

    # ALLOCATE -> RESPOND (Write miss, no-allocate)
    draw_arrow(9.2, -2.5, 5.4, -2.5, label="mem_ready & cpu_wr (Write Miss)", dashed=True, label_offset=(0, 0.25))

    # UPDATE -> RESPOND (1 cycle write)
    draw_arrow(9.0, -2.8, 5.4, -2.8, label="RAM write complete (1 cycle)", label_offset=(0, -0.3))

    # RESPOND -> IDLE
    draw_arrow(3.0, -2.2, 1.2, 0.5, label="done -> IDLE", label_offset=(-0.5, -0.1), ha="right")

    # Title & Legend
    ax.text(6.0, 3.0, "Direct-Mapped Cache Controller Finite State Machine (M2)",
            ha="center", va="center", fontsize=13, fontweight="bold", color="#111111")
    ax.text(6.0, 2.6, "Write-Through, No-Write-Allocate Policy with Single-Cycle Fast-Path Hit",
            ha="center", va="center", fontsize=9.5, color="#555555", style="italic")

    # Legend
    leg_y = -4.3
    ax.plot([1.0, 2.2], [leg_y, leg_y], color="#333333", linewidth=1.8)
    ax.text(2.4, leg_y, "Normal State Transition", va="center", fontsize=8.5)

    ax.plot([5.5, 6.7], [leg_y, leg_y], color="#B85450", linewidth=1.8, linestyle="dashed")
    ax.text(6.9, leg_y, "Bypass / Write-Miss Path", va="center", fontsize=8.5)

    p = patches.FancyBboxPatch((9.8, leg_y - 0.2), 0.4, 0.4, boxstyle="round,pad=0.05",
                               facecolor="#FFE6CC", edgecolor="#D79B00", linewidth=1.5)
    ax.add_patch(p)
    ax.text(10.4, leg_y, "Member 2 FSM State", va="center", fontsize=8.5)

    os.makedirs("docs/figures", exist_ok=True)
    out_path = "docs/figures/fsm_diagram.png"
    plt.tight_layout()
    plt.savefig(out_path, dpi=300, bbox_inches="tight")
    plt.close()
    print(f"Rendered FSM diagram to {out_path}")

if __name__ == "__main__":
    render_fsm()
