# NootedGreen (this EFI's build)

`EFI/OC/Kexts/NootedGreen.kext` is
[JulioNectar's NootedGreen](https://github.com/JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe) at `24450b4` with two
patches:

| Patch | What it adds | From |
|---|---|---|
| `0001-vostroxe-xe-hdmi13.diff` | The laptop's **HDMI port** (XE-HDMI13: pipe B, DPLL, DDC, TMDS light-up on display 13) | [henriquejsza/VostroXe](https://github.com/henriquejsza/VostroXe) (NootedGreen changes since `6f03560`) |
| `0002-usbc-dp-alt-mode.diff` | **USB-C DisplayPort alt mode** (docks, USB-C monitors) on ADL-P/RPL-P with the TGL framebuffer, boot flag `-ngreentc1` | this repo |

Build: `zsh src/nootedgreen/build.sh` (clones the reference, applies both, runs its `build-nootedgreen.sh`).

## USB-C: what the patch does

macOS's Tiger Lake framebuffer already contains Type-C code, but Alder/Raptor Lake-P's display engine differs from
Tiger Lake in many details. The patch fills those gaps, in connection order:

- **Connector:** Apple's own entry for Type-C port 1 (DDI index 3) in the third connector slot.
- **Connect:** power well 2, PHY ownership through `DDI_BUF_CTL` bit 6, "ready" from `TCSS_DDI_STATUS` instead of
  TGL's FIA handshake, AUX power and AUX routing; unplug detected from `TCSS_DDI_STATUS`.
- **PHY:** the Dekel PHY register translation (lane-group bank, PHY base, ADL-P PLL enable), both lane groups
  programmed for USB-C pin assignment D, lane suspend released; the modular FIA's lane mask and lane count.
- **Display path:** a pipe for the port before link training, a full modeset for it, the HDCP object's register
  access, the DDI IO power well, transcoder clock (PHY encoding) and DDI route before training, the ADL-P link-rate
  field in `DDI_BUF_CTL`, enhanced framing in `DP_TP_CTL`.
- **Link:** the light-up stays at HBR2 (the link did not equalise at HBR here); lanes are capped at the port's 2;
  the DP-to-HDMI converter's 180 MHz lane-count cap is lifted so 2560×1080@60 is offered.
- **Unplug:** the port is released only after macOS has turned the pipe off.

`-ngreentc1dbg` adds register snapshots and link-training traces (ioreg `ngreen-tc1-*` on the framebuffer controller).

The register layouts follow the Linux i915 driver; [b00t0x/WhateverXe](https://github.com/b00t0x/WhateverXe)
(BSD-3-Clause) was a valuable cross-check for the Dekel tables, the DP-alt FIA functions and the pre-training
transcoder route.

NootedGreen and its forks are under the Thou Shalt Not Profit License 1.0 (no commercial use):
[licenses/NootedGreen-ThouShaltNotProfit-1.0.txt](../../licenses/NootedGreen-ThouShaltNotProfit-1.0.txt).
