/*
 * SSDT-AWAC - re-enable the legacy RTC for macOS.
 *
 * This ThinkPad's DSDT gates \_SB.AWAC and \_SB.RTC on the STAS field
 * (AWAC._STA returns 0x0F when STAS == 0, RTC._STA when STAS == 1).
 * macOS has no AWAC driver, so flip STAS to 1 under Darwin only.
 * Dortania's SSDT-AWAC template; DSDT has no existing \_SB._INI.
 */
DefinitionBlock ("", "SSDT", 2, "DRTNIA", "AWAC", 0x00000000)
{
    External (STAS, FieldUnitObj)

    Scope (_SB)
    {
        Method (_INI, 0, NotSerialized)
        {
            If (_OSI ("Darwin"))
            {
                STAS = One
            }
        }
    }
}
