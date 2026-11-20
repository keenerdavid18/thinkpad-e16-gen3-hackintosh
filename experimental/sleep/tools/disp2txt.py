#!/usr/bin/env python3
"""debug.s0ix.disp / disphalt binary (u32 per register, gpu-wm.py RANGES order) -> '0xOFF 0xVAL' lines for gpu-wm.py."""
import struct
import sys
RANGES = [(0x44FE0, 0x45040), (0x45270, 0x45280), (0x45500, 0x45530), (0x60000, 0x60080), (0x61000, 0x61080),
          (0x70000, 0x70600), (0x71000, 0x71600), (0x72000, 0x72600), (0x73000, 0x73600), (0x101080, 0x101090)]
offs = [o for a, b in RANGES for o in range(a, b, 4)]
b = open(sys.argv[1], "rb").read()
assert len(b) == 4 * len(offs), f"{len(b)} bytes, want {4 * len(offs)}"
print(f"== macOS S0ixStandby {sys.argv[1].rsplit('/', 1)[-1]}")
for o, v in zip(offs, struct.unpack(f"<{len(offs)}I", b)):
    print(f"0x{o:x} 0x{v:08x}")
