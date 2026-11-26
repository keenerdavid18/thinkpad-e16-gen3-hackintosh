#!/usr/bin/env python3
"""irqregs.py awake.txt halt.txt: GPU/display interrupt registers from two disp2txt.py dumps (S0ixStandby 99b5692+).

Per block: ISR (live status), IMR (mask, 1 = masked), IIR (latched, cleared by the ISR), IER (enable), and
armed = IER & ~IMR (sources that can raise the IGPU interrupt). S0ixStandby #7: the IGPU vector fires ~23/s during
the E16 halt; a source armed at the halt with its ISR bit set or toggling is the suspect.
"""
import sys

BLOCKS = [("pipe A", 0x44400), ("pipe B", 0x44410), ("pipe C", 0x44420), ("pipe D", 0x44430),
          ("DE port", 0x44440), ("DE misc", 0x44460), ("DE HPD (TC/TBT)", 0x44470), ("GU misc", 0x444F0),
          ("PCH SDE", 0xC4000)]
SINGLE = [(0x44030, "TBT_HOTPLUG_CTL"), (0x44038, "TC_HOTPLUG_CTL"), (0x44200, "DISPLAY_INT_CTL"),
          (0xC4030, "SHOTPLUG_CTL_DDI"), (0xC4034, "SHOTPLUG_CTL_TC"), (0xC4038, "SHPD_FILTER_CNT"),
          (0x190010, "GFX_MSTR_IRQ"), (0x190018, "GT_INTR_DW0"), (0x19001C, "GT_INTR_DW1"),
          (0x190030, "RENDER_COPY_INTR_ENABLE"), (0x190034, "VCS_VECS_INTR_ENABLE"),
          (0x190038, "GUC_SG_INTR_ENABLE"), (0x19003C, "GPM_WGBOXPERF_INTR_ENABLE"),
          (0x1900A8, "RCS0_RSVD_INTR_MASK"), (0x1900AC, "BCS_RSVD_INTR_MASK"),
          (0x1900C4, "GUC_SG_INTR_MASK"), (0x1900C8, "GPM_WGBOXPERF_INTR_MASK")]


def load(path):
    d = {}
    for line in open(path):
        p = line.split()
        if len(p) == 2 and p[0].startswith("0x"):
            d[int(p[0], 16)] = int(p[1], 16)
    return d


aw, ha = load(sys.argv[1]), load(sys.argv[2])
if 0x44200 not in ha:
    sys.exit("  (dump has no interrupt registers: S0ixStandby older than 99b5692)")
g = lambda d, o: d.get(o, 0)
print(f"  {'block':16} {'':6} {'ISR':>10} {'IMR':>10} {'IIR':>10} {'IER':>10} {'armed':>10} {'armed&ISR':>10}")
for name, base in BLOCKS:
    for tag, d in (("awake", aw), ("halt", ha)):
        isr, imr, iir, ier = (g(d, base + 4 * i) for i in range(4))
        armed = ier & ~imr & 0xFFFFFFFF
        flag = "  <==" if tag == "halt" and (armed & (isr | iir)) else ""
        print(f"  {name:16} {tag:6} {isr:#010x} {imr:#010x} {iir:#010x} {ier:#010x} {armed:#010x} {armed & isr:#010x}{flag}")
print()
for o, name in SINGLE:
    a, h = g(aw, o), g(ha, o)
    print(f"  {name:26} {o:#08x}  awake {a:#010x}  halt {h:#010x}{'  (changed)' if a != h else ''}")
