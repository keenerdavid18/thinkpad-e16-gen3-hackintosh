# iPhone Mirroring / AirPlay to Mac

On this Iris Xe (NootedGreen) build, **AirPlay from an iPhone to the Mac** and the **iPhone Mirroring** app first
**crashed WindowServer** (you're logged out), and with that fixed, the screen went black. Two small user-space
workarounds:

| Part | Problem | Fix |
|---|---|---|
| `ws-nogva` | WindowServer scales the iPhone picture with AppleGVA's hardware scaler, which asserts on this GPU stack (`AVFPixelProcessCore_PrepareToTransferImages` → `__assert_rtn`) → WindowServer crash, logout | turns that scaler off with a WindowServer debug option (`SLSSetDebugOptions(0x80000122)`, sets SkyLight's `gWSGVAEnabled`, which its scaling code reads as "skip GVA"); WindowServer then scales with Metal. Runs at every login |
| `vtbgra.dylib` | the iPhone stream is decoded to YUV 4:2:0; WindowServer's composite of that turns the **whole** panel black (first frame shows, then black until you stop) | loaded into ControlCenter (the AirPlay receiver) at login; forces the decoder output to BGRA. Plus `defaults write -g enableGVATransfer -bool NO` |

The `vtbgra` idea comes from gianguyen14's
[airplayfix](https://github.com/gianguyen14/efi-latitude-5320/tree/main/PostInstall/Tools/airplayfix) for Tiger Lake
([b00t0x/WhateverXe#144](https://github.com/b00t0x/WhateverXe/issues/144)); this is a rewrite for this machine.

## Status

| | |
|---|---|
| AirPlay screen mirroring from an iPhone | **works** |
| A video sent over AirPlay from an app (e.g. YouTube) | plays, then turns **tiled** after a few seconds (likely the GPU's YUV→BGRA conversion in `VTDecoderXPCService`; open) |
| iPhone Mirroring app | crash fixed; picture untested with `vtbgra` (start it with `mirror.sh`) |

## Install

Needs `amfi_get_out_of_my_way=1` in boot-args (the main `config.plist` has it) and the Xcode Command Line Tools.

```zsh
zsh tools/iphone-mirroring/install.sh          # builds both, installs two LaunchAgents, applies them now
zsh tools/iphone-mirroring/install.sh remove   # undo everything
```

`install.sh` builds `ws-nogva` (ad-hoc signed with the `com.apple.private.CoreGraphics.debugging` entitlement WindowServer
requires for debug options) and `vtbgra.dylib`, sets `enableGVATransfer`, and adds:
- `local.e16.ws-nogva`: runs `ws-nogva` at login (WindowServer forgets the option when it restarts);
- `local.e16.airplay-bgra`: restarts ControlCenter with `DYLD_INSERT_LIBRARIES` set for 5 s.

`vtbgra.dylib` only acts in ControlCenter, iPhone Mirroring, ScreenContinuityAgent and AirPlayXPCHelper; elsewhere it
passes through. It logs to the unified log: `log show --last 5m --predicate 'eventMessage CONTAINS "[vtbgra]"'`.

For the iPhone Mirroring app: `zsh tools/iphone-mirroring/mirror.sh` (opens it with the library loaded).

## Notes from the investigation (SkyLight, macOS 26.7.1)

- `ws-nogva on` (`0x80000121`) turns the GVA scaler back on.
- Two other WindowServer debug options were tried against the black screen and did **not** help: `0x80000070`
  (detached layers off) and `0x80000102` (content-protection enforcement off).
- Debug options need `com.apple.private.CoreGraphics.debugging` (`debug_connection_permitted`); none of the three
  above is on SkyLight's Apple-internal-only list.
