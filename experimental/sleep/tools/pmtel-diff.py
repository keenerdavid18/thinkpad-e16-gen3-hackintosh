#!/usr/bin/env python3
"""Diff two `pmtel ... cstate_counter` outputs by the raw values (16-bit counters: (after - before) & 0xFFFF)."""
import re, sys
def load(f):
    d = {}
    for l in open(f):
        m = re.search(r'cstate_counter/(\S+).*raw (\d+) -> (\d+)', l)
        if m: d[m.group(1)] = int(m.group(3))
    return d
a, b = load(sys.argv[1]), load(sys.argv[2])
rows = [(k, (b[k] - a[k]) & 0xFFFF, b[k]) for k in a if k in b and (b[k] - a[k]) & 0xFFFF]
for k, d, v in sorted(rows, key=lambda r: -r[1]):
    print(f"  {k:36} +{d:6}   (now {v})")
if not rows: print("  (no counter changed)")
