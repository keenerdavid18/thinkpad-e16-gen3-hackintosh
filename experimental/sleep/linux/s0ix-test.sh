#!/bin/bash
# s2idle reaches no S0ix at all (slp_s0 residency 0, ~3.65 W asleep, 2026-11-13). What blocks it - measured while
# actually suspended, not awake. One s2idle cycle with all the kernel's own diagnostics switched on:
#   - pm_debug_messages: pmc_core dumps the PMC "LPM STATUS" (which IP/PLL was not off) on resume, and
#     acpi/x86/s2idle prints "LPI: Constraint not met" for devices above their firmware (PEP) minimum D-state
#   - dynamic debug on drivers/pci/pci-driver.c: "PCI PM: Suspend power state: D3cold/D3hot/D0" for every device
#   - package C-state residency MSRs (PC2..PC10) and S0ix counters before/after -> how deep the package got
# Run on battery, dock + Ethernet + USB-C unplugged, then change ONE thing (step 2 of the plan) and run it again.
#   sudo bash s0ix-test.sh [secs=90] [label]   -> appends to ~/s0ix-test-<date>.txt
set -u
[[ $EUID -eq 0 ]] || { echo "run with sudo"; exit 1; }
SECS=${1:-90}; LABEL=${2:-baseline}
out=${SUDO_USER:+/home/$SUDO_USER}/s0ix-test-$(date +%F).txt
mountpoint -q /sys/kernel/debug || mount -t debugfs none /sys/kernel/debug
modprobe msr 2>/dev/null
PMC=/sys/kernel/debug/pmc_core; DYN=/sys/kernel/debug/dynamic_debug/control
CPUIDLE=/sys/devices/system/cpu/cpuidle

log() { echo "$*" | tee -a "$out"; }
msr() { local v; v=$(rdmsr -p0 -u "$1" 2>/dev/null); echo "${v:-0}"; }
# package C-state residency counters (count at TSC rate): PC2 PC3 PC6 PC7 PC8 PC9 PC10; last = TSC itself
PCS=(PC2:0x60D PC3:0x3F8 PC6:0x3F9 PC7:0x3FA PC8:0x630 PC9:0x631 PC10:0x632 TSC:0x10)
readpc() { local r=""; for p in "${PCS[@]}"; do r+="$(msr ${p#*:}) "; done; echo "$r"; }
bat() { cat /sys/class/power_supply/BAT*/energy_now 2>/dev/null | head -1; }
rd() { cat "$1" 2>/dev/null || echo "?"; }

log ""
log "=== $(date)  label=$LABEL  ${SECS}s  kernel $(uname -r)"
log "cmdline: $(cat /proc/cmdline)"
log "nvme suspend mode: $(journalctl -k -b --no-pager | grep -o 'nvme [0-9a-f:.]*: platform quirk: setting simple suspend' | tr '\n' ';')  (none = host-managed: stays D0 + APST)"
log "power: $(rd /sys/class/power_supply/BAT0/status)  AC online=$(cat /sys/class/power_supply/A*/online 2>/dev/null | head -1)" \
	" ethernet carrier=$(cat /sys/class/net/e*/carrier 2>/dev/null | head -1)  rfkill: $(rfkill -n -o TYPE,SOFT 2>/dev/null | tr '\n' ' ')"
log "usb devices: $(lsusb | grep -v 'root hub' | cut -d' ' -f6- | tr '\n' ';')"
log "typec partners: $(ls -d /sys/class/typec/port*-partner 2>/dev/null | xargs -r -n1 basename | tr '\n' ' ')"
log "-- PCI devices awake (runtime power state / d3cold_allowed / driver):"
for d in /sys/bus/pci/devices/*; do
	log "   ${d##*/} $(rd $d/power_state) rt=$(rd $d/power/runtime_status) d3cold=$(rd $d/d3cold_allowed)" \
		"$(basename "$(readlink $d/driver)" 2>/dev/null)"
done
log "-- PCIe link power (NVMe + root ports): ASPM in LnkCtl, ASPM/PCI-PM L1.1/L1.2 enables in L1SubCtl1, LTR in DevCtl2:"
for dev in $(lspci -D | awk '/PCI bridge|Non-Volatile/ {print $1}'); do
	log "   $dev $(lspci -s $dev | cut -d' ' -f2- | cut -c1-50)"
	lspci -vvv -s $dev 2>/dev/null | grep -E 'LnkCtl:|L1SubCtl1:|DevCtl2:' | sed 's/^\s*/      /' | tee -a "$out" >/dev/null
done
[[ -r $PMC/ltr_show ]] && { log "-- pmc_core ltr_show (awake):"; grep -v ': 0x0 ' $PMC/ltr_show | sed 's/^/   /' | tee -a "$out" >/dev/null; }
[[ $LABEL == baseline && -r $PMC/substate_requirements ]] && {
	log "-- pmc_core substate_requirements (static table, which IPs each S0ix substate needs):"
	sed 's/^/   /' $PMC/substate_requirements >> "$out"; }

# --- switch diagnostics on (restored on exit) ---
dbg_prev=$(cat /sys/power/pm_debug_messages)
restore() { echo "$dbg_prev" > /sys/power/pm_debug_messages; [[ -w $DYN ]] && echo 'file drivers/pci/pci-driver.c -p' > $DYN; }
trap restore EXIT
echo 1 > /sys/power/pm_debug_messages
[[ -w $DYN ]] && echo 'file drivers/pci/pci-driver.c +p' > $DYN
grep -q '\[s2idle\]' /sys/power/mem_sleep || log "WARNING mem_sleep is $(cat /sys/power/mem_sleep)"

pc0=($(readpc)); s0=$(rd $PMC/slp_s0_residency_usec); l0=$(rd $CPUIDLE/low_power_idle_system_residency_us)
lc0=$(rd $CPUIDLE/low_power_idle_cpu_residency_us); tsc0=$(date +%s.%N); b0=$(bat)
marker="s0ix-test marker $RANDOM"; echo "$marker" > /dev/kmsg
log "== s2idle for ${SECS}s at $(date +%T) - don't touch anything, it wakes by itself"
sync; rtcwake -m freeze -s "$SECS" >/dev/null 2>&1
t1=$(date +%s.%N); b1=$(bat); pc1=($(readpc)); s1=$(rd $PMC/slp_s0_residency_usec)
l1=$(rd $CPUIDLE/low_power_idle_system_residency_us); lc1=$(rd $CPUIDLE/low_power_idle_cpu_residency_us)
log "== back at $(date +%T)"

el=$(awk -v a="$tsc0" -v b="$t1" 'BEGIN {printf "%.1f", b-a}')
log "-- RESULT ($el s wall clock):"
log "   S0ix: slp_s0_residency_usec $s0 -> $s1  (+$(( ${s1//\?/0} - ${s0//\?/0} )) us)" \
	"| low_power_idle system +$(( ${l1//\?/0} - ${l0//\?/0} )) us, cpu +$(( ${lc1//\?/0} - ${lc0//\?/0} )) us"
log "   last_hw_sleep: $(rd /sys/power/suspend_stats/last_hw_sleep) us  total_hw_sleep: $(rd /sys/power/suspend_stats/total_hw_sleep) us" \
	" wakeup irq: $(rd /sys/power/pm_wakeup_irq)"
# residency counters tick at TSC rate -> % of the TSC delta over the cycle (includes ~1-2 s of freeze/thaw)
n=$(( ${#PCS[@]} - 1 )); dt=$(( pc1[n] - pc0[n] ))
line="   package C-states over the cycle (% of time):"
for (( i=0; i<n; i++ )); do
	d=$(( pc1[i] - pc0[i] ))
	line+=" ${PCS[i]%%:*} $(awk -v d=$d -v t=$dt 'BEGIN {if (t>0) printf "%.1f%%", 100*d/t; else print "?"}')"
done
log "$line"
[[ -n $b0 && -n $b1 ]] && log "   battery $b0 -> $b1 uWh: $(awk -v a=$b0 -v b=$b1 -v t=$el 'BEGIN {printf "%.0f mW", (a-b)/1000/(t/3600)}') (coarse below 600 s)"

log "-- kernel messages from the cycle (pmc_core LPM status, LPI constraints, PCI suspend states, wake source):"
dmesg | awk -v m="$marker" 'index($0, m) {on=1; next} on' |
	grep -E 'pmc_core|intel_pmc|LPM|SLP_S0|S0ix|LPI|Constraint|PEPD|PCI PM: Suspend power state|Wakeup|wakeup|PM: (suspend|resume|Triggering)|s2idle|ACPI: EC|error|fail' |
	sed 's/^\[ *[0-9.]*\] /   /' | tee -a "$out" >/dev/null
log "   (full: dmesg lines after '$marker')"
for f in substate_status_registers substate_residencies package_cstate_show pll_status; do
	[[ -r $PMC/$f ]] && { log "-- pmc_core $f (after):"; sed 's/^/   /' $PMC/$f >> "$out"; }
done
log "== done $(date +%T)"
chown "${SUDO_USER:-root}" "$out"
echo; echo "saved $out"
grep -E 'S0ix:|package C-states|battery .* mW' "$out" | tail -3
