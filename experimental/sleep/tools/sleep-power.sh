#!/bin/zsh
# sleep-power.sh: sleep once and measure (a) battery drain (gauge mAh x V) and (b) CPU package energy (RAPL via
# NootedGreen's debug.xepm.sensors - keeps counting in Deep Idle). No sudo. On battery, below ~95 % charge.
#   zsh experimental/sleep/tools/sleep-power.sh     -> experimental/sleep/tools/results/sleep-power2-<time>.txt   (wake it after 20+ min)
#   zsh experimental/sleep/tools/sleep-power.sh lid -> does not sleep itself: close the lid (or let it idle-sleep), wake it later
here=${0:A:h}; mkdir -p $here/results
out=$here/results/sleep-power2-$(date +%Y%m%d-%H%M%S).txt
bat() { ioreg -rn AppleSmartBattery -w0 | awk -F' = ' -v k="\"$1\"" '$1 ~ k {gsub(/ /,"",$2); print $2; exit}'; }
rapl() { python3 -c "
import subprocess,struct
b=subprocess.run(['sysctl','-b','debug.xepm.sensors'],capture_output=True).stdout
eu,pad,ep,ei,eg=struct.unpack_from('<IIQQQ',b,80); print(eu, ep, ei, eg)"; }
cores() { sysctl -b debug.s0ix.cores > $1 2>/dev/null; }   # S0ixStandby 2cd1d252+: per-CPU core residency
c1=$(bat AppleRawCurrentCapacity); v1=$(bat Voltage); read eu p1 i1 g1 <<< "$(rapl)"; t1=$(date +%s); cs1=$(mktemp); cores $cs1
pmcA=${out%.txt}-pmc-awake.bin; sysctl -b debug.s0ix.pmc > $pmcA 2>/dev/null || rm -f $pmcA   # S0ixStandby fb95f26a+
dispA=${out%.txt}-disp-awake.bin; sysctl -b debug.s0ix.disp > $dispA 2>/dev/null || rm -f $dispA   # 79c7d8d1+
{ print "start $(date '+%F %T')  charge ${c1} mAh  ${v1} mV  $(pmset -g batt | tail -1 | cut -c1-60)"; } > $out
sync; sleep 2
fullwakes() { pmset -g log | awk '$4 == "Wake" && /Deep Idle/' | wc -l; }   # full wakes only (incl. DarkWake to FullWake)
n0=$(fullwakes)
[[ $1 == lid ]] && print "   (lid mode: waiting for you to close the lid)" >> $out || pmset sleepnow >/dev/null
# wait for the real wake (sleep entry can take > 20 s); the process is frozen while asleep
while (( $(fullwakes) <= n0 )); do sleep 2; done
sleep 15
c2=$(bat AppleRawCurrentCapacity); v2=$(bat Voltage); read eu p2 i2 g2 <<< "$(rapl)"; t2=$(date +%s); cs2=$(mktemp); cores $cs2
slept=$(pmset -g log | grep -E "	Wake .*Deep Idle|	DarkWake " | tail -1 | cut -c1-120)
python3 - "$c1" "$c2" "$v1" "$v2" "$t1" "$t2" "$eu" "$p1" "$p2" "$i1" "$i2" "$g1" "$g2" "$cs1" "$cs2" >> $out <<'PY'
import sys
import struct
c1,c2,v1,v2,t1,t2,eu,p1,p2,i1,i2,g1,g2=map(int,sys.argv[1:14])
dt=t2-t1-17
f=lambda a,b: ((b-a)&0xffffffff)/(2**eu)
wh=(c1-c2)/1000*((v1+v2)/2000)
print(f"asleep ~{dt/60:.1f} min (incl. sleep entry)")
print(f"battery: {c1-c2} mAh = {wh:.2f} Wh -> {wh/(dt/3600):.2f} W average (gauge, coarse)")
P,I,G=f(p1,p2)/dt,f(i1,i2)/dt,f(g1,g2)/dt
print(f"CPU package (RAPL): {f(p1,p2):.0f} J -> {P:.2f} W average; cores {I:.2f} W, GT {G:.2f} W, rest (uncore/SA/display) {P-I-G:.2f} W")
def load(fn):
    try: b=open(fn,'rb').read()
    except OSError: return {}
    return {i:struct.unpack_from('<IIQQQQQ',b,i*48)[1:] for i in range(len(b)//48) if struct.unpack_from('<I',b,i*48)[0]}
a,b=load(sys.argv[14]),load(sys.argv[15])
if a and b:
    print("per CPU over the whole window (incl. ~35 s awake): C0+C1 = 100 - C6 - C7; module C6 = Atom cluster")
    for c in sorted(set(a)&set(b)):
        ty,ts=a[c][0],(b[c][1]-a[c][1])
        if ts<=0: print(f"  cpu{c:2}: TSC went backwards"); continue
        pc=lambda k:(b[c][k]-a[c][k])*100/ts if a[c][k]!=2**64-1 and b[c][k]>=a[c][k] else float('nan')
        c6,c7,m6=pc(3),pc(4),pc(5)
        print(f"  cpu{c:2} {'E' if ty==0x20 else 'P' if ty==0x40 else hex(ty)}: C6 {c6:5.1f}%  C7+ {c7:5.1f}%  shallow {100-c6-c7:5.1f}%" + (f"  module-C6 {m6:5.1f}%" if ty==0x20 else ""))
else:
    print("per CPU: no debug.s0ix.cores (S0ixStandby older than 2cd1d252)")
PY
{ print "last wake: $slept"; print "  xcpm: $(sysctl -n machdep.xcpm.deep_idle_last_stats)"; ioreg -rd1 -c S0ixStandby -w0 | grep -E '"(Last C-state percent|Last wake source|Type-C D3cold at last sleep|Bus master off at last sleep|NVMe at last sleep|NVMe link config[^"]*|NVMe power state at last sleep)"' | sed 's/^ */  /'
  sleep 3; rc=$(ioreg -rd1 -c S0ixStandby -w0 | sed -n 's/.*"GT RC6 at last halt" = "\(.*\)"/\1/p')
  [[ -n $rc ]] && python3 -c "
import re,sys
m=re.search(r'\+(\d+) x 1.28 us\), TSC \+(\d+)', sys.argv[1]); f=float(sys.argv[2])
print(f'  GT RC6 during the halt: {int(m[1])*1.28e-6/(int(m[2])/f)*100:.1f} %  ({sys.argv[1]})' if m and f else '  GT RC6: '+sys.argv[1])" "$rc" "$(sysctl -n machdep.tsc.frequency)"; } >> $out
[[ -s ${pmcA:-} ]] && { print "\n#### PMC awake (before sleep) vs Deep Idle halt"; python3 $here/pmc-compare.py $pmcA; } >> $out 2>&1
dispH=${out%.txt}-disp-halt.bin; sysctl -b debug.s0ix.disphalt > $dispH 2>/dev/null || rm -f $dispH
if [[ -s ${dispA:-} && -s ${dispH:-} ]]; then
  for f in $dispA $dispH; do python3 $here/disp2txt.py $f > ${f%.bin}.txt; done
  { print "\n#### display registers: awake (before sleep) vs Deep Idle halt"; python3 $here/gpu-wm.py ${dispA%.bin}.txt ${dispH%.bin}.txt; print "\n-- raw registers that differ (offset awake halt):"; join <(tail -n +2 ${dispA%.bin}.txt) <(tail -n +2 ${dispH%.bin}.txt) | awk '$2 != $3'; } >> $out 2>&1
fi
sync; cat $out
