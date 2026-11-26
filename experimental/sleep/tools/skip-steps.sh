#!/bin/zsh
# skip-steps.sh: subtraction test - macOS reaches PC6 ~45 % awake idle (links idle), but Deep Idle stops at PC2/PC3.
# Run one Deep Idle per S0ixStandby skip mask (debug.s0ix.skip, 2026-11-23+), RTC wake after ~4 min, and see which
# sleep-only step costs the package depth. Battery, lid open, nothing on USB-C, hands off (~6 min per value).
#   sudo zsh experimental/sleep/tools/skip-steps.sh [values...]      default: 0 2 4 8 1 0xF   (NVMe mode stays as set, default 1)
#   0x1 LPS0 _DSM entry/exit (EC standby, GUAM, DPOF...) - without it the EC may wake us after ~14 s; still a reading
#   0x2 TCSS D3cold   0x4 display refclk workaround   0x8 wake arming (keyboard, power button, lid pad; RTC still wakes)
#   -> experimental/sleep/tools/results/skip-steps-<time>.txt
[[ $EUID -eq 0 ]] || { print "run with sudo"; exit 1; }
here=${0:A:h}; mkdir -p $here/results; user=${SUDO_USER:-$USER}
sysctl -n debug.s0ix.skip >/dev/null 2>&1 || { print "debug.s0ix.skip missing - S0ixStandby e2ce351+ needed"; exit 1; }
out=$here/results/skip-steps-$(date +%Y%m%d-%H%M%S).txt
if (( $# )); then vals=($@); else vals=(0 2 4 8 1 0xF); fi
print "== $(date)  skip values: $vals  nvme mode $(sysctl -n debug.s0ix.nvme)  $(pmset -g batt | tail -1 | cut -c1-60)" | tee $out
pmset -a disablesleep 0 sleep 0 hibernatemode 0 standby 0 powernap 0 tcpkeepalive 0 proximitywake 0
for v in $vals; do
  sysctl -w debug.s0ix.skip=$(( v )) >/dev/null
  print "\n-- skip $v: sleeping ~4 min (RTC wake), $(date +%T)" | tee -a $out
  pmset relative wake 240 >/dev/null
  sudo -u $user zsh $here/sleep-power.sh >/dev/null 2>&1
  f=$(ls -t $here/results/sleep-power2-*.txt | head -1)
  { grep -E 'asleep|CPU package|xcpm:|last wake:' $f | sed 's/^ */   /'
    ioreg -rd1 -c S0ixStandby -w0 | grep -E '"(Skipped at last sleep|Last halt C-state percent|Last wake source)"' | sed 's/^ */   /'
    print "   file: ${f:t}"; } | tee -a $out
  sleep 20
done
sysctl -w debug.s0ix.skip=0 >/dev/null
chown $user $out 2>/dev/null
print "\nsaved $out (debug.s0ix.skip back to 0)" | tee -a $out
