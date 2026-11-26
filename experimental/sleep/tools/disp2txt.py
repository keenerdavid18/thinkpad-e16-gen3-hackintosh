#!/usr/bin/env python3
"""debug.s0ix.disp / disphalt binary (u32 per register, gpu-wm.py RANGES order) -> '0xOFF 0xVAL' lines for gpu-wm.py."""
import struct
import sys
RANGES = [(0x44FE0, 0x45040), (0x45270, 0x45280), (0x45500, 0x45530), (0x60000, 0x60080), (0x61000, 0x61080),
          (0x70000, 0x70600), (0x71000, 0x71600), (0x72000, 0x72600), (0x73000, 0x73600), (0x101080, 0x101090)]
# appended 2026-11-24 (S0ixStandby kext with the interrupt-register dump): hotplug ctl, DISPLAY_INT_CTL, DE pipe/port/
# misc/HPD ISR-IMR-IIR-IER, GU misc, PCH SDE + SHOTPLUG, GT master/enables. Older dumps lack them.
IRQ = [(0x44030, 0x44040), (0x44200, 0x44210), (0x44400, 0x44480), (0x444F0, 0x44500), (0xC4000, 0xC4040),
       (0x190000, 0x190100)]
b = open(sys.argv[1], "rb").read()
offs = [o for a, c in RANGES for o in range(a, c, 4)]
if len(b) != 4 * len(offs):
    offs += [o for a, c in IRQ for o in range(a, c, 4)]
assert len(b) == 4 * len(offs), f"{len(b)} bytes, want {4 * len(offs)}"
print(f"== macOS S0ixStandby {sys.argv[1].rsplit('/', 1)[-1]}")
for o, v in zip(offs, struct.unpack(f"<{len(offs)}I", b)):
    print(f"0x{o:x} 0x{v:08x}")
