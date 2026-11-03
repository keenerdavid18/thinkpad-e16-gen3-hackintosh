# Graphics acceleration (Iris Xe, macOS Tahoe 26.7.1 25G241 only)

The stack comes from [JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe](https://github.com/JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe),
a fork of [NootedGreen](https://github.com/sgiammori/NootedGreen). It presents the Raptor Lake
iGPU as a Tiger Lake one (`9A49`), loads Apple's GPUDriversIntel 16.0.32 Tiger Lake kexts from
`/Library/Extensions`, and patches them and Metal for Tahoe. It is pinned to **25G241**.

Already in this EFI: `NootedGreen.kext` (built from that project, NootedGreen `95f8189`),
`WhateverGreen.kext` 1.7.2, `SSDT-PNLF`, `BrightnessKeys.kext`, the iGPU device properties,
SIP partly off (`csr-active-config` `130A0000`) and the boot-args below.

## Steps

1. On the ESP, use the accelerated **`config.plist`** (not `config-install.plist`) and reboot.
   Check: `ioreg -r -c IOPCIDevice -n IGPU -d1 | grep device-id` → `<499a0000>`, `csrutil status`
   shows a custom configuration, `kmutil showloaded | grep NootedGreen`.
2. Install the Command Line Tools (`xcode-select --install`) if needed.
3. Build and install the user-space part from the reference project. Never run its
   `make-efi.sh`; it generates new SMBIOS serials.
   ```zsh
   git clone https://github.com/JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe.git ref
   cd ref
   zsh install.sh --build-only   # builds everything, installs nothing
   zsh install.sh                # asks for your password, installs into /Library
   ```
   It installs Apple's TGL kexts + HookCase into `/Library/Extensions`, the patched Metal driver
   into `/Library/GPUBundles`, and the shader compiler into `/System/Library/Caches/xe.bundle`,
   then registers the kexts ("requires a reboot"). Ignore its instruction to copy NootedGreen.kext:
   this EFI already has one. If you rebuild it, copy `build/NootedGreen.kext` here.
4. If macOS asks, allow the extension in System Settings → Privacy & Security. Reboot.
5. Check: `system_profiler SPDisplaysDataType` shows **Metal Support: Metal 2**, and
   `ioreg -rc IntelAccelerator -d1 | grep xe-topo` shows **16390** (64 EU, 6 L3 banks).

## Boot-args (in `config.plist`)

| Boot-arg | Why |
|---|---|
| `IGLogLevel=3 -ngreentglwithgfx -allow3d -disablegfxfirmware ngreen-dmc=adlp -ngreenv189 -ngreenkeepefi -ngreenxefix -ngreenfixbootmode ngreenSched=4 ngreenV142=3` | the reference project's set |
| `amfi_get_out_of_my_way=1` | required by the patched Metal stack |
| `ngreen-eu=64 ngreen-l3=6` | **this CPU's iGPU**: 64 EU and 6 L3 banks (measured on Linux, see below). The default is 96/8 |
| `ngreenblmax=17741` | full backlight range. The panel's PWM period is 96000; Apple's driver writes 17741 at 100 %. Without it, maximum brightness is ~18 % |
| `-ngreenpm` | XE-PM: hybrid-CPU turbo fix (P-cores were capped ~3.8 GHz), EPP 0, deep C-states. Keeps the BIOS power limit. Don't use `ngreenpm=22`; that's the XPS's limit |
| `itlwm_he=1` | Wi-Fi 6 rates (AirportItlwm) |
| `alcverbs=1`, `keepsyms=1`, `debug=0x100` | audio verb tool, readable panics, no reboot on panic |

Don't add `-ngreenfbdpms`: the panel doesn't come back from display sleep with it.

### Measuring EU / L3 (other CPUs)

From a Linux live USB (i915): `sudo cat /sys/kernel/debug/dri/0/i915_sseu_status` (EU = DSS ×
16) and `sudo intel_reg read 0x9118` (`intel-gpu-tools`). The low nibble is the disabled
L3-bank-pair mask: banks = 2 × (4 − set bits). This CPU: 4 subslices → 64 EU, `0x88` → 6 banks.

### Backlight calibration (other panels)

`sudo dmesg | grep "bl hw="` at full brightness prints `bl hw=<period> … max=<apple max duty>`.
Set `ngreenblmax=<max>`.

## Updating / removing

`install.sh` in the reference project handles updates (`git pull`, re-run) and
`zsh install.sh --uninstall`. To boot without acceleration, use `config-install.plist`.
