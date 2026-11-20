# Deep Idle findings (what has been tried)

Lenovo ThinkPad E16 Gen 3, Core 7 240H (Raptor Lake-H, display version 13 via NootedGreen spoofed as 9A49),
Modern-Standby-only firmware, macOS 26.7.1 (25G241). Two DRAM-less NVMe drives: SK Hynix HFS001TEM4X169N (macOS +
Linux, CPU root port 00:06.0) and SPCC/RTS5765DL (Windows, 00:06.2). Upstream report:
[labrouss/S0ixStandby#7](https://github.com/labrouss/S0ixStandby/issues/7).

## Where it stands

| | macOS Deep Idle (this folder) | Ubuntu 6.17 s2idle |
|---|---|---|
| Package C-state while asleep | PC3 99 % | PC10 ~95 %, S0ix 99.7 % |
| CPU package (RAPL) | 2.8 W | ~0.3 W |
| Whole system (battery gauge) | ~7.1 W (72 min, lid closed) | 0.78 W |

**The open question:** what keeps the package at PC3 (or PC2) under macOS when Linux reaches PC10 on the same
hardware? Everything below points at the NVMe drives.

## Ruled out (clean at the halt)

- **CPU cores:** all P-cores ~99 % C7, E-core module C6 ~99 % (per-CPU residency read across the halt).
- **GPU:** RC6 100 % during the halt.
- **Display:** DC9 entered for real (display core powered off) and relit after wake; with the display kept on
  instead, same package result.
- **Type-C subsystem:** D3cold through `TCOF`/`TCON`; the IOM acknowledges.
- **PCH latency (LTR):** aggregate "no requirement" at the halt.
- **PCH devices left in D0** (Wi-Fi, HDA, GbE, LPSS I2C, ISH, HECI, xHCI): tested one by one in Linux by unbinding
  their drivers before s2idle; none of them costs PC10 (`linux/pc2-hunt.sh`).
- **DMA / bus mastering**, the SOUTH_CHICKEN1 refclk workaround, the charger, DPOF (see below), NVMe link power
  config (identical in macOS and Linux: ASPM L1, L1.2 configured, LTR 3.1 ms; Linux also reaches PC10 with LTR 3.1 ms).

## NVMe: the floor

| NVMe state during sleep | macOS Deep Idle | Linux s2idle |
|---|---|---|
| D3hot (macOS default) | PC2 73–88 % | PC3 98 % |
| D0, controller shut down (CC.SHN) | **PC3 99 %** (`-s0ixnvmed0`, used now) | PC3 95 % |
| D0, controller running, deepest power state | **PC2 81–88 %** | **PC10 95 %** (`nvme.noacpi=1`) |

In macOS the "running" row was tried several ways: the kext re-initialising each controller (admin + I/O queue pair,
Set Features PS4, HMB on/off, MSI-X masked), and macOS's own controller left running (a NootedGreen hook on
`IONVMeController::HandleControllerPowerOff`, `-ngreennvmekeep`; safe, because `EnableController` resets on wake).
All gave PC2. Per drive: SK Hynix running + SPCC shut down → PC2 88 %; SK Hynix shut down + SPCC running → PC3 99 %.
In Linux, shutting down just one drive is enough to cap the package at PC3.

So a shut-down controller caps both OSes at PC3, and only a running, idle controller allows PC10, which macOS
doesn't get right yet. Ideas not yet tried:
- read the drives' real power state and the root ports' link / L1 substate status **during** the halt, in both OSes;
- Linux with a running controller forced to PS0 (APST off): does Linux then drop to PC2 too?
- the "NVMe Power States" IOReport channel IONVMeFamily publishes, to see whether APST ever reaches PS3/PS4 in macOS.

## Other findings that may help others

1. **`hwSaveNVRAM` panic** on Tahoe with the TGL framebuffer at Deep Idle entry: skipping
   `AppleIntelBaseController::hwSaveNVRAM` fixes it (NootedGreen 0003).
2. **LPS0 `_DSM` function 5 sets the IOM DPOF bit** ("all monitors off", IOM REGBAR + 0xC10040 bit 17). With the
   display kept on that's false; clearing it gave PC6 67 % once (not reproduced later). `-s0ixnodpof`.
3. **eDP relight after DC9 (display 13).** Apple's `enableDisplayEngine` restores wells, CDCLK and DBUF but never
   re-runs the eDP modeset. Replaying it from a snapshot taken at FB0 sleep (DPLL1, DPCLKA, TRANS_CLK_SEL, timings,
   M/N, `TRANS_DDI_FUNC_CTL`, DDI buffer, AUX link training at the firmware's rate/lanes, `TRANS_MSA_MISC`,
   `TRANSCONF`) brings the panel back. Without `TRANS_MSA_MISC` the sink decodes 6 bpc (garbled). Apple's
   `enableDC9` alone doesn't power the display core down on display 13; running Linux's `icl_display_core_uninit`
   sequence first makes DC9 real.
4. **TCSS D3cold.** macOS never runs the TCSS xHCI's `_PR3`; calling `\_SB.PC00.TCOF` at the sleep action and `TCON`
   at wake does it. `IOACPIPlatformDevice::evaluateObject` only takes plain names: `"D3C._OFF"` returns
   `kIOReturnBadArgument`.
5. **Instant wake:** GPE 0x6D (PCH PME shared by XDCI/LAN/HDA/Wi-Fi/xHCI) → SSDT-GPRW.
6. **Lid wake:** the lid's legacy wake pin (GPE 0x17, GPIO community pad) is disabled and locked by the BIOS
   (PADCFG writes don't stick). The EC SCI (GPE 0x6E) carries the lid events (EC queries `_Q2A` open / `_Q2B` close),
   so `LID._PRW` → GPE 0x6E works. AppleACPIPlatform rewrites `GPE0_EN` from the devices' `_PRW` after the quiesce
   actions, so the GPE has to come from ACPI, not from a register write.
7. **AC dark wakes:** on AC the EC sends `_Q24` (charge status) roughly every 56 s until charging finishes; each one
   is a dark wake that powerd holds for 45 s (`com.apple.powermanagement.acwakelinger`, not tunable;
   `pmset dwlinterval` only changes the other linger).
8. **Docked sleep bug** (see README): reproducible with one docked Deep Idle cycle; Type-C PCI state and ports look
   identical in the stuck state; not SMIs, not dark wakes.

## Measuring

`tools/sleep-power.sh` (needs the diagnostics boot args) records battery drain, RAPL (NootedGreen's
`debug.xepm.sensors`), per-CPU residency (`debug.s0ix.cores`), and compares the PMC page and display registers awake
vs during the halt (`pmc-compare.py`, `disp2txt.py`, `gpu-wm.py`). Results go to `tools/results/` (ignored by git).
Battery-gauge readings under ~30 minutes are coarse.
