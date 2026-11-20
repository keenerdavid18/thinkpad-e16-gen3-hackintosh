#!/usr/bin/env python3
"""Compare the PCH PMC state awake vs at the Deep Idle halt (why the package stays at PC2 in sleep).

Sources (all the same 4 KB page = PMC offsets 0x1000-0x1FFF, the LPIT counter's page 0xFE001000):
  awake      file from `sysctl -b debug.s0ix.pmc` (S0ixStandby fb95f26a+), e.g. saved by sleep-power.sh
  halt       ioreg "PMC page at halt"    (S0ixStandby with -s0ixpmcdump, last Deep Idle, read at the quiesce action)
  afterhalt  ioreg "PMC page after halt" (same, read at the active action right after the halt)
Prints per-IP LTR (Linux pmc_core ltr_show names/decoding), PFEAR power gating and the live LPM requirement status
side by side; '*' marks rows that differ.
  python3 pmc-compare.py <awake-file> [more files...]    # plus the ioreg halt pages when present
"""
import json
import os
import plistlib
import struct
import subprocess
import sys

here = os.path.dirname(os.path.abspath(__file__))
names = json.load(open(os.path.join(here, "linux_names.json")))
BASE = 0x1000

pages = {}
for fn in sys.argv[1:]:
    b = open(fn, "rb").read()
    if len(b) == 4096:
        pages[os.path.basename(fn)] = b
raw = subprocess.run(["ioreg", "-a", "-r", "-c", "S0ixStandby", "-d1", "-w0"], capture_output=True).stdout
svc = plistlib.loads(raw)[0] if raw.strip() else {}
for key, label in (("PMC page at halt", "halt"), ("PMC page after halt", "afterhalt")):
    if isinstance(svc.get(key), bytes) and len(svc[key]) == 4096:
        pages[label] = svc[key]
if not pages:
    raise SystemExit("no PMC pages (need a debug.s0ix.pmc file and/or -s0ixpmcdump)")
cols = list(pages)
r32 = lambda p, off: struct.unpack_from("<I", pages[p], off - BASE)[0]


def ltr(v):
    sn = (v & 0x3FF) << (5 * ((v >> 10) & 7)) if v & (1 << 15) else None
    ns = ((v >> 16) & 0x3FF) << (5 * ((v >> 26) & 7)) if v & (1 << 31) else None
    f = lambda x: "-" if x is None else (f"{x/1e6:.1f}ms" if x >= 1e6 else f"{x/1e3:.0f}us" if x >= 1e3 else f"{x}ns")
    return f"{f(sn)}/{f(ns)}"


w = 18
print("columns: " + ", ".join(cols))
print(f"SLP_S0 counter: " + "  ".join(f"{r32(c, 0x193C)}" for c in cols))
print(f"LTR_IGNORE:     " + "  ".join(f"0x{r32(c, 0x1B0C):08x}" for c in cols))
print("\n== LTR (snoop/non-snoop; '-' = no requirement). 0x1B50-0x1B5C = platform/aggregate words, raw")
for off in (0x1B50, 0x1B54, 0x1B58, 0x1B5C):
    vals = [r32(c, off) for c in cols]
    print(f"{'*' if len(set(vals)) > 1 else ' '} 0x{off:04X} {'':16}" + "".join(f"{('0x%08x ' % v + ltr(v)):>{w + 12}}" for v in vals))
for name, off in names["ltr"]:
    vals = [r32(c, off) for c in cols]
    print(f"{'*' if len(set(vals)) > 1 else ' '} {name:22}" + "".join(f"{('0x%08x ' % v + ltr(v)):>{w + 12}}" for v in vals))

print("\n== PFEAR: IPs NOT power gated")
for c in cols:
    pf = pages[c][0x1D90 - BASE:0x1D90 - BASE + 9]
    on = [n for i, n in enumerate(names["pfear"]) if not (pf[i // 8] >> (i % 8)) & 1 and not n.startswith("RES")]
    print(f"  {c:12} {', '.join(on)}")

print("\n== live LPM requirement status (listed = NOT met)")
for i, (mapname, bits) in enumerate(names["lpm"].items()):
    short = mapname.replace("tgl_", "").replace("_map", "")
    rows = []
    for c in cols:
        live = r32(c, 0x1C5C + 4 * i)
        unmet = [n for n, mask in bits if isinstance(mask, int) and not live & mask]
        rows.append((live, unmet))
    diff = len({r[0] for r in rows}) > 1
    print(f"{'*' if diff else ' '} {short}")
    for c, (live, unmet) in zip(cols, rows):
        print(f"    {c:12} 0x{live:08x}  {', '.join(unmet) or '-'}")
