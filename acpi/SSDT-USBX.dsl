/*
 * SSDT-USBX - USB power properties for Skylake-and-newer SMBIOS.
 *
 * No fake EC needed: this laptop's embedded controller is already named
 * \_SB.PC00.LPCB.EC, which is what macOS expects on a laptop.
 * Dortania's SSDT-USBX template, Darwin-only.
 */
DefinitionBlock ("", "SSDT", 2, "DRTNIA", "SsdtUsbx", 0x00001000)
{
    Scope (\_SB)
    {
        Device (USBX)
        {
            Name (_ADR, Zero)
            Method (_DSM, 4, NotSerialized)
            {
                If ((Arg2 == Zero))
                {
                    Return (Buffer (One) { 0x03 })
                }

                Return (Package ()
                {
                    "kUSBSleepPowerSupply", 0x13EC,
                    "kUSBSleepPortCurrentLimit", 0x0834,
                    "kUSBWakePowerSupply", 0x13EC,
                    "kUSBWakePortCurrentLimit", 0x0834
                })
            }

            Method (_STA, 0, NotSerialized)
            {
                If (_OSI ("Darwin"))
                {
                    Return (0x0F)
                }
                Else
                {
                    Return (Zero)
                }
            }
        }
    }
}
