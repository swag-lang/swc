#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Core

// Requires the system font installed with Windows.
#[Swag.TestTag("integration.fonts")]
#test
{
    const Name = "Segoe UI"
    let names = FontFamily.enumerateSystemFontNames()
    Swag.require(names.contains(String.from(Name)))
    Swag.require((expect FontFamily.createTypeFace("Pixel missing family 6e2cbf11", .Regular)) == null)
    let ownedName = String.from(Name)
    for style in [FontFamilyStyle.Regular, .Bold, .Italic, .BoldItalic]
    {
        let face = unwrap expect FontFamily.createTypeFace(Name, style)
        Swag.require((expect FontFamily.createTypeFace(ownedName.toString(), style)) == face)
        Swag.require((expect face.renderGlyph('A', 20)).width > 0)
        if style == .Bold or style == .BoldItalic do
            Swag.require(face.isBold() or face.forceBold)
        if style == .Italic or style == .BoldItalic do
            Swag.require(face.isItalic() or face.forceItalic)
    }
}
