#!/bin/bash
# nvme-live-test.sh: what exactly does a LIVE NVMe controller look like when Linux s2idle reaches PC10, and which part
# of it matters? (macOS 2026-11-18: controller shut down in D0 -> PC3 99 %; the kext's own re-enabled controller
# (admin queue only, no HMB, Set Features PS4) -> PC2 85 %. Linux nvme.noacpi=1 -> PC10.)
# Linux's host-managed nvme_suspend() (drivers/nvme/host/pci.c, v6.17): controller stays LIVE, I/O queues kept (frozen,
# not deleted), MSI-X untouched, HMB DISABLED (Set Features 0x0D = 0), Set Features 0x02 -> npss, APST left as is,
# pci_save_state (stays D0). So vs the kext's PS4 controller the open differences are: APST, I/O queues, MSI-X.
#   1. dump both drives: id-ctrl power fields + PS table, features 0x02/0x0C/0x0D/0x06/0x11, sysfs hmb/queue_count,
#      PCI command / MSI-X / ASPM / L1SS / LTR config
#   2. on the idle (Windows) drive only, s2idle 30 s: baseline -> APST disabled -> rebind (restores) -> baseline
# Read-only for the data on both drives (only power-management features are changed, on the idle drive).
#   sudo bash nvme-live-test.sh          -> ~/nvme-live-test-<date-time>.txt   (~2 min, screen dark 3 times)
set -u
export LC_ALL=C
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
out=${SUDO_USER:+/home/$SUDO_USER}/nvme-live-test-$(date +%F-%H%M).txt
SECS=${1:-30}
modprobe msr 2>/dev/null
mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug
log() { echo "$*" | tee -a "$out"; }
msrs() {
	python3 - <<'PY'
import os, struct
fd=os.open('/dev/cpu/0/msr', os.O_RDONLY)
def rd(m):
    try: return struct.unpack('<Q', os.pread(fd, 8, m))[0]
    except OSError: return 0
print(' '.join(str(rd(m)) for m in (0x10, 0x60D, 0x3F8, 0x3F9, 0x3FA, 0x630, 0x631, 0x632)))
PY
}
slps0() { cat /sys/kernel/debug/pmc_core/slp_s0_residency_usec 2>/dev/null || echo 0; }
energy() { cat /sys/class/powercap/intel-rapl:0/energy_uj 2>/dev/null || echo 0; }
cycle() {
	local a b s0 s1 e0 e1 t0 t1
	sync; sleep 2
	a=$(msrs); s0=$(slps0); e0=$(energy); t0=$(date +%s.%N)
	rtcwake -m freeze -s "$SECS" >/dev/null 2>&1
	b=$(msrs); s1=$(slps0); e1=$(energy); t1=$(date +%s.%N)
	python3 - "$1" "$a" "$b" "$s0" "$s1" "$e0" "$e1" "$t0" "$t1" <<'PY' | tee -a "$out"
import sys
lab=sys.argv[1]; a=list(map(int,sys.argv[2].split())); b=list(map(int,sys.argv[3].split()))
s0,s1,e0,e1=map(int,sys.argv[4:8]); t0,t1=map(float,sys.argv[8:10])
dt=b[0]-a[0]; pct=lambda i: 100*(b[i]-a[i])/dt if dt else 0
names=['PC2','PC3','PC6','PC7','PC8','PC9','PC10']
w=(e1-e0)/1e6/(t1-t0) if e1>e0 else float('nan')
print(f"{lab:40} " + ' '.join(f"{n} {pct(i+1):5.1f}" for i,n in enumerate(names)) +
      f"  | SLP_S0 {(s1-s0)/1e6:5.1f} s of {t1-t0:4.0f} s | pkg {w:5.2f} W")
PY
}
feat() {  # $1 dev $2 fid $3 label
	log "  -- feature $2 ($3):"
	nvme get-feature "$1" --feature-id="$2" --human-readable 2>&1 | sed 's/^/     /' | head -45 | tee -a "$out" >/dev/null
}

log ""
log "=== $(date)  kernel $(uname -r)  cmdline: $(cat /proc/cmdline)"
log "power: $(cat /sys/class/power_supply/AC*/online 2>/dev/null | head -1) (1 = AC)   nvme_core.default_ps_max_latency_us=$(cat /sys/module/nvme_core/parameters/default_ps_max_latency_us)  nvme.max_host_mem_size_mb=$(cat /sys/module/nvme/parameters/max_host_mem_size_mb)"

victim=""; vpci=""
for c in /sys/class/nvme/nvme*; do
	n=$(basename "$c"); pci=$(basename "$(readlink -f "$c/device")")
	busy=$(lsblk -nro MOUNTPOINTS,FSTYPE /dev/${n}n1 2>/dev/null | grep -E '^/|LVM2_member|crypto_LUKS' | head -1)
	[[ -z $busy && -z $victim ]] && { victim=$n; vpci=$pci; }
	log ""
	log "##### $n  $pci  $(cat $c/model | xargs)  fw $(cat $c/firmware_rev | xargs)  ${busy:+(in use: $busy)}"
	log "  sysfs: state=$(cat $c/state) hmb=$(cat $c/hmb 2>/dev/null) queue_count=$(cat $c/queue_count) sqsize=$(cat $c/sqsize)"
	log "  -- id-ctrl power fields:"
	nvme id-ctrl /dev/$n 2>/dev/null | grep -E '^(ver|rtd3r|rtd3e|oaes|ctratt|apsta|npss|hmpre|hmmin|hmminds|hmmaxd|vwc|mdts|nn) ' | sed 's/^/     /' | tee -a "$out" >/dev/null
	log "  -- power state table:"
	nvme id-ctrl /dev/$n 2>/dev/null | sed -n '/^ps /,$p' | sed 's/^/     /' | tee -a "$out" >/dev/null
	feat /dev/$n 0x02 "power management: current PS"
	feat /dev/$n 0x0c "APST"
	feat /dev/$n 0x0d "host memory buffer"
	feat /dev/$n 0x06 "volatile write cache"
	feat /dev/$n 0x11 "non-operational power state config"
	log "  -- PCI ($pci) and its root port:"
	for d in $pci $(basename "$(readlink -f /sys/bus/pci/devices/$pci/..)"); do
		log "     [$d]"
		lspci -vvv -s $d 2>/dev/null | grep -E 'Control:|LnkCap:|LnkCtl:|DevCtl2:|L1SubCap:|L1SubCtl1:|L1SubCtl2:|Max snoop|Max no snoop|MSI-X:|MSI:|Status: D[0-3]' | sed 's/^\s*/       /' | tee -a "$out" >/dev/null
	done
done
log ""
[[ -n $victim ]] || { log "no idle NVMe drive - skipping the sleep tests"; exit 0; }
log "=== sleep tests on $victim ($vpci), ${SECS}s each"
cycle "baseline (both drives live, APST on)"
# APST off: Set Features 0x0C with APSTE=0 and an all-zero 256-byte table
z=$(mktemp); head -c 256 /dev/zero > "$z"
nvme set-feature /dev/$victim --feature-id=0x0c --value=0 --data-len=256 --data="$z" 2>&1 | sed 's/^/  /' | tee -a "$out" >/dev/null
rm -f "$z"
log "  APST now: $(nvme get-feature /dev/$victim --feature-id=0x0c --human-readable 2>&1 | grep -iE 'enable' | head -1 | xargs)"
cycle "$victim APST OFF (Linux still sets npss)"
log "  restoring: rebind nvme on $vpci (re-runs Linux's normal setup: APST, HMB, queues)"
echo "$vpci" > /sys/bus/pci/drivers/nvme/unbind && sleep 1 && echo "$vpci" > /sys/bus/pci/drivers/nvme/bind || log "  WARNING: rebind failed - reboot Ubuntu"
sleep 5
log "  APST after rebind: $(nvme get-feature /dev/$victim --feature-id=0x0c --human-readable 2>&1 | grep -iE 'enable' | head -1 | xargs)  hmb=$(cat /sys/class/nvme/$victim/hmb 2>/dev/null)"
cycle "baseline after rebind"
log "saved to $out"
