# Third-party components

Everything in `EFI/` that isn't listed under "this repo" belongs to its authors and keeps its
license (as recorded by GitHub, checked 2026-11-02). Sources and versions:

| Component | Version | Source | License |
|---|---|---|---|
| OpenCore (`BOOTx64.efi`, `OpenCore.efi`, drivers, `OpenShell.efi`) | 1.0.8 RELEASE | [acidanthera/OpenCorePkg](https://github.com/acidanthera/OpenCorePkg) | BSD-3-Clause |
| Lilu | 1.7.2 | [acidanthera/Lilu](https://github.com/acidanthera/Lilu) | BSD-3-Clause |
| AppleALC | 1.9.8 + SN6140 entry, built by `src/applealc` | [acidanthera/AppleALC](https://github.com/acidanthera/AppleALC) | BSD-3-Clause |
| WhateverGreen | 1.7.2 (from the JulioNectar reference EFI) | [acidanthera/WhateverGreen](https://github.com/acidanthera/WhateverGreen) | BSD-3-Clause |
| VirtualSMC, SMCProcessor, SMCBatteryManager | 1.3.8 | [acidanthera/VirtualSMC](https://github.com/acidanthera/VirtualSMC) | BSD-3-Clause |
| RestrictEvents | 1.1.6 | [acidanthera/RestrictEvents](https://github.com/acidanthera/RestrictEvents) | BSD-3-Clause |
| CpuTopologyRebuild | 2.0.2 | [b00t0x/CpuTopologyRebuild](https://github.com/b00t0x/CpuTopologyRebuild) | BSD-3-Clause |
| NVMeFix | 1.1.3 | [acidanthera/NVMeFix](https://github.com/acidanthera/NVMeFix) | see upstream LICENSE |
| BrightnessKeys | 1.0.4 | [acidanthera/BrightnessKeys](https://github.com/acidanthera/BrightnessKeys) | BSD-3-Clause |
| BlueToolFixup | 2.7.2 | [acidanthera/BrcmPatchRAM](https://github.com/acidanthera/BrcmPatchRAM) | GPL-2.0 |
| VoodooPS2Controller (+ VoodooInput) | 2.3.7 (calculator key mapped to F16) | [acidanthera/VoodooPS2](https://github.com/acidanthera/VoodooPS2) | see upstream LICENSE |
| VoodooI2C, VoodooI2CHID | 2.9.1 (`IOPCIMatch` + `0x51e88086`) | [VoodooI2C/VoodooI2C](https://github.com/VoodooI2C/VoodooI2C) | GPL-3.0 |
| VoodooGPIO (in VoodooI2C) | 1.2 + Tiger Lake-LP fix, built by `src/voodoogpio` | [VoodooI2C/VoodooGPIO](https://github.com/VoodooI2C/VoodooGPIO) | GPL-3.0 |
| USBToolBox | 1.2.0 | [USBToolBox/kext](https://github.com/USBToolBox/kext) | no license file upstream |
| IntelMausiEthernet | 3.0.1 | [Mieze/IntelMausiEthernet](https://github.com/Mieze/IntelMausiEthernet) | no license file upstream (see source headers) |
| itlwm | 2.3.0 | [OpenIntelWireless/itlwm](https://github.com/OpenIntelWireless/itlwm) | GPL-2.0 ([licenses/itlwm-GPL-2.0.txt](licenses/itlwm-GPL-2.0.txt)) |
| AirportItlwm-Tahoe | 2.4.0-alpha `7204c69` (official release build) | [laobamac/itlwm](https://github.com/laobamac/itlwm) | GPL-2.0 |
| IntelBluetoothFirmware, IntelBTPatcher | 2.5.2 (`14787a2`), built by `src/intelbluetooth` | [lshbluesky/IntelBluetoothFirmware](https://github.com/lshbluesky/IntelBluetoothFirmware) | GPL-3.0; Intel firmware under its linux-firmware license |
| NootedGreen | JulioNectar reference `24450b4` (NootedGreen base `95f8189`), built with the reference's `install.sh --build-only` | [JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe](https://github.com/JulioNectar/Hackintosh-XPS13Plus-IrisXe-Tahoe), [sgiammori/NootedGreen](https://github.com/sgiammori/NootedGreen) | Thou Shalt Not Profit 1.0 ([licenses/](licenses/NootedGreen-ThouShaltNotProfit-1.0.txt)): no commercial use |
| `SSDT-PNLF.aml` | from the JulioNectar reference EFI | as above | |
| SimpleHDA | 1.0.0 (**not included**, `tools/fetch-simplehda.sh`) | [laobamac/SimpleHDA](https://github.com/laobamac/SimpleHDA) | no license file; contains Apple's AppleHDA |

**This repo:** `config.plist`, `config-install.plist`, `UTBMap.kext` (USBToolBox map for this
laptop), `XHCI-unsupported-600.kext` (codeless, adds `0x51ed8086`), `SSDT-AWAC/PLUG-ALT/USBX/XOSI`
(Dortania/acidanthera templates adapted to this DSDT), the build scripts and docs: MIT.
`src/voodoogpio/build-voodoogpio.sh` is adapted from the JulioNectar project (TSNP 1.0).

**Not included:** Apple software. The graphics install downloads and patches Apple's
GPUDriversIntel 16.0.32 bundles on your machine (via the reference project), and SimpleHDA is
fetched separately. Apple, macOS and Metal are trademarks of Apple Inc.
