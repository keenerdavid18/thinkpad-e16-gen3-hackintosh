/*
 * SSDT-XOSI - answer _OSI like Windows under macOS.
 *
 * Needs the ACPI patch _OSI -> XOSI (DSDT only; 12 calls, no OSID here).
 * This DSDT sets OSYS from _OSI("Windows 20xx"); under macOS none match,
 * OSYS stays 0x03E8, and the touchpad's _CRS (\_SB.PC00.I2C0.TPD0) then
 * returns only an interrupt, without its I2C address - so VoodooI2C
 * can't find it. Matching up to "Windows 2015" gives OSYS 0x07DF.
 * Dortania's SSDT-XOSI template; "Linux" deliberately not listed.
 */
DefinitionBlock ("", "SSDT", 2, "DRTNIA", "XOSI", 0x00001000)
{
    Method (XOSI, 1, NotSerialized)
    {
        If (_OSI ("Darwin"))
        {
            Local0 = Package ()
            {
                "Windows 2001",
                "Windows 2001 SP1",
                "Windows 2001 SP2",
                "Windows 2001.1",
                "Windows 2006",
                "Windows 2006 SP1",
                "Windows 2006.1",
                "Windows 2009",
                "Windows 2012",
                "Windows 2013",
                "Windows 2015",
                "Windows 2016",
                "Windows 2017",
                "Windows 2017.2",
                "Windows 2018",
                "Windows 2018.2",
                "Windows 2019",
                "Windows 2020",
                "Windows 2021",
                "Windows 2022"
            }
            Return ((Ones != Match (Local0, MEQ, Arg0, MTR, Zero, Zero)))
        }
        Else
        {
            Return (_OSI (Arg0))
        }
    }
}
