#!/usr/bin/env python3
# Dumps the HDA codec's widget graph through AppleALC's alc-verb (needs boot-arg alcverbs=1):
# widget type, pin default config, pin caps, amp caps and connection list for every node of
# the audio function group - the facts needed to write an AppleALC layout/platform/pin config.
#   python3 dump-codec.py [path/to/alc-verb]   (default: build/alc-verb next to this script)
import os, subprocess, sys

VERB = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "build", "alc-verb")
TYPES = ["Audio Output", "Audio Input", "Audio Mixer", "Audio Selector", "Pin Complex",
         "Power Widget", "Volume Knob", "Beep Generator"]
DEVICES = ["Line Out", "Speaker", "HP Out", "CD", "SPDIF Out", "Digital Out", "Modem Line",
           "Modem Handset", "Line In", "AUX", "Mic In", "Telephony", "SPDIF In", "Digital In",
           "Reserved", "Other"]
CONN = ["Jack", "None", "Fixed", "Both"]


def verb(nid, v, p):
    out = subprocess.run([VERB, "-q", hex(nid), v, p], capture_output=True, text=True).stdout.split()
    return int(out[-1], 16) if out else None


def conn_list(nid):
    n = verb(nid, "PARAMETERS", "CONNLIST_LEN") or 0
    long_form, count = bool(n & 0x80), n & 0x7f
    per, width, out = (2, 16, []) if long_form else (4, 8, [])
    for i in range(0, count, per):
        r = verb(nid, "GET_CONNECT_LIST", hex(i))
        for k in range(per):
            if len(out) < count:
                out.append((r >> (k * width)) & ((1 << width) - 1))
    return out


print(f"Vendor {verb(0, 'PARAMETERS', 'VENDOR_ID'):#010x}  Subsystem {verb(1, 'GET_SUBSYSTEM_ID', '0'):#010x}"
      f"  Rev {verb(0, 'PARAMETERS', 'REV_ID'):#010x}")
nc = verb(1, "PARAMETERS", "NODE_COUNT")
start, count = (nc >> 16) & 0xff, nc & 0xff
for nid in range(start, start + count):
    cap = verb(nid, "PARAMETERS", "AUDIO_WIDGET_CAP")
    t = (cap >> 20) & 0xf
    line = f"Node {nid:#04x} [{TYPES[t] if t < len(TYPES) else t}] wcaps {cap:#010x}"
    if cap & 0x2:
        line += f" ampIn {verb(nid, 'PARAMETERS', 'AMP_IN_CAP'):#010x}"
    if cap & 0x4:
        line += f" ampOut {verb(nid, 'PARAMETERS', 'AMP_OUT_CAP'):#010x}"
    print(line)
    if t == 4:
        cfg = verb(nid, "GET_CONFIG_DEFAULT", "0")
        pcap = verb(nid, "PARAMETERS", "PIN_CAP")
        dev = (cfg >> 20) & 0xf
        print(f"    pincfg {cfg:#010x}  {CONN[(cfg >> 30) & 3]} {DEVICES[dev]} loc {(cfg >> 24) & 0x3f:#04x}"
              f" assoc {(cfg >> 4) & 0xf} seq {cfg & 0xf}  pincap {pcap:#010x}"
              f"{' OUT' if pcap & 0x10 else ''}{' IN' if pcap & 0x20 else ''}{' HP' if pcap & 0x8 else ''}"
              f"{' EAPD' if pcap & 0x10000 else ''}  ctl {verb(nid, 'GET_PIN_WIDGET_CONTROL', '0'):#04x}")
    if cap & 0x100:
        conns = conn_list(nid)
        sel = verb(nid, "GET_CONNECT_SEL", "0") if t != 2 else None
        print("    conn " + " ".join(f"{c:#04x}{'*' if i == sel and len(conns) > 1 else ''}" for i, c in enumerate(conns)))
