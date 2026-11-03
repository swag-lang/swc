#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

using Core

#[Swag.TestTag("fonts.descriptors")]
#test
{
    var catalog: FontCatalog
    discard expect catalog.addFile(getTestDataPath("segoeui.ttf"))
    let source = catalog.toSlice()[0]
    var family = SystemFontFamilyInfo{name: source.metadata.typographicFamilyName}
    family.faces[cast(u64, FontFamilyStyle.Regular)] = SystemFontFaceInfo{source.metadata.typographicStyleName, source}
    catalog.clear()
    let regular = expect FontFamily.createTypeFace(family, .Regular)
    let bold    = expect FontFamily.createTypeFace(family, .Bold)
    let italic  = expect FontFamily.createTypeFace(family, .Italic)
    Swag.assert(regular and bold and italic)
    Swag.assert(regular.face.hasChar('A'))
    Swag.assert(bold != regular and italic != regular)
    Swag.assert(bold.forceBold and italic.forceItalic)
    let repeated = expect FontFamily.createTypeFace(family, .Bold)
    Swag.assert(repeated == bold)
    let empty = expect FontFamily.createTypeFace(SystemFontFamilyInfo{}, .Regular)
    Swag.assert(not empty)
    family.faces[0].face.path = "/missing-swag-font-descriptor.ttf"
    var outcome: Swag.Error
    discard catch FontFamily.createTypeFace(family, .Regular) as outcome
    Swag.assert(outcome.value() != null)
}
