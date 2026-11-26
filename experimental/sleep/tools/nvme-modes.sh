#!/bin/zsh
# nvme-modes.sh: run several Deep Idle sleeps in one boot, each with a different NVMe handling (S0ixStandby
# debug.s0ix.nvme, e97e95fb+), woken by the RTC after ~4 min. Battery, lid open, nothing on USB-C, hands off.
#   sudo zsh experimental/sleep/tools/nvme-modes.sh [modes...]     default modes: 1 2 0x102 0x202 0x12
#   0 macOS D3 | 1 D0 shut down | 2 D0 live PS4 (both) | 0x102 live only bus 4 (SK Hynix) | 0x202 live only bus 5 (SPCC)
#   +0x400 / +0x800: bus 4 (SK Hynix) / bus 5 (SPCC) stays in macOS D3 (S0ixStandby 2026-11-23+), e.g. 0x401 = Hynix D3 + SPCC shut down
#   +0x10 MSI-X masked during the halt; +0x20 HMB on then off before PS4 (Linux); +0x40 HMB kept on (e97e95fb+/3af5668b+).
#   Summary -> experimental/sleep/tools/results/nvme-modes-<time>.txt (+ one sleep-power2 file each)
[[ $EUID -eq 0 ]] || { print "run with sudo"; exit 1; }
here=${0:A:h}; mkdir -p $here/results; user=${SUDO_USER:-$USER}
out=$here/results/nvme-modes-$(date +%Y%m%d-%H%M%S).txt
sysctl -n debug.s0ix.nvme >/dev/null 2>&1 || { print "debug.s0ix.nvme missing - S0ixStandby e97e95fb+ needed"; exit 1; }
if (( $# )); then modes=($@); else modes=(1 2 0x102 0x202 0x12); fi
orig=$(sysctl -n debug.s0ix.nvme)
print "== $(date)  modes: $modes  (sysctl was $orig)  $(pmset -g batt | tail -1 | cut -c1-60)" | tee $out
for m in $modes; do
  sysctl -w debug.s0ix.nvme=$(( m )) >/dev/null
  if (( (m & 0x60) && !hmbReady )); then   # HMB modes: the 60 s timer allocates the 4 MB chunks first
    print "   (waiting 70 s for the HMB buffers to be allocated)" | tee -a $out; sleep 70; hmbReady=1
  fi
  print "\n-- mode $m: sleeping ~4 min (RTC wake), $(date +%T)" | tee -a $out
  b=${out:r}-m$m-nvcfg; sysctl -b debug.s0ix.nvcfg > $b-before.bin 2>/dev/null
  pmset relative wake 260 >/dev/null
  sudo -u $user zsh $here/sleep-power.sh >/dev/null 2>&1
  f=$(ls -t $here/results/sleep-power2-*.txt | head -1)
  { grep -E 'asleep|CPU package|xcpm:|NVMe at last sleep|NVMe power state' $f | sed 's/^ */   /'; print "   file: ${f:t}"
    if sysctl -b debug.s0ix.nvcfg > $b-after.bin 2>/dev/null && [[ -s $b-after.bin ]]; then
      # link pattern at the halt: 0x328 top byte 0x40 + 0x480 0x1111 = idle (Linux PC10), 0x33 + 0x7575 = busy
      python3 $here/nvcfg.py $b-after.bin $b-before.bin | grep -E '^== 00|^  (awake|halt|after) |0x328=' | sed 's/^/   /'
    fi; } | tee -a $out
  sleep 20
done
sysctl -w debug.s0ix.nvme=$orig >/dev/null
chown $user $out ${out:r}-m*-nvcfg-*.bin 2>/dev/null
print "\nsaved $out (debug.s0ix.nvme back to $orig)" | tee -a $out
