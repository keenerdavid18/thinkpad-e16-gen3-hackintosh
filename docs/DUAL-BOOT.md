# Optional: rEFInd as the only boot menu (macOS + Windows + Linux)

This keeps OpenCore away from Windows and Linux, so no SMBIOS or ACPI changes reach them and
one bad OpenCore config can't break all three OSes. rEFInd shows **Apple · Ubuntu · Windows**.
Picking the Apple logo starts OpenCore, which boots macOS directly with its own picker hidden.

1. Install rEFInd on the ESP next to `EFI/OC` (e.g. from Linux with `refind-install`). Never
   overwrite another OS's `EFI/BOOT`.
2. Copy `refind/os_apple.png` to `EFI/refind/icons/` (a gray Apple logo; `refind/appleicon.swift`
   regenerates it: `swiftc -O appleicon.swift -o appleicon && ./appleicon 256 os_apple.png`).
3. In `EFI/refind/refind.conf`:
   ```
   scanfor manual,internal,external,optical
   dont_scan_files +,<ESP-partition-GUID>:/EFI/OC/OpenCore.efi,boot.efi

   menuentry "macOS" {
       icon   /EFI/refind/icons/os_apple.png
       volume <ESP-partition-GUID>
       loader /EFI/OC/OpenCore.efi
       graphics on
   }
   ```
   - `scanfor manual,…` puts the macOS entry first.
   - `dont_scan_files` hides the generic OpenCore entry, and `boot.efi` stops rEFInd from
     offering macOS directly (that would skip OpenCore).
   - `graphics on` removes rEFInd's "Booting OS / Starting OpenCore.efi" text screen.
   - The ESP GUID is the partition's UUID: `diskutil info disk0s1 | grep "Partition UUID"` or
     `lsblk -o NAME,PARTUUID`.
4. The shipped `config.plist` already has `ShowPicker` false, `PollAppleHotKeys` true,
   `HideAuxiliary` true and `ScanPolicy` 17760515 (APFS only), so OpenCore only sees macOS. Hold
   **Esc** right after picking the Apple logo to get OpenCore's menu.
5. Keep a USB stick with this EFI and `ShowPicker` true as a fallback (F12 at power-on).

Linux/Windows updates can put themselves first in the firmware boot order. If the laptop skips
rEFInd, use F12 or `efibootmgr -o` from Linux.
