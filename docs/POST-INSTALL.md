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
  which iMessage/FaceTime want. The Wi-Fi driver keeps Wi-Fi on `en2`.
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
after the first iCloud sync) the fan will run hard for a while. `config.plist` sets
`ngreenpmepp=96` (energy/performance preference: a bit more towards efficiency, ~1.5 W less at
idle; `sudo sysctl -w debug.xepm.epp=…` changes it until reboot). If you hear coil whine at idle:
`sudo sysctl -w debug.xepm.cst=0` (boot-arg `ngreenpmcst=0`).

CPU scheduling: the CPU is hybrid (6 P-cores with HT + 4 E-cores). Without help macOS sees 16
identical cores and moves threads between fast and slow ones every second. CpuTopologyRebuild
(in `EFI/OC/Kexts`, enabled in `config.plist`) fixes that: Geekbench 7 went from about 960 / 5200
to about 1470 / 6900 (single / multi). `sysctl hw.physicalcpu` shows 6 when it's active. Its
effect on a single tight synthetic loop looks negative (a lone loop sits on an E-core); judge it
with real workloads.

## Idle power

Measured with the CPU's own counters (package C-state residency and RAPL energy, using
[hackintosh-power-tools](https://github.com/keenerdavid18/hackintosh-power-tools)): the idle CPU
package went from ~6 W to ~2.5–3 W. Already in `config.plist`:

- `ngreenpmepp=96` (see above).
- **NVMe L1 substates:** NVMeFix's `-nvmefaspm` only enables ASPM L1. The DeviceProperties
  `pci-l1ss-enable` / `pci-max-latency` on both NVMe drives and their root ports add L1.1/L1.2 and
  LTR. Without them the package can't go below PC3 (Linux shows the same).
- **BTIdle** + the IntelBluetoothFirmware power-state patch: lets the Bluetooth controller
  idle-suspend. Without it, Bluetooth being on caps the package at PC3 (~1.6 W more). Check
  with `ioreg -r -c BTIdle -d1 | grep btidle-status`. Turn it off with
  `sudo sysctl debug.btidle.ms=0` if Bluetooth misbehaves.

Optional:

- **Timer coalescing** (`tools/timer-coalesce`, a LaunchDaemon): wider kernel timer windows mean
  fewer CPU wake-ups, ~0.7 W less at idle. Timers may fire up to 10 ms late; see its README.
- **Unplug Ethernet** when you don't need it. A linked I219-V keeps the package at PC3.
- **Keyboard backlight off** (Fn+Space) saves ~2 W of whole-laptop power.

## Smoother animations

Turn on **System Settings → Accessibility → Display → Reduce transparency**. Tahoe's Liquid
Glass adds blur layers to every frame. On this stack the bottleneck is handing frames to the
GPU (CPU/driver side, host scheduler without GuC), not GPU power: during the "click wallpaper to
reveal desktop" slide the GPU drew under 0.5 W while WindowServer spiked to 20–50% CPU. With
Reduce transparency that animation is much smoother. **Reduce motion** (fades instead of
slides) is the next step if anything still stutters.

## Background GPU work

The GPU still hangs now and then (see [KNOWN-ISSUES.md](KNOWN-ISSUES.md)). Usually the driver
recovers, but heavy background GPU work while nobody is using the Mac can end in a frozen black
screen and a restart. The main source is Photos' library analysis after the first iCloud sync.
Turning it off stops People/Pets grouping, content search ("dog", "beach"), Memories and the
Duplicates album from updating; viewing, editing and iCloud Photos sync keep working:

```zsh
launchctl disable gui/$(id -u)/com.apple.photoanalysisd
launchctl disable gui/$(id -u)/com.apple.mediaanalysisd
# undo: the same with "enable", then log out and back in
```

## Wi-Fi

- Native Wi-Fi menu via ForbiddenItlwm (an AirportItlwm-Tahoe fork that also does AirDrop;
  see [AIRDROP.md](AIRDROP.md)). WPA2 and WPA2/WPA3 transition networks only. WPA3-only networks
  and mandatory PMF don't work.
- Wi-Fi uses a random ("private") MAC by default. Turn it off per network if your router or
  DNS server needs a stable address.
- **Pi-hole / filtering DNS users:**
  - If Wi-Fi connects but nothing resolves, iCloud **Private Relay** is probably on and your
    DNS blocks `mask.icloud.com`. Turn off Private Relay, or "Limit IP address tracking" for
    that network.
  - If Location Services never finds you, allowlist **`gs-loc.apple.com`** (Apple's Wi-Fi
    location lookup; it's on some blocklists).
- Location Services need the connected-scan fix (laobamac AirportItlwm `7204c69` or newer;
  ForbiddenItlwm includes it). Older builds return no networks to `locationd`.
- Fallbacks: AirportItlwm (in the EFI, disabled; see [AIRDROP.md](AIRDROP.md#switching-back-to-airportitlwm-no-airdrop)),
  and `itlwm.kext` + HeliPort (`MaxKernel 24.99.99`; to use it on Tahoe, swap its Min/MaxKernel
  with the active Wi-Fi kext's). Only ever load one Wi-Fi kext.

## Audio

- Speakers and the headphone jack use the custom AppleALC (SN6140, `layout-id` 21) plus SimpleHDA.
- If the jack misbehaves, try `layout-id` 15 (`DeviceProperties` → `PciRoot(0x0)/Pci(0x1f,0x3)`).
- `alc-verb` (built from AppleALC's source, `alcverbs=1`) can talk to the codec;
  `src/applealc/dump-codec.py` dumps its widget graph.

## Keyboard and pointing devices

- macOS key positions: **Alt = Command, Windows key = Option.**
- F1–F3 (mute/volume) work. PrtSc arrives as **F13**; bind it under Keyboard Shortcuts →
  Screenshots. Fn+F5/F6 change brightness. Fn+Space is the keyboard backlight (handled by the EC).
- **F4 (mic mute) and F7–F12** go through the ThinkPad EC and need YogaSMC (in the EFI) plus its
  menu-bar app **YogaSMCNC** from the [YogaSMC 1.5.3 release](https://github.com/zhen-zen/YogaSMC/releases/tag/1.5.3):
  copy it to `/Applications` and add it to **System Settings → General → Login Items**.
- If the keyboard backlight won't stay off, YogaSMCNC has saved a bad backlight timeout: quit it,
  run `defaults write org.zhen.YogaSMC BacklightTimeout -int 0`, and start it again.
- The calculator key is remapped to **F16** (VoodooPS2 `Custom ADB Map` `e021=6a`). Bind it with
  a Shortcuts-app keyboard shortcut. This mapping hasn't been verified on the hardware.
- **System Settings → Trackpad** controls the touchpad; **→ Mouse** controls the TrackPoint.
- **Turn off Trackpad → Point & Click → "Force Click and haptic feedback".** The touchpad shows up
  as a Magic Trackpad 2, but it has no pressure sensor. With Force Click on, pressing the pad down
  to click is ignored (tap to click still works).

## Chrome

If Chrome flickers, e.g. when viewing PDFs, open `chrome://flags/#skia-graphite`, choose the option
labelled **Disabled** and relaunch. Then check `chrome://gpu`: WebGL and WebGL2 must still say
"Hardware accelerated". Chrome stores flag choices by position, and after a Chrome update the
stored choice disabled the GPU entirely here ("GPU access is disabled due to frequent crashes",
no WebGL; sites like Gaia GPS refuse to load). Setting the flag back to **Default** fixed that.

## Never update

Keep automatic macOS updates off and ignore update offers. The graphics stack is tied to 25G241.
