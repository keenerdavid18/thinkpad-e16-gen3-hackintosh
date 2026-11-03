# Post-install

## SMBIOS and iMessage

- SMBIOS: **`MacBookPro16,2`** (13" 2020, 4 TB3; Intel iGPU-only laptop, supported by Tahoe).
  It's also what the reference graphics project uses.
- Generate the serial and MLB with `macserial -m MacBookPro16,2 -n 5` (OpenCore 1.0.8
  `Utilities/macserial`), and the `SystemUUID` with `uuidgen`.
- **Check every candidate serial at checkcoverage.apple.com.** Use one that comes back
  "Please enter a valid serial number". macserial can produce serials of real Macs. The first
  one generated for this build belonged to a real 2020 MacBook Pro.
- `ROM` = the I219-V Ethernet MAC (6 bytes). The Ethernet port is `en0` (built-in, primary),
  which iMessage/FaceTime want. AirportItlwm keeps Wi-Fi on `en2`.
- Sign in to the App Store first, then Messages and FaceTime. **Never change these values
  after signing in.**
- With iCloud signed in, macOS may turn on **FileVault**. The boot then shows the unlock screen
  first, then a second Apple logo with a progress bar. That's normal.

## Power, sleep and the lid

System sleep doesn't work on this firmware (Modern Standby / S0ix only; macOS never really
sleeps and the panel isn't relit on wake). Disable it and use display sleep:

```zsh
sudo pmset -a sleep 0 disablesleep 1 hibernatemode 0 standby 0 powernap 0 proximitywake 0
sudo pmset -b displaysleep 3
sudo pmset -c displaysleep 10
```

Closing the lid then turns the display off and the Mac keeps running. **Shut down before
putting it in a bag.**

CPU: `-ngreenpm` gives full turbo. Under sustained load (e.g. Spotlight indexing everything
after the first iCloud sync) the fan will run hard for a while. To bias towards efficiency,
`sudo sysctl -w debug.xepm.epp=64` lasts until reboot; boot-arg `ngreenpmepp=64` makes it
permanent. If you hear coil whine at idle: `sudo sysctl -w debug.xepm.cst=0` (boot-arg
`ngreenpmcst=0`).

## Wi-Fi

- Native Wi-Fi menu via AirportItlwm-Tahoe. WPA2 and WPA2/WPA3 transition networks only.
  WPA3-only networks and mandatory PMF don't work.
- Wi-Fi uses a random ("private") MAC by default. Turn it off per network if your router or
  DNS server needs a stable address.
- **Pi-hole / filtering DNS users:**
  - If Wi-Fi connects but nothing resolves, iCloud **Private Relay** is probably on and your
    DNS blocks `mask.icloud.com`. Turn off Private Relay, or "Limit IP address tracking" for
    that network.
  - If Location Services never finds you, allowlist **`gs-loc.apple.com`** (Apple's Wi-Fi
    location lookup; it's on some blocklists).
- Location Services need an AirportItlwm build with the connected-scan fix (laobamac
  `7204c69` or newer, as shipped here). Older builds return no networks to `locationd`.
- Fallback: `itlwm.kext` + HeliPort (in the EFI, `MaxKernel 24.99.99`). To use it on Tahoe,
  swap the Min/MaxKernel of itlwm and AirportItlwm. Never load both.

## Audio

- Speakers and the headphone jack use the custom AppleALC (SN6140, `layout-id` 21) plus SimpleHDA.
- If the jack misbehaves, try `layout-id` 15 (`DeviceProperties` → `PciRoot(0x0)/Pci(0x1f,0x3)`).
- `alc-verb` (built from AppleALC's source, `alcverbs=1`) can talk to the codec;
  `src/applealc/dump-codec.py` dumps its widget graph.

## Keyboard and pointing devices

- macOS key positions: **Alt = Command, Windows key = Option.**
- F1–F3 (mute/volume) work. PrtSc arrives as **F13**; bind it under Keyboard Shortcuts →
  Screenshots. Fn+F5/F6 change brightness. Fn+Space is the keyboard backlight (handled by the EC).
- The calculator key is remapped to **F16** (VoodooPS2 `Custom ADB Map` `e021=6a`). Bind it with
  a Shortcuts-app keyboard shortcut. This mapping hasn't been verified on the hardware.
- **System Settings → Trackpad** controls the touchpad; **→ Mouse** controls the TrackPoint.

## Chrome

If Chrome flickers, e.g. when viewing PDFs, open `chrome://flags/#skia-graphite`, set it to
**Disabled** and relaunch. Fallback: Settings → System → turn off graphics acceleration.

## Never update

Keep automatic macOS updates off and ignore update offers. The graphics stack is tied to 25G241.
