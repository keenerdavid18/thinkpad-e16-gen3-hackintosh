# ThinkPad E16 Gen 3 (Intel) – macOS Tahoe Hackintosh

An OpenCore EFI and guide for running **macOS Tahoe 26.7.1 (25G241) with Iris Xe graphics
acceleration** on a Lenovo ThinkPad E16 Gen 3 (Intel Core 7 240H). The graphics stack is
[JulioNectar's NootedGreen fork](https://github.com/JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe),
which only works on that exact macOS build. Don't update macOS past 25G241.

> This is a working build for one specific laptop, shared as-is. Use it at your own risk and
> back up everything first. Not affiliated with or endorsed by Apple, Lenovo or Intel.

## Hardware

| Component | Model | ID |
|---|---|---|
| CPU | Intel Core 7 240H (Raptor Lake-H, 6P+4E, 16 threads) | |
| iGPU | Intel Graphics, 64 EU / 6 L3 banks | `8086:A7AB` rev 4 (spoofed as `9A49`) |
| Display | 16" 1920×1200 (NV160WUM-K03), PWM backlight | |
| Audio | Synaptics/Conexant **SN6140** codec on `8086:51CA` | codec `0x14F11F87` |
| Wi-Fi / Bluetooth | Intel AX211 (CNVi) | `8086:51F1` / USB `8087:0033` |
| Ethernet | Intel I219-V | `8086:1A1F` |
| Touchpad | I2C HID (`TPD0` on I2C0, `8086:51E8`), GPIO interrupt | |
| Keyboard / TrackPoint | PS/2 | |
| USB | PCH xHCI `8086:51ED` | |

See [docs/HARDWARE.md](docs/HARDWARE.md) for details.

## Status

| Works | Notes |
|---|---|
| Graphics acceleration (Metal 2), video playback | NootedGreen; see [docs/GRAPHICS.md](docs/GRAPHICS.md) |
| Brightness (slider + Fn+F5/F6), display sleep, lid → display off | `ngreenblmax=17741` for the full range |
| Internal speakers, headphone jack | custom AppleALC (SN6140) + SimpleHDA (AppleHDA was removed in Tahoe) |
| Wi-Fi (native menu, Wi-Fi 6 rates), Location Services | AirportItlwm-Tahoe `7204c69`; WPA2 and WPA2/WPA3 mixed only |
| Bluetooth | IntelBluetoothFirmware/IntelBTPatcher 2.5.2 (lshbluesky fork) |
| Ethernet | IntelMausi, TSO/CSO6 offloads off |
| Touchpad (gestures, GPIO interrupts), keyboard, TrackPoint | VoodooI2C + patched VoodooGPIO, VoodooPS2 |
| iMessage, FaceTime, iCloud, App Store | with your own SMBIOS serials |
| CPU turbo + deep idle | NootedGreen XE-PM (`-ngreenpm`) |
| USB, NVMe, battery, keyboard backlight (Fn+Space) | |

| Doesn't work | |
|---|---|
| **System sleep** | the firmware is Modern Standby only; sleep is disabled and display sleep is used instead |
| AirDrop / AWDL / Sidecar | Intel Wi-Fi can't do AWDL; would need a Broadcom card |
| Internal microphones | DMICs behind the Intel DSP; the headset mic works |
| ThinkPad hotkeys F4 (mic mute), F7–F12 | EC/HKEY events, no driver yet; F1–F3 and PrtSc (= F13) work |
| WPA3-only Wi-Fi networks | AirportItlwm limitation |

More in [docs/KNOWN-ISSUES.md](docs/KNOWN-ISSUES.md).

## Quick start

1. **BIOS:** Secure Boot **off**; storage in **AHCI/NVMe** mode (not RAID/VMD).
2. **Get the EFI ready:**
   ```zsh
   git clone <this repo> && cd thinkpad-e16-gen3-hackintosh
   zsh tools/fetch-simplehda.sh        # not shipped here (contains Apple code)
   ```
3. **Generate your own SMBIOS** (`MacBookPro16,2`) with `macserial` and put it in **both**
   `EFI/OC/config.plist` and `EFI/OC/config-install.plist`
   ([docs/POST-INSTALL.md](docs/POST-INSTALL.md#smbios-and-imessage)). Never reuse someone else's serial.
4. **Install macOS** with `config-install.plist` (no acceleration), then **add graphics** with
   `config.plist` and the NootedGreen user-space install: [docs/INSTALL.md](docs/INSTALL.md).
5. **Post-install:** power settings, Wi-Fi, iMessage, tips: [docs/POST-INSTALL.md](docs/POST-INSTALL.md).
6. **Optional:** rEFInd as the single boot menu for macOS + Windows + Linux:
   [docs/DUAL-BOOT.md](docs/DUAL-BOOT.md).

## Repository layout

| Path | Contents |
|---|---|
| `EFI/BOOT`, `EFI/OC` | OpenCore 1.0.8 EFI: `config.plist` (accelerated, everyday) and `config-install.plist` (installing/upgrading) |
| `acpi/` | sources of the SSDTs in `EFI/OC/ACPI` |
| `src/applealc/` | builds AppleALC 1.9.8 with an **SN6140** entry (not in upstream AppleALC) |
| `src/voodoogpio/` | builds VoodooGPIO with the Tiger Lake-LP `start` fix this machine's GPIO needs |
| `src/intelbluetooth/` | builds IntelBluetoothFirmware/IntelBTPatcher 2.5.2 (lshbluesky fork, newer AX211 firmware) |
| `refind/` | Apple-logo icon and its generator, for the optional rEFInd menu |
| `tools/` | `fetch-simplehda.sh` |

All build scripts use only the Xcode **Command Line Tools** (no full Xcode).

## Credits and licenses

Built on the work of acidanthera (OpenCore, Lilu, AppleALC, WhateverGreen, VirtualSMC, …),
StezzaPilot/sgiammori (NootedGreen), JulioNectar (the Tahoe Iris Xe stack this build follows),
OpenIntelWireless and laobamac (itlwm/AirportItlwm), lshbluesky (IntelBluetoothFirmware fork),
VoodooI2C/VoodooPS2, USBToolBox and laobamac (SimpleHDA). Third-party components keep their own
licenses: see [THIRD-PARTY.md](THIRD-PARTY.md). This repo's own scripts and docs are MIT
([LICENSE](LICENSE)).
