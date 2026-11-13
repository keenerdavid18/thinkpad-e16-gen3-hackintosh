# External displays

Both of the laptop's display outputs work, through this EFI's own NootedGreen build
([src/nootedgreen](../src/nootedgreen)):

| Output | Status | Tested with |
|---|---|---|
| **HDMI port** | works; hot plug after login | LG 29" UltraWide, 2560×1080@60 |
| **USB-C** (DisplayPort alt mode) | works; hot plug and unplug | Anker USB-C dock: its DP-alt output (2560×1080@60 through the dock's DP→HDMI converter) + 2 DisplayLink outputs, gigabit Ethernet, USB 3, 60 W charging, all on one cable |

The boot flags are already in `config.plist`:
- **HDMI:** `ngreenhdmilight=2 ngreenhdmiflags=0x202 ngreenhdmiddc=1`, plus `ngreenhdmiaux=1 ngreenhdmiedid=1
  ngreenhdmisink=1 ngreenhdmiregs=1`, which are part of the tested set.
- **USB-C:** `-ngreentc1`. It needs the HDMI set, because it shares that code.

## Use

- **Connect external displays after you log in.** Booting with one attached isn't reliable:
  - with HDMI, both screens stayed black;
  - with the USB-C dock, one boot in two stalled at the progress bar.
- **Hot plug and unplug** both work, with the lid open or closed. With the lid closed, macOS uses only the external
  screens (clamshell mode).
- **Display sleep** (idle or lid closed) and wake work with the dock attached. System sleep doesn't exist on this
  machine (see [KNOWN-ISSUES.md](KNOWN-ISSUES.md)).
- **DisplayLink outputs** on a dock need [DisplayLink Manager](https://www.synaptics.com/products/displaylink-graphics/downloads/macos)
  running. They are drawn by that app, not by the GPU.

## Limits

- **USB-C is a single DisplayPort stream on 2 lanes at HBR2** (the dock's USB-C pin assignment D leaves the other two
  lanes for USB 3). That carries up to about 4K@30 or 2560×1440@60 at 8 bits per colour; there is no MST
  (daisy-chaining) and no DSC.
- **Only Type-C port 1** has been set up and tested.
- **HDMI runs in DVI mode:** no HDMI audio. There is no audio over the USB-C link to the monitor either.
- **HDMI monitor through a USB-C dock looks dim or washed out?** macOS may send it YCbCr instead of RGB. An EDID
  override in `/Library/Displays/Contents/Resources/Overrides/` that clears the YCbCr bits (CEA extension byte 3,
  bits 4–5) makes macOS use RGB.

## Check

```zsh
ioreg -l -w0 | grep -E '"ngreen-tc1(-con2)?" ='
```
`ngreen-tc1-con2` should show `ddi=3 ... type=0x400` (the USB-C connector). With a monitor attached,
`system_profiler SPDisplaysDataType` lists it with its resolution.

For problems, add `-ngreentc1dbg` to the boot args: the driver then publishes register snapshots and the link-training
trace (`ngreen-tc1-snap0/1`, `ngreen-tc1-dpcd1..3`, ...) in ioreg.
