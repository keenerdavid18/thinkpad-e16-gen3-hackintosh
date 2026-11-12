# Installation

The tested path: install macOS with `config-install.plist` (no graphics acceleration), get
macOS on **26.7.1 build 25G241**, then switch to `config.plist` and install the NootedGreen
user-space stack. The author's machine was installed with Sequoia 15.8.2 first and upgraded in
place to 25G241; installing 25G241 directly with `config-install.plist` should work the same
way but wasn't tested here.

## 1. BIOS (F1 at power-on)

- **Secure Boot: off.**
- **Storage: AHCI/NVMe** (not RAID/Intel RST/VMD).
- VT-d can stay on (`DisableIoMapper` is set).
- Nothing else is required. There's no CFG Lock toggle; `AppleXcpmCfgLock` handles that.

## 2. Prepare the EFI

1. Clone this repo onto a Mac or a Linux machine.
2. `zsh tools/fetch-simplehda.sh` puts SimpleHDA into `EFI/OC/Kexts`. It needs a Mac or zsh,
   or do the same steps by hand (the URL and SHA-256 are in the script).
3. **SMBIOS:** generate a `MacBookPro16,2` serial and MLB with `macserial` from the
   [OpenCore 1.0.8 release](https://github.com/acidanthera/OpenCorePkg/releases/tag/1.0.8)
   (`Utilities/macserial`), and a `SystemUUID` with `uuidgen`. Set `ROM` to your Ethernet MAC
   (6 bytes). Put them under `PlatformInfo > Generic` in **both** config files. **Check the
   serial at checkcoverage.apple.com.** It must come back "not valid"; if it shows a real Mac,
   generate another. See [POST-INSTALL.md](POST-INSTALL.md#smbios-and-imessage).
4. For installing: **copy `config-install.plist` over `config.plist`** on the USB stick (keep
   the accelerated one aside for later).

## 3. Installer USB

Get the **26.7.1 (25G241)** full installer from Apple's catalog on any Mac:

```zsh
softwareupdate --list-full-installers
softwareupdate --fetch-full-installer --full-installer-version 26.7.1
```

Keep a copy of `Install macOS Tahoe.app`. Apple removes old builds from the catalog over time,
and the graphics stack only works on this build. Make a USB installer (≥ 32 GB) with
`createinstallmedia`, and put this repo's `EFI` folder on the stick's EFI partition. Without a
Mac, OpenCore's `macrecovery` can fetch a recovery image instead, but recovery downloads
whatever build Apple currently offers.

## 4. Install

1. F12 at power-on → the USB stick → in OpenCore's menu pick the installer.
2. Install onto an APFS volume. The installer reboots several times; each time choose
   **macOS Installer** in OpenCore until it's gone, then your macOS volume.
3. Finish setup. **Don't sign in to your Apple ID yet** if you haven't verified your serial.
4. **Turn off automatic macOS updates** (System Settings → General → Software Update →
   Automatic updates: off). Never install anything past 25G241.
5. Copy the EFI to the internal ESP (`sudo diskutil mount disk0s1`; check the number with
   `diskutil list`) so you can boot without the stick.

At this point you have audio, Wi-Fi, Bluetooth, touchpad and keyboard, but no acceleration.

## 5. Graphics acceleration

See [GRAPHICS.md](GRAPHICS.md). In short: switch the ESP to the accelerated `config.plist`,
reboot (so the GPU is spoofed as Tiger Lake), run the reference project's `install.sh`, and
reboot again.

## 6. Afterwards

[POST-INSTALL.md](POST-INSTALL.md): power and sleep settings, idle power, Wi-Fi notes, iMessage,
ThinkPad hotkeys (YogaSMCNC), Chrome. `config.plist` also turns on AirDrop: [AIRDROP.md](AIRDROP.md).
