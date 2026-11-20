#!/bin/bash
# pc2-hunt.sh: which device, left powered (D0) through s2idle the way macOS leaves it, keeps the package at PC2?
# (macOS Deep Idle 2026-11-18: cores ~99 % CC7, GT RC6 100 %, PCH LTR "no requirement", TCSS D3cold done, display on or
# off - package still only PC2 73-88 %. At the halt the PMC lists GBE, HDA, LPSS, CNVi as not power-gated.)
# Linux s2idle on this laptop reaches PC10 / S0ix. A PCI device whose driver is unbound stays in D0 through s2idle
# (pci_pm_suspend_noirq skips pci_prepare_to_sleep without a driver), like a device macOS keeps on. For each candidate:
# unbind its driver, s2idle 30 s with an RTC alarm, read the package C-state counters (MSRs on CPU 0) + the SLP_S0
# counter before/after, rebind. Lid open, nothing on USB-C, battery preferred, hands off during each sleep.
#   sudo bash pc2-hunt.sh            -> ~/pc2-hunt-<date-time>.txt   (~8 min, the screen goes dark ~10 times)
# The touchpad (LPSS I2C) and Bluetooth/USB (xHCI) are briefly unbound in their own test and rebound afterwards.
set -u
export LC_ALL=C
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
out=${SUDO_USER:+/home/$SUDO_USER}/pc2-hunt-$(date +%F-%H%M).txt
SECS=${1:-30}
modprobe msr 2>/dev/null
mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug
log() { echo "$*" | tee -a "$out"; }

msrs() {  # TSC + package C-state residency counters, read on CPU 0
	python3 - <<'PY'
import os, struct
fd=os.open('/dev/cpu/0/msr', os.O_RDONLY)   # unbuffered: a buffered read returns 8 KB of the FIRST MSR repeated
def rd(m):
    try: return struct.unpack('<Q', os.pread(fd, 8, m))[0]
    except OSError: return 0
print(' '.join(str(rd(m)) for m in (0x10, 0x60D, 0x3F8, 0x3F9, 0x3FA, 0x630, 0x631, 0x632)))
PY
}
slps0() { cat /sys/kernel/debug/pmc_core/slp_s0_residency_usec 2>/dev/null || echo 0; }
energy() { cat /sys/class/powercap/intel-rapl:0/energy_uj 2>/dev/null || echo 0; }

cycle() {  # $1 label
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
print(f"{lab:34} " + ' '.join(f"{n} {pct(i+1):5.1f}" for i,n in enumerate(names)) +
      f"  | SLP_S0 {(s1-s0)/1e6:5.1f} s of {t1-t0:4.0f} s | pkg {w:5.2f} W (incl. entry/exit)")
PY
}

# candidate PCI functions: what macOS leaves powered at the halt (PMC PFEAR not gated) + other macOS-only-D0 devices
declare -A WHAT=(
	[0000:00:14.3]="CNVi Wi-Fi (macOS: ForbiddenItlwm)"
	[0000:00:1f.3]="HD Audio (macOS: AppleALC/AppleHDA)"
	[0000:00:1f.6]="GbE (macOS: IntelMausi)"
	[0000:00:15.0]="LPSS I2C0 (touchpad ELAN06C8)"
	[0000:00:15.2]="LPSS I2C2 (touchscreen PRT0818)"
	[0000:00:0d.0]="TCSS xHCI (Type-C USB)"
	[0000:00:0d.2]="TBT DMA0"
	[0000:00:14.0]="PCH xHCI (Bluetooth, USB-A)"
	[0000:00:12.0]="ISH sensor hub"
	[0000:00:16.0]="CSME HECI"
	[0000:00:04.0]="DPTF thermal"
)
ORDER=(0000:00:14.3 0000:00:1f.3 0000:00:1f.6 0000:00:15.0 0000:00:15.2 0000:00:0d.0 0000:00:0d.2 0000:00:14.0 0000:00:12.0 0000:00:16.0 0000:00:04.0)

log ""
log "=== $(date)  kernel $(uname -r)  ${SECS}s per sleep"
log "cmdline: $(cat /proc/cmdline)"
log "mem_sleep: $(cat /sys/power/mem_sleep)  power: $(cat /sys/class/power_supply/AC*/online 2>/dev/null | head -1) (1 = AC)"
log "--- devices (driver, power state):"
for d in "${ORDER[@]}"; do
	[[ -e /sys/bus/pci/devices/$d ]] || continue
	log "  $d $(basename "$(readlink /sys/bus/pci/devices/$d/driver 2>/dev/null)" 2>/dev/null || echo none) $(cat /sys/bus/pci/devices/$d/power_state 2>/dev/null)  ${WHAT[$d]}"
done
log ""
cycle "baseline (all drivers bound)"
cycle "baseline again"

for d in "${ORDER[@]}"; do
	p=/sys/bus/pci/devices/$d
	[[ -e $p/driver ]] || { log "$(printf '%-34s' "${WHAT[$d]%% (*}") skipped: no driver bound ($d)"; continue; }
	drv=$(basename "$(readlink $p/driver)")
	echo "$d" > $p/driver/unbind 2>/dev/null || { log "$d: unbind failed"; continue; }
	sleep 2
	log "  ($d unbound from $drv, now $(cat $p/power_state 2>/dev/null))"
	cycle "D0: ${WHAT[$d]%% (*} [$drv]"
	echo "$d" > /sys/bus/pci/drivers/$drv/bind 2>/dev/null || log "  WARNING: rebind of $d to $drv failed - reboot Ubuntu afterwards"
	sleep 3
done

# everything macOS leaves on, at once
held=()
for d in 0000:00:14.3 0000:00:1f.3 0000:00:1f.6 0000:00:15.0 0000:00:15.2; do
	p=/sys/bus/pci/devices/$d
	[[ -e $p/driver ]] || continue
	held+=("$d:$(basename "$(readlink $p/driver)")")
	echo "$d" > $p/driver/unbind 2>/dev/null
done
sleep 2
log "  (together: $(for h in "${held[@]}"; do printf '%s=%s ' "${h%:*}" "$(cat /sys/bus/pci/devices/${h%:*}/power_state)"; done))"
cycle "D0: Wi-Fi+HDA+GbE+LPSS together"
for h in "${held[@]}"; do d=${h%:*}; drv=${h##*:}; echo "$d" > /sys/bus/pci/drivers/$drv/bind 2>/dev/null || log "  WARNING: rebind $d failed"; done
sleep 3
cycle "baseline at the end"
log "saved to $out"
