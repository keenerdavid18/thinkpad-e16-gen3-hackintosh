# Known issues

| Issue | Details | Workaround |
|---|---|---|
| No system sleep | Modern-Standby-only firmware; a sleep attempt never completes and WindowServer hangs on wake | `pmset` settings in [POST-INSTALL.md](POST-INSTALL.md#power-sleep-and-the-lid); shut down instead |
| GPU hang right after boot | `gpuRestart` report on the copy engine (BCS, signature 2803) shortly after login on most boots | recovers by itself, harmless |
| Occasional render-engine hang | `gpuRestart` in WindowServer (RCS, `WAIT_ON_SCANLINE`), a known open issue of the NootedGreen stack; recovered as a brief blink | none needed; report patterns upstream |
| Freeze + restart after a GPU hang | a GPU hang is recovered, but its stuck job is never retired; when the app that owns it closes, the teardown waits forever while holding a lock WindowServer needs: black screen, then a watchdog panic. Seen with Photos' first-time library analysis (idle) and once right after Messages opened. Upstream issue [#31](https://github.com/JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe/issues/31) | disable Photos/media analysis (see [POST-INSTALL.md](POST-INSTALL.md#background-gpu-work)); after a visible GPU reset, **don't quit the app that triggered it**: save your work and restart from the Apple menu |
| Chrome flicker (e.g. PDFs), or no WebGL | Chrome's Skia Graphite renderer flickers; a Graphite flag stored by an older Chrome later disabled the GPU process entirely ("GPU access is disabled due to frequent crashes", no WebGL) | flicker: `chrome://flags/#skia-graphite` → the option labelled Disabled; no WebGL: set that flag back to **Default** and check `chrome://gpu` |
| macOS updates | anything past 25G241 breaks graphics | keep automatic updates off |
| AirDrop is a prerelease driver | ForbiddenItlwm 0.3.1-test1; cold iPhone → Mac connects can take a few seconds | switch back to AirportItlwm: [AIRDROP.md](AIRDROP.md) |
| Ethernet cable plugged in → higher idle power | with the I219-V linked, the CPU package stays at PC3 (~0.6 W more); Linux doesn't | unplug Ethernet when you don't need it |
| BTIdle is new | Bluetooth idle suspend (2026-11-11); Bluetooth audio and Bluetooth accessories haven't been tested much | `sudo sysctl debug.btidle.ms=0` (runtime) or boot arg `-btidleoff`; report problems |
| Internal microphones | DMICs behind the Intel DSP | headset or USB mic |
| Keyboard backlight turns itself back on | YogaSMCNC saved `BacklightTimeout = -1`, which YogaSMC treats as a timeout, so any key press relights it | quit YogaSMCNC, `defaults write org.zhen.YogaSMC BacklightTimeout -int 0`, start it again |
| WPA3-only Wi-Fi | AirportItlwm limitation | WPA2/WPA3 mixed mode on the router |
| Pressing the touchpad to click does nothing | VoodooInput presents a Force Touch trackpad but reports no pressure | Trackpad → turn off "Force Click and haptic feedback" |
| TrackPoint speed | follows the **Mouse** slider, not the Trackpad one | – |
| `disk0`/`disk1` numbers swap between boots | NVMe enumeration order | identify the ESP by size/contents before mounting |
| Dual boot: Windows clock off | Windows keeps the RTC in local time | set `RealTimeIsUniversal` in Windows |
| Dual boot: Bluetooth pairing | each OS has its own link keys for the same card | re-pair after switching |

## Reading panics without macOS

After a panic loop, the panic text stays in NVRAM. From Linux:
`/sys/firmware/efi/efivars/AAPL,PanicInfo*-7c436110-…`. Drop the 4-byte attribute header of
each, concatenate them, and unpack the 7-bit characters.
