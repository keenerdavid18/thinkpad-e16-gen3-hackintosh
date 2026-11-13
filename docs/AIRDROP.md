# AirDrop

AirDrop works in both directions (iPhone ↔ Mac) with [ForbiddenItlwm](https://github.com/retropineaple/ForbiddenItlwm). It's a fork of AirportItlwm-Tahoe that adds AWDL, the Wi-Fi side of AirDrop, alongside a normal Wi-Fi connection. Its companion kext **BTLEAdvFixup** lets the Mac advertise over Bluetooth LE, which is how iPhones find it.

`config.plist` ships with both enabled:

| | |
|---|---|
| Wi-Fi driver | ForbiddenItlwm **0.5.3-test1** (official release build, [release](https://github.com/retropineaple/ForbiddenItlwm/releases/tag/v0.5.3-test1); includes 0.4.0's security fixes) |
| Bluetooth LE | BTLEAdvFixup 0.9.0. **IntelBTPatcher is disabled**, because both hook the same function and loading both panics. |
| Boot flags | `-btleadv` and the `-itlawdl*` / `itlawdlintcoal=4` / `itlawdltxqueue=4096` set from ForbiddenItlwm's [BOOT-FLAGS.md](https://github.com/retropineaple/ForbiddenItlwm/blob/main/docs/BOOT-FLAGS.md) |

On this laptop (AX211 `8086:51F1`), every AirDrop frame from the iPhone arrived with 8 bytes of zero padding, and the driver rejected all of them, so transfers stayed on "Waiting". The fix was found here ([ForbiddenItlwm#6](https://github.com/retropineaple/ForbiddenItlwm/issues/6)) and is part of every release since 0.3.1-test1.

## Requirements

- **Bluetooth on.** AirDrop discovery runs over Bluetooth LE.
- **A nearby Wi-Fi network that advertises a country that allows channel 149.** The AX211 firmware only opens channel 149 after it learns the country, and AirDrop is fast only there. See ForbiddenItlwm's README, "Channel 149 and your country".
- macOS 26.7.1 (25G241). The driver keeps AirDrop off on builds it doesn't know.

## Check

```zsh
ioreg -l -w0 | grep -E '"ItlwmAWDL(InterfaceBuild|BuildCheck)"|"ITLAWDLCoex(Added|Channel|CountryLearned|ZeroPadTrimmed|Forwarded)"'
```

Expected: `forbidden-0.5.3-test1`, `verified`, `Added = Yes`, `Channel = 149`, `CountryLearned = Yes`. `ZeroPadTrimmed` and `Forwarded` rise together while an iPhone is nearby.

## Notes

- **It's a prerelease, AI-assisted kernel driver** maintained by someone else. Cold iPhone → Mac connects can take a few seconds. Check the ForbiddenItlwm README for its current limits.
- **Wi-Fi itself behaves as with AirportItlwm.** WPA2 and WPA2/WPA3 mixed networks work; WPA3-only networks don't.
- **Bluetooth stays on with AirDrop.** [BTIdle](https://github.com/keenerdavid18/hackintosh-power-tools/tree/main/macos/btidle) (enabled) keeps the idle cost of that low; see [POST-INSTALL.md](POST-INSTALL.md#idle-power).

## Switching back to AirportItlwm (no AirDrop)

In `config.plist`:
1. Set `Kernel/Add` → `ForbiddenItlwm.kext` **Enabled = false** and `AirportItlwm.kext` **Enabled = true**. Never load both.
2. Set `BTLEAdvFixup.kext` **Enabled = false** and `IntelBTPatcher.kext` **Enabled = true**.
3. Remove `-btleadv` and every `-itlawdl…` / `itlawdl…=` flag from `boot-args`.

`config-install.plist` already uses AirportItlwm and IntelBTPatcher.
