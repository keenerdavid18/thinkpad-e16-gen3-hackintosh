# Known issues

| Issue | Details | Workaround |
|---|---|---|
| No system sleep | Modern-Standby-only firmware; a sleep attempt never completes and WindowServer hangs on wake | `pmset` settings in [POST-INSTALL.md](POST-INSTALL.md#power-sleep-and-the-lid); shut down instead |
| GPU hang right after boot | `gpuRestart` report on the copy engine (BCS, signature 2803) shortly after login on most boots | recovers by itself, harmless |
| Occasional render-engine hang | `gpuRestart` in WindowServer (RCS, `WAIT_ON_SCANLINE`), a known open issue of the NootedGreen stack; recovered as a brief blink | none needed; report patterns upstream |
| Chrome flicker (e.g. PDFs) | Chrome's Skia Graphite renderer | `chrome://flags/#skia-graphite` → Disabled |
| macOS updates | anything past 25G241 breaks graphics | keep automatic updates off |
| AirDrop / AWDL / Sidecar | Intel Wi-Fi can't do AWDL | Broadcom card (untested; the CNVi slot may not take PCIe cards) |
| Internal microphones | DMICs behind the Intel DSP | headset or USB mic |
| ThinkPad hotkeys F4, F7–F12 | EC → HKEY events (`_Qxx` → `MHKQ`), not handled | none yet (YogaSMC is untested on Tahoe) |
| WPA3-only Wi-Fi | AirportItlwm limitation | WPA2/WPA3 mixed mode on the router |
| TrackPoint speed | follows the **Mouse** slider, not the Trackpad one | – |
| `disk0`/`disk1` numbers swap between boots | NVMe enumeration order | identify the ESP by size/contents before mounting |
| Dual boot: Windows clock off | Windows keeps the RTC in local time | set `RealTimeIsUniversal` in Windows |
| Dual boot: Bluetooth pairing | each OS has its own link keys for the same card | re-pair after switching |

## Reading panics without macOS

After a panic loop, the panic text stays in NVRAM. From Linux:
`/sys/firmware/efi/efivars/AAPL,PanicInfo*-7c436110-…`. Drop the 4-byte attribute header of
each, concatenate them, and unpack the 7-bit characters.
