# Hardware notes and how each part is handled

| Part | ID | Handling |
|---|---|---|
| iGPU | `8086:A7AB` rev 4, 64 EU / 6 L3 | spoofed `9A49` (`AAPL,ig-platform-id 0000499A`), NootedGreen + Apple TGL 16.0.32 kexts |
| HDA controller | `8086:51CA` (Raptor Lake-P cAVS) | AppleALC controller patch |
| Codec | Synaptics/Conexant SN6140 `0x14F11F87`, rev `0x100100` | AppleALC entry derived from CX8070 (`0x14F11F86`, same Linux driver): layouts 15/21 retagged to codec `0x14F11F87`, pin configs copied, AppleHDA codec-table patch `871ff114`. Without the retag, AppleHDA finds no path map and stops after 5 s. Widget dump: `src/applealc/sn6140-dump.txt` |
| Wi-Fi | AX211 CNVi `8086:51F1` | AirportItlwm-Tahoe (laobamac) |
| Bluetooth | `8087:0033` | IntelBluetoothFirmware + IntelBTPatcher 2.5.2 (lshbluesky fork: newer AX211 firmware with *LE Read Buffer Size v2*, which Sequoia/Tahoe's bluetoothd requires) + BlueToolFixup, NVRAM `bluetoothExternalDongleFailed`=`00`, `bluetoothInternalControllerInfo`=14×`00` |
| Ethernet | I219-V `8086:1A1F` | IntelMausi (TSO4/TSO6/CSO6 off: long downloads drop otherwise) |
| xHCI | `8086:51ED` | `XHCI-unsupported-600.kext` + USBToolBox `UTBMap.kext` (9 ports) |
| Touchpad | I2C0 `8086:51E8`, `TPD0`, GPIO pin 177 | VoodooI2C 2.9.1 with `0x51e88086&0xFFFCFFFF` added to `VoodooI2CPCILakeController`'s `IOPCIMatch`; VoodooGPIO built with the Tiger Lake-LP `start` fix (`src/voodoogpio`); `SSDT-XOSI` + `_OSI→XOSI` so `TPD0._CRS` returns its I2C address |
| I2C2 `8086:51EA` | `TPL1` (`PRT0818`, 0x24) | appears as a touchscreen; unclear what it is on the E16; harmless |
| Keyboard / TrackPoint | PS/2 | VoodooPS2 2.3.7 (calculator key `e021` → F16) |
| CPU | Core 7 240H | `SSDT-PLUG-ALT`, `AppleXcpmCfgLock`, `ProvideCurrentCpuInfo`, NootedGreen XE-PM (`-ngreenpm`) |
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
