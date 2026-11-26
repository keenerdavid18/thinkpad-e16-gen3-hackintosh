#!/usr/bin/env python3
"""Decode S0ixStandby's debug.s0ix.nvcfg: config space of the NVMe root ports (00:06.x) and drives,
live / right before the last Deep Idle halt (quiesce, root ports only) / right after it (active).

    sysctl -b debug.s0ix.nvcfg > x.bin; nvcfg.py x.bin          # or: nvcfg.py (reads the sysctl itself)
    nvcfg.py after.bin before.bin    # "live" = the awake copy in before.bin (saved before the sleep)
    nvcfg.py --linux 00:06.0=/sys/bus/pci/devices/0000:00:06.0/config ...   (raw 4 KB dumps, e.g. from Ubuntu)

The question it answers: is each root port's link in L1 (L1.2) at the halt, and what else differs from awake.
"""
import struct, subprocess, sys

SPEED = {1: "2.5GT", 2: "5GT", 3: "8GT", 4: "16GT", 5: "32GT"}


def dw(b, o):
    return struct.unpack_from("<I", b, o)[0]


def caps(b):
    out, p, seen = {}, b[0x34] & 0xFC, 0
    while p and seen < 48:
        out.setdefault(b[p], p); p = b[p + 1] & 0xFC; seen += 1
    p, seen = 0x100, 0
    while p and seen < 48 and p < 0x1000:
        h = dw(b, p)
        if h in (0, 0xFFFFFFFF): break
        out.setdefault(0x10000 | (h & 0xFFFF), p); p = (h >> 20) & 0xFFC; seen += 1
    return out


def link(b):
    c = caps(b); s = []
    if 0x10 in c:
        e = c[0x10]
        lc, ls = struct.unpack_from("<HH", b, e + 0x10)
        aspm = ["off", "L0s", "L1", "L0s+L1"][lc & 3]
        s.append(f"LNKCTL ASPM {aspm}{' CLKPM' if lc & 0x100 else ''}  LNKSTA x{(ls >> 4) & 0x3F} {SPEED.get(ls & 0xF, ls & 0xF)}"
                 f"{' training' if ls & 0x800 else ''}{' DLLA' if ls & 0x2000 else ' DL-down'}")
        dc2 = struct.unpack_from("<H", b, e + 0x28)[0]
        s.append(f"DEVCTL2 LTR {'on' if dc2 & 0x400 else 'off'}")
    if 0x1001E in c:
        o = c[0x1001E]; c1 = dw(b, o + 8)
        en = [n for bit, n in ((0, "PCI-PM L1.2"), (1, "PCI-PM L1.1"), (2, "ASPM L1.2"), (3, "ASPM L1.1")) if c1 & (1 << bit)]
        s.append("L1SS " + (",".join(en) or "none") + f" (ctl1 0x{c1:08x})")
    if 0x01 in c:
        pm = struct.unpack_from("<H", b, c[0x01] + 4)[0]
        s.append(f"D{pm & 3}")
    return "  ".join(s)


# Intel PCIe root port registers (PCH 600/700 series datasheet vol. 2; the CPU PEG/x4 ports of ADL/RPL share the IP).
# Names are a hint only: the diff below lists every dword that changed, named or not.
# 0x328 top byte / 0x480 on this E16 (Ubuntu rp-link-test 2026-11-23): 0x40 + 0x11110000 = link idle (what Linux shows
# while the package reaches PC8/PC10), 0x33 + 0x75750000 = link busy / not idle (disk I/O moments in Linux).
INTEL = {0x324: "PCIEDBG", 0x328: "PCIESTS1 (31:24 LTSSM)", 0x32C: "PCIESTS2", 0x338: "PCIEALC",
         0x420: "PCIEPMECTL", 0x424: "PCIEPMECTL2", 0x428: "PCE", 0x4A4: "PGCTL?", 0xE0: "RPDCGEN?",
         0xE8: "PWRCTL?", 0xE4: "?", 0x5C8: "?"}


def main():
    a = sys.argv[1:]
    if a and a[0] == "--linux":
        for x in a[1:]:
            name, path = x.split("=", 1)
            b = open(path, "rb").read()
            print(f"{name}: {link(b)}")
            print("  " + "  ".join(f"0x{o:03x} {dw(b, o):08x}" for o in sorted(INTEL) if o + 4 <= len(b)))
        return
    raw = open(a[0], "rb").read() if a else subprocess.run(["sysctl", "-b", "debug.s0ix.nvcfg"], capture_output=True).stdout
    if len(raw) < 64:
        sys.exit("no debug.s0ix.nvcfg (kext too old, or not loaded)")
    before = open(a[1], "rb").read() if len(a) > 1 else raw
    hdr = struct.unpack_from("<16I", raw, 0)
    n, hv, av, sleeps = hdr[:4]
    blk = n * 4096
    view = lambda k, s: raw[64 + k * blk + s * 4096: 64 + k * blk + (s + 1) * 4096]
    print(f"slots {n}, sleeps snapshotted {sleeps}, halt copy {'valid' if hv else 'none'}, after-halt copy {'valid' if av else 'none'}")
    for s in range(n):
        bdf = hdr[4 + s]
        if bdf == 0xFFFFFFFF: continue
        name = f"{bdf >> 8:02x}:{(bdf >> 3) & 31:02x}.{bdf & 7}"
        rp = (bdf >> 8) == 0
        L, H, A = before[64 + s * 4096: 64 + (s + 1) * 4096], view(1, s), view(2, s)
        print(f"\n== {name} {'root port' if rp else 'drive'}")
        print(f"  awake {'(before)' if len(a) > 1 else '(now)   '}  {link(L)}")
        if rp and hv: print(f"  at the halt       {link(H)}")
        if av: print(f"  right after it    {link(A)}")
        if rp:
            for tag, b in (("awake", L), ("halt", H), ("after", A)):
                if tag == "halt" and not hv or tag == "after" and not av: continue
                st = {0x40: "IDLE (Linux PC10 pattern)", 0x33: "BUSY (not idle)"}.get(dw(b, 0x328) >> 24, "?")
                print(f"  {tag:5} link {st:26} " + "  ".join(f"0x{o:03x}={dw(b, o):08x}" for o in (0x328, 0x480, 0x5F0, 0x6CC)))
        if rp and hv:
            d = [(o, dw(L, o), dw(H, o), dw(A, o) if av else None) for o in range(0, 4096, 4) if dw(L, o) != dw(H, o)]
            print(f"  {len(d)} dwords differ live vs halt (offset live halt after):")
            for o, l, h, x in d:
                print(f"    0x{o:03x}  {l:08x}  {h:08x}  {'' if x is None else f'{x:08x}'}  {INTEL.get(o, '')}")


main()
