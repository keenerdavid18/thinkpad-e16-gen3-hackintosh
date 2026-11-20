/*
 * SSDT-LIDWAKE: under macOS, report the EC's SCI GPE (0x6E) as the lid's wake GPE.
 * The DSDT's LID._PRW names GPE 0x17 = the EC's legacy S3 wake pin (GPIO group 11 pad 23), which this
 * Modern-Standby BIOS has disabled (PADCFG0 RX/TX disabled, no SCI route). In standby the EC signals lid open
 * through its SCI (GPE 0x6E) - Linux s2idle wakes on it. AppleACPIPlatform sets the Deep Idle wake GPEs from
 * the devices' _PRW right before the halt, so the lid has to name 0x6E for macOS to arm it.
 * v1: only on battery (on AC the EC raises 0x6E for charge events -> constant dark wakes).
 * Needs the OpenCore ACPI patch LID._PRW -> XPRW (Base \_SB.LID, DSDT, count 1).
 * Hand-assembled by make-ssdt-lidwake.py (no iasl on the Mac).
 */
DefinitionBlock ("", "SSDT", 2, "HACK", "LIDWAKE", 0x00000001)
{
    If (Zero)
    {
        External (\_SB.LID, DeviceObj)
        External (\_SB.LID.XPRW, MethodObj)    // 0 arguments
        External (\_SB.PC00.LPCB.EC.AC._PSR, MethodObj)    // 0 arguments
    }

    Scope (\_SB.LID)
    {
        Method (_PRW, 0, NotSerialized)
        {
            // Battery only: on AC the EC raises GPE 0x6E for charge events too (dark wake every ~10-15 s).
            If ((_OSI ("Darwin") && (\_SB.PC00.LPCB.EC.AC._PSR () == Zero)))
            {
                Return (Package (0x02) { 0x6E, 0x03 })
            }

            Return (\_SB.LID.XPRW ())
        }
    }
}
