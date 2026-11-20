#!/usr/bin/env python3
"""Assemble SSDT-LIDWAKE.aml (see SSDT-LIDWAKE.dsl). Usage: make-ssdt-lidwake.py OUT.aml [--always]
--always (v2, SSDT-LIDWAKE2): EC GPE 0x6E under Darwin on AC too (for S0ixStandby's EC event filter)."""
import struct, sys

def pkglen(body):                 # PkgLength includes its own bytes: 1-byte form < 64, 2-byte form < 4096
    n = len(body) + 1
    if n < 64:
        return bytes([n]) + body
    n = len(body) + 2
    assert n < 4096, n
    return bytes([0x40 | (n & 0x0F), (n >> 4) & 0xFF]) + body

SB_LID = b"\x5c\x2e" + b"_SB_" + b"LID_"                      # \_SB_.LID_  (RootChar, DualNamePrefix)
SB_LID_XPRW = b"\x5c\x2f\x03" + b"_SB_" + b"LID_" + b"XPRW"   # \_SB_.LID_.XPRW (MultiNamePrefix, 3 segs)
AC_PSR = b"\x5c\x2f\x06" + b"_SB_" + b"PC00" + b"LPCB" + b"EC__" + b"AC__" + b"_PSR"   # \_SB.PC00.LPCB.EC.AC._PSR

ext = (b"\x15" + SB_LID + b"\x06\x00" +                       # External (\_SB.LID, DeviceObj)
       b"\x15" + SB_LID_XPRW + b"\x08\x00" +                  # External (\_SB.LID.XPRW, MethodObj, 0 args)
       b"\x15" + AC_PSR + b"\x08\x00")                        # External (\_SB.PC00.LPCB.EC.AC._PSR, MethodObj, 0)
if_zero = b"\xa0" + pkglen(b"\x00" + ext)                     # If (Zero) { externals }

pkg = b"\x12" + pkglen(b"\x02" + b"\x0a\x6e" + b"\x0a\x03")   # Package (2) { 0x6E, 0x03 }
ret_pkg = b"\xa4" + pkg
osi = b"_OSI" + b"\x0d" + b"Darwin\x00"                       # _OSI ("Darwin")
on_batt = b"\x93" + AC_PSR + b"\x00"                           # LEqual (AC._PSR (), Zero)
if_darwin = b"\xa0" + pkglen(b"\x90" + osi + on_batt + ret_pkg) # If (LAnd (_OSI ("Darwin"), on battery))
ALWAYS = "--always" in sys.argv
if ALWAYS: if_darwin = b"\xa0" + pkglen(osi + ret_pkg)          # If (_OSI ("Darwin"))  (v2: AC too)
ret_x = b"\xa4" + SB_LID_XPRW                                 # Return (\_SB.LID.XPRW ())
method = b"\x14" + pkglen(b"_PRW" + b"\x00" + if_darwin + ret_x)
scope = b"\x10" + pkglen(SB_LID + method)

body = if_zero + scope
hdr = b"SSDT" + struct.pack("<IBB", 36 + len(body), 2, 0) + b"HACK  " + (b"LIDWAKE2" if ALWAYS else b"LIDWAKE ") + struct.pack("<I", 2 if ALWAYS else 1) \
      + b"INTL" + struct.pack("<I", 0x20200925)
t = bytearray(hdr + body)
t[9] = (-sum(t)) & 0xFF
assert sum(t) & 0xFF == 0
open(sys.argv[1], "wb").write(t)
print(len(t), "bytes:", t.hex())
