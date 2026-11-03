/*
 * SSDT-PNLF: backlight device for macOS (AppleBacklight via WhateverGreen/NootedGreen).
 * Same content as the compiled EFI/OC/ACPI/SSDT-PNLF.aml (from the JulioNectar reference EFI):
 * a PNLF device under the iGPU, _UID 19 (Coffee Lake and newer), present only on macOS.
 * This E16's iGPU path is \_SB.PC00.GFX0.
 */
DefinitionBlock ("", "SSDT", 2, "INTL", "PNLF", 0x00000000)
{
    External (_SB_.PC00.GFX0, DeviceObj)

    Device (_SB.PC00.GFX0.PNLF)
    {
        Name (_HID, EisaId ("APP0002"))
        Name (_CID, "backlight")
        Name (_UID, 0x13)
        Method (_STA, 0, NotSerialized)
        {
            If (_OSI ("Darwin"))
            {
                Return (0x0B)
            }
            Else
            {
                Return (Zero)
            }
        }
    }
}
