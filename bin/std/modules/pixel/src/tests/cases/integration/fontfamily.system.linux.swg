#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

using Core

#[Swag.TestTag("integration.fonts")]
#test
{
    let families = FontFamily.enumerateSystemFonts()
    let names    = FontFamily.enumerateSystemFontNames()

    // This opt-in integration requires at least one installed supported font.
    Swag.require(not families.isEmpty())
    Swag.require(families.count == names.count)
    for family in families
    {
        Swag.require(names.contains(family.name))
        let found = FontFamily.findSystemFont(family.name.toString())
        Swag.require(found.name == family.name)
        for j in FontFamilyStyle.count
        {
            Swag.require(not family.faces[j].face.path.isEmpty())
            Swag.require(family.faces[j].face.path == found.faces[j].face.path)
            Swag.require(family.faces[j].face.faceIndex == found.faces[j].face.faceIndex)
        }
    }

    let missing = FontFamily.findSystemFont("Swag Uninstalled Font 742EB013")
    Swag.require(missing.name.isEmpty())
}
