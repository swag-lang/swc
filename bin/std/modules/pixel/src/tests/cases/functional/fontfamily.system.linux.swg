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
    Swag.require(regular and bold and italic)
    Swag.require(regular.face.hasChar('A'))
    Swag.require(bold != regular and italic != regular)
    Swag.require(bold.forceBold and italic.forceItalic)
    let repeated = expect FontFamily.createTypeFace(family, .Bold)
    Swag.require(repeated == bold)
    let empty = expect FontFamily.createTypeFace(SystemFontFamilyInfo{}, .Regular)
    Swag.require(not empty)
    family.faces[0].face.path = "/missing-swag-font-descriptor.ttf"
    var outcome: Swag.Error
    discard catch FontFamily.createTypeFace(family, .Regular) as outcome
    Swag.require(outcome.value() != null)
}
