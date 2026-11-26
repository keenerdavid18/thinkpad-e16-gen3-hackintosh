# Experimental: system sleep (Deep Idle / S0ix)

> **Experimental. Test from a USB-stick EFI only, never from your internal EFI.** It works on the author's laptop,
> but sleep power is still far above Linux, and there are known traps (see [Known problems](#known-problems)).
> Help is very welcome: [FINDINGS.md](FINDINGS.md) lists what has been tried and what is still open.

This laptop's firmware is Modern Standby only (no `_S3`), so the main EFI keeps system sleep off. This folder makes
macOS sleep in **Deep Idle**, Apple's S0 sleep (sleep type 7), using
[labrouss/S0ixStandby](https://github.com/labrouss/S0ixStandby) plus fixes for this machine.

## Status (macOS 26.7.1 25G241, ThinkPad E16 Gen 3, Core 7 240H)

| | |
|---|---|
| Sleep from the Apple menu, `pmset sleepnow`, **closing the lid** | works |
| Wake by **lid open**, **power button**, **keyboard** (lid open), RTC/maintenance | works |
| Internal display after wake (display core really powered off, DC9) | works (XE-EDPWAKE replays the eDP modeset) |
| Wi-Fi, Bluetooth, USB-A, USB-C (without a dock), audio, touchpad after wake | back |
| Long runs | 8 h 40 min overnight on AC (91 sleep/wake cycles), clean wake |
| Sleep power on battery (72 min, lid closed) | **~7.1 W** system (battery gauge), **2.8 W** CPU package (RAPL) |
| Ubuntu 6.17 s2idle on the same laptop, for comparison | **0.78 W** system, PC10 / S0ix 99.7 % |

The CPU package stops at **PC3** (99 %): the NVMe drives set that floor under macOS. See [FINDINGS.md](FINDINGS.md).

## What's in here

| Path | What it does |
|---|---|
| `EFI/OC/Kexts/S0ixStandby.kext` | labrouss/S0ixStandby 0.5.4 + this machine's patches ([patches/s0ixstandby-e16.diff](patches/s0ixstandby-e16.diff)): LPS0 `_DSM` around Deep Idle, power-button / keyboard wake, Type-C D3cold, NVMe handling, diagnostics, and the HDA clock-gating and HPET comparator fixes from upstream 0.5.13 (brandonedley) |
| `EFI/OC/Kexts/NootedGreen.kext` | **replaces** the main EFI's NootedGreen: same build plus [`src/nootedgreen/0003-deep-idle-sleep.diff`](../../src/nootedgreen/0003-deep-idle-sleep.diff) (no `hwSaveNVRAM` panic, FB0 sleep/wake bookkeeping, eDP relight after DC9, a fix for a `xeLrcaRepair` panic on display-mode changes) |
| `EFI/OC/ACPI/SSDT-DEEPIDLE.aml` | `\_SB.LPS0` + Deep Idle support (from the S0ixStandby release) |
| `EFI/OC/ACPI/SSDT-GPRW.aml` + ACPI patch `GPRW→XPRW` | stops the shared PCH PME GPE 0x6D (XDCI, LAN, audio, Wi-Fi, xHCI) from waking Deep Idle instantly (Dortania) |
| `EFI/OC/ACPI/SSDT-LIDWAKE.aml` + ACPI patch `LID._PRW→XPRW` | the lid's own wake pin (GPE 0x17) is locked off by the BIOS; under macOS the lid's `_PRW` names the EC SCI GPE 0x6E instead. **Battery only** |
| `EFI/OC/ACPI/SSDT-LIDWAKE2.aml` | the same on AC as well (used by `config-sleep-ac.plist`) |
| `EFI/OC/config-sleep-battery.plist` | main `config.plist` + the pieces above + sleep boot args (tested as "Yl") |
| `EFI/OC/config-sleep-ac.plist` | the same with `SSDT-LIDWAKE2`, `-s0ixeclog -s0ixacnoec` (tested as "Yr", the overnight run) |
| `acpi/` | `.dsl` sources; `make-ssdt-lidwake.py` builds both LIDWAKE tables |
| `tools/sleep-power.sh` | one sleep, measured: battery drain, RAPL package/core/GT power, per-CPU residency, PMC and display registers awake vs during the halt |
| `tools/nvme-modes.sh` | a batch of RTC-woken sleeps over the NVMe handling modes (`debug.s0ix.nvme`), with the NVMe root-port link state at the halt (`nvcfg.py`) |
| `tools/skip-steps.sh` | one RTC-woken sleep per `debug.s0ix.skip` value: skips the LPS0 `_DSM`, TCSS D3cold, the refclk workaround or wake arming for that sleep |
| `tools/pmtel.c` | reads the PUNIT package C-state counters (`pmtelemetry_cpu` IOReport group) or any other IOReport group; build: `clang -O2 -o pmtel pmtel.c -framework CoreFoundation -lIOReport`. Method from brandonedley (S0ixStandby #7) |
| `tools/halt-diff.py`, `tools/pmtel-diff.py` | turn two `pmtel` snapshots (before / after a sleep) into per-counter rates during the halt, with the awake rate subtracted |
| `tools/irqregs.py` | GPU / display / PCH-display interrupt registers awake vs at the halt (`sleep-power.sh` runs it) |
| `linux/` | the Ubuntu scripts used to compare: `s0ix-test.sh`, `pc2-hunt.sh` (which device left in D0 blocks PC10), `nvme-state-test.sh`, `nvme-live-test.sh` |

### Sleep boot args (in both configs)

| Boot arg | From | Effect |
|---|---|---|
| `-ngreenfb0pm` | NootedGreen 0003 | Apple's FB0 `prepareToEnterSleep/ExitSleep` on real power-state changes, so the GPU restarts after wake |
| `-ngreenedpwake` | NootedGreen 0003 | eDP teardown before DC9, modeset replay after wake (without it: backlight on, black panel) |
| `-s0ixpwrbtn`, `-s0ixkbdwake` | S0ixStandby patch | power-button and internal-keyboard wake during the halt |
| `-s0ixnodpof` | S0ixStandby patch | clears the IOM "all monitors off" bit the LPS0 `_DSM` sets |
| `-s0ixtcssd3` | S0ixStandby patch | Type-C subsystem to D3cold (`TCOF`/`TCON`); USB-C works after wake |
| `-s0ixnvmed0` | S0ixStandby patch | NVMe back to D0 (controller shut down) for the halt: PC3 99 % instead of PC2 |
| `-s0ixhdapm` | S0ixStandby (upstream 0.5.13) | restores the HDA controller's clock gating (`CGCTL` 0 → `0x003f01ff`) during the halt: AC ring oscillator off, ~1 W less package power in one run; audio works after wake |
| `-s0ixhpetfix` | S0ixStandby (upstream 0.5.13) | moves the stopped HPET's comparators off the counter value; needed for SLP_S0 once the package reaches PC10 (not reached on the E16 yet) |
| `-s0ixrefclk` | S0ixStandby patch | SOUTH_CHICKEN1 refclk workaround; no measurable effect, kept because it was tested that way |
| `-s0ixacnoec` | S0ixStandby patch | AC config only: on AC, re-points the lid wake away from the EC so charge events stop dark-waking the Mac (lid-open wake on AC is given up). **The fixed build here is untested on AC** |
| `-s0ixpmcdump`, `-ngreenedpdiag`, `-s0ixeclog` | | diagnostics only (ioreg dumps used by `sleep-power.sh`); safe to remove |

## Try it (USB stick)

You need a USB stick that already boots this repo's main EFI with **your** SMBIOS.

1. Copy `EFI/OC/ACPI/*.aml` and both kexts from this folder into the stick's `EFI/OC/ACPI` and `EFI/OC/Kexts`
   (`NootedGreen.kext` replaces the one there).
2. Take `config-sleep-battery.plist`, copy your SMBIOS fields (`PlatformInfo → Generic`) into it, and save it as the
   stick's `EFI/OC/config.plist`.
3. Boot from the stick and check:
   ```zsh
   ioreg -rd1 -c IOPMrootDomain | grep IOPMDeepIdleSupported   # = Yes
   kextstat | grep S0ixStandby
   ```
4. Allow sleep (manual sleep only; no idle sleep yet):
   ```zsh
   sudo pmset -a disablesleep 0 sleep 0 hibernatemode 0 standby 0 powernap 0 tcpkeepalive 0 proximitywake 0
   ```
5. Sleep with the Apple menu or by closing the lid; wake with the lid, a key or the power button.
   To measure: `zsh experimental/sleep/tools/sleep-power.sh lid`, close the lid, wait 20+ min, open it.
6. **Before booting your normal EFI again**, turn sleep back off (the setting is Mac-wide, not per EFI):
   ```zsh
   sudo pmset -a sleep 0 disablesleep 1 hibernatemode 0 standby 0 powernap 0 proximitywake 0
   ```

## Known problems

- **Never sleep with the USB-C dock attached.** After a docked sleep, unplugging the dock leaves the CPU package stuck
  at PC2 (~12–15 W idle, fan up) and the USB-C port's data side dead until a reboot. Linux s2idle doesn't do this; the
  cause isn't found.
- **On AC the Mac dark-wakes about once a minute while charging** (the EC raises GPE 0x6E for charge events; powerd
  then holds every dark wake ~45 s). It stops once the battery is full. `-s0ixacnoec` is meant to stop it.
- **Sleep power ~7 W instead of <1 W** (see above): the package stays at PC3 and ~4 W go outside the package.
- The power button does nothing during a dark wake.
- No touchpad wake, no Handoff/Bluetooth wake filtering when docked, no hibernation fallback, no automatic idle sleep
  setup yet.
- The panel can show the previous frame for a moment at wake.

## Credits

[labrouss/S0ixStandby](https://github.com/labrouss/S0ixStandby) (BSD-3-Clause) is the base of all of this.
SSDT-GPRW is Dortania's. JulioNectar's NootedGreen issues and b00t0x/WhateverXe's issue tracker (Raptor Lake sleep,
RC6 and trackpad-wake recipes) were references.
