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
    Swag.assert(not families.isEmpty())
    Swag.assert(families.count == names.count)
    for family in families
    {
        Swag.assert(names.contains(family.name))
        let found = FontFamily.findSystemFont(family.name.toString())
        Swag.assert(found.name == family.name)
        for j in FontFamilyStyle.count
        {
            Swag.assert(not family.faces[j].face.path.isEmpty())
            Swag.assert(family.faces[j].face.path == found.faces[j].face.path)
            Swag.assert(family.faces[j].face.faceIndex == found.faces[j].face.faceIndex)
        }
    }

    let missing = FontFamily.findSystemFont("Swag Uninstalled Font 742EB013")
    Swag.assert(missing.name.isEmpty())
}
