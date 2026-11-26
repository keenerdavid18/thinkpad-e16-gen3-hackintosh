#!/usr/bin/env python3
"""halt-diff.py: per-counter activity DURING a Deep Idle halt, from pmtel snapshots taken before and after one sleep.

  halt-diff.py BITS before.txt after.txt awake-rate.txt ELAPSED_S HALT_S

before/after: `pmtel 0.25 <group> <filter>` outputs (the `raw a -> b` end value is the snapshot).
awake-rate:   `pmtel 10 <group> <filter>` output taken awake just before (its `N/s` column is the awake rate).
BITS:         counter width, 16 for pmtelemetry_cpu (PUNIT counters wrap), 64 for interrupt statistics.
The time between the snapshots that is not the halt (sleep entry, wake, the script) is charged at the awake rate;
what is left over happened during the halt: halt/s = (delta - awake_rate * (ELAPSED_S - HALT_S)) / HALT_S.
"""
import re, sys

LINE = re.compile(r'^\s+(.*?)\s+total\s+(-?\d+)\s+(-?[\d.]+)/s\s+raw (-?\d+) -> (-?\d+)')


def load(path):
    vals, rates, seen = {}, {}, {}
    for l in open(path):
        m = LINE.match(l)
        if not m:
            continue
        name = re.sub(r'\s+', ' ', m.group(1)).replace(' (fmt 1)', '')
        name = re.sub(r'(First|Second) Level Interrupt Handler Count', 'interrupts', name)
        n = seen[name] = seen.get(name, 0) + 1          # same name twice (e.g. two PEGP 0) -> number them
        key = name if n == 1 else f"{name} #{n}"
        vals[key], rates[key] = int(m.group(5)), float(m.group(3))
    return vals, rates


bits, fa, fb, fr, elapsed, halt = int(sys.argv[1]), *sys.argv[2:5], float(sys.argv[5]), float(sys.argv[6])
mask = (1 << bits) - 1
a, _ = load(fa)
b, _ = load(fb)
_, rate = load(fr)
awake = max(0.0, elapsed - halt)
rows = []
for k in a:
    if k not in b:
        continue
    d = (b[k] - a[k]) & mask
    r = rate.get(k, 0.0)
    if d == 0 and r == 0:
        continue
    extra = d - r * awake
    rows.append((k, d, r, extra / halt if halt > 0 else 0.0))
print(f"  {elapsed:.0f} s between snapshots, halt {halt:.0f} s, ~{awake:.0f} s awake charged at the awake rate")
print(f"  {'counter':52} {'delta':>9} {'awake/s':>9} {'HALT/s':>9}")
for k, d, r, h in sorted(rows, key=lambda x: -x[3]):
    flag = '  <==' if h >= 1 else ''
    if bits == 16 and d > 0xF000:
        flag += '  (near 65535: may have wrapped, ignore)'
    print(f"  {k[:52]:52} {d:9d} {r:9.1f} {h:9.1f}{flag}")
if not rows:
    print("  (nothing changed)")
