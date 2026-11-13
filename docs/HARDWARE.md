# Hardware notes and how each part is handled

| Part | ID | Handling |
|---|---|---|
| iGPU | `8086:A7AB` rev 4, 64 EU / 6 L3 | spoofed `9A49` (`AAPL,ig-platform-id 0000499A`), NootedGreen + Apple TGL 16.0.32 kexts |
| HDA controller | `8086:51CA` (Raptor Lake-P cAVS) | AppleALC controller patch |
| Codec | Synaptics/Conexant SN6140 `0x14F11F87`, rev `0x100100` | AppleALC entry derived from CX8070 (`0x14F11F86`, same Linux driver): layouts 15/21 retagged to codec `0x14F11F87`, pin configs copied, AppleHDA codec-table patch `871ff114`. Without the retag, AppleHDA finds no path map and stops after 5 s. Widget dump: `src/applealc/sn6140-dump.txt` |
| Wi-Fi | AX211 CNVi `8086:51F1` | ForbiddenItlwm 0.3.1-test1 (AirportItlwm-Tahoe fork with AWDL for AirDrop; [AIRDROP.md](AIRDROP.md)); AirportItlwm kept as a disabled fallback |
| Bluetooth | `8087:0033` | IntelBluetoothFirmware 2.5.2 (lshbluesky fork: newer AX211 firmware with *LE Read Buffer Size v2*, which Sequoia/Tahoe's bluetoothd requires; power state patched to `kIOPMLowPower`) + BlueToolFixup + BTLEAdvFixup (LE advertising for AirDrop; IntelBTPatcher disabled, same hook) + BTIdle (USB idle suspend: without it the controller is polled every 1 ms and the CPU package can't go below PC3), NVRAM `bluetoothExternalDongleFailed`=`00`, `bluetoothInternalControllerInfo`=14×`00` |
| Ethernet | I219-V `8086:1A1F` | IntelMausi (TSO4/TSO6/CSO6 off: long downloads drop otherwise) |
| xHCI | `8086:51ED` | `XHCI-unsupported-600.kext` + USBToolBox `UTBMap.kext` (9 ports) |
| USB-C display | Type-C port 1 = DDI index 3 (Dekel PHY, FIA 1) | DisplayPort alt mode via this EFI's NootedGreen (`-ngreentc1`); with a dock using pin assignment D: 2 lanes at HBR2 + USB 3 ([DISPLAYS.md](DISPLAYS.md)) |
| Touchpad | I2C0 `8086:51E8`, `TPD0`, GPIO pin 177 | VoodooI2C 2.9.1 with `0x51e88086&0xFFFCFFFF` added to `VoodooI2CPCILakeController`'s `IOPCIMatch`; VoodooGPIO built with the Tiger Lake-LP `start` fix (`src/voodoogpio`); `SSDT-XOSI` + `_OSI→XOSI` so `TPD0._CRS` returns its I2C address |
| I2C2 `8086:51EA` | `TPL1` (`PRT0818`, 0x24) | appears as a touchscreen; unclear what it is on the E16; harmless |
| Keyboard / TrackPoint | PS/2 | VoodooPS2 2.3.7 (calculator key `e021` → F16) |
| CPU | Core 7 240H | `SSDT-PLUG-ALT`, `AppleXcpmCfgLock`, `ProvideCurrentCpuInfo`, NootedGreen XE-PM (`-ngreenpm`, `ngreenpmepp=96`), `lilucpu=17` (so SMCProcessor reports power and temperatures) |
| NVMe (both drives) | root ports `00:06.0`, `00:06.2` | NVMeFix `-nvmefaspm` (ASPM L1) + DeviceProperties `pci-l1ss-enable` (L1.1/L1.2) and `pci-max-latency` (LTR): without the L1 substates the CPU package can't go below PC3, as in Linux |
| ThinkPad EC (`HKEY` LEN0268) | | YogaSMC 1.5.3: F4/F7–F12 hotkeys, mic-mute LED, keyboard backlight, fan, sensors |
| RTC | | `SSDT-AWAC` |
| Backlight | PWM, period 96000 | `SSDT-PNLF` + `ngreenblmax=17741` |
| Brightness keys | `_Q14/_Q15` → `Notify(GFX0.DD1F, 0x86/0x87)` | BrightnessKeys |

## OpenCore notes

- `SecureBootModel` **Disabled** (Default makes the installer loop with `img4_firmware_execute failed`).
- `SetupVirtualMap` **on** (off hangs at `EXITBS:START`).
- `ScanPolicy` 17760515 and `ShowPicker` off in `config.plist` assume rEFInd or the firmware menu
  handles other OSes (see [DUAL-BOOT.md](DUAL-BOOT.md)); hold **Esc** at OpenCore start for its
  menu (Recovery, Reset NVRAM via Space). `config-install.plist` shows the picker and scans everything.
- `Misc/Debug Target` 0. Set `0x41` for file logging when debugging.
- Debug output from Lilu plugins: DEBUG builds plus `-liludbg -alcdbg liludump=90` write
  `/var/log/Lilu_*.txt` (read it with `grep -a`). The kernel message buffer is too small
  (itlwm/AirportItlwm log a lot).
