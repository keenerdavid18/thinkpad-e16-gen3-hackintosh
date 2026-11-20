#!/bin/bash
# nvme-state-test.sh: does an NVMe drive whose controller is SHUT DOWN but left in D0 (= macOS Deep Idle with
# S0ixStandby -s0ixnvmed0) keep Linux s2idle out of PC10? macOS results 2026-11-18: drives in D3 -> PC2;
# D0 + controller shut down -> PC3 99 %; D0 + our own re-enabled controller in PS4 -> PC2 85 %. Linux (nvme.noacpi=1)
# keeps a live controller in its deepest PS -> PC10.
# Only touches the NVMe drive that has no mounted filesystem / active LVM (the Windows drive): unbinding the nvme
# driver shuts its controller down (CC.SHN) and leaves it in D0 without a driver; rebinding restores it.
#   sudo bash nvme-state-test.sh          -> ~/nvme-state-test-<date-time>.txt   (~3 min, screen goes dark 4 times)
set -u
export LC_ALL=C
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
out=${SUDO_USER:+/home/$SUDO_USER}/nvme-state-test-$(date +%F-%H%M).txt
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

# pick the drive that holds nothing mounted / no active LVM PV
victim=""; vpci=""
for c in /sys/class/nvme/nvme*; do
	n=$(basename "$c"); pci=$(basename "$(readlink -f "$c/device")")
	busy=$(lsblk -nro MOUNTPOINTS,FSTYPE /dev/${n}n1 2>/dev/null | grep -E '^/|LVM2_member|crypto_LUKS' | head -1)
	log "$n $pci model $(cat $c/model 2>/dev/null | xargs) ${busy:+(in use: $busy)}"
	[[ -z $busy && -z $victim ]] && { victim=$n; vpci=$pci; }
done
[[ -n $victim ]] || { log "no idle NVMe drive found - nothing to test"; exit 1; }
log "=== $(date)  kernel $(uname -r)  test drive $victim ($vpci)  cmdline: $(cat /proc/cmdline)"
log "power: $(cat /sys/class/power_supply/AC*/online 2>/dev/null | head -1) (1 = AC)"
cycle "baseline (both drives live)"
echo "$vpci" > /sys/bus/pci/drivers/nvme/unbind || { log "unbind failed"; exit 1; }
sleep 2
log "  $vpci unbound: controller shut down, power_state $(cat /sys/bus/pci/devices/$vpci/power_state 2>/dev/null)"
cycle "$victim shut down, D0, no driver"
cycle "$victim shut down, D0, no driver (again)"
echo "$vpci" > /sys/bus/pci/drivers/nvme/bind || log "  WARNING: rebind failed - reboot Ubuntu"
sleep 5
cycle "baseline after rebind"
log "saved to $out"
