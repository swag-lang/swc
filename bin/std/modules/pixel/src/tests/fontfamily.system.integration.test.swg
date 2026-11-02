#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows or #os == Swag.TargetOs.Linux
#global private

using Core

// Requires Segoe UI on Windows or DejaVu Sans on Linux.
#[Swag.TestTag("integration.fonts")]
#test
{
    const Name = #os == Swag.TargetOs.Windows ? "Segoe UI" : "DejaVu Sans"
    let names = FontFamily.enumerateSystemFontNames()
    Swag.assert(names.contains(String.from(Name)))
    Swag.assert((expect FontFamily.createTypeFace("Pixel missing family 6e2cbf11", .Regular)) == null)
    let ownedName = String.from(Name)
    for style in [FontFamilyStyle.Regular, .Bold, .Italic, .BoldItalic]
    {
        let face = unwrap expect FontFamily.createTypeFace(Name, style)
        Swag.assert((expect FontFamily.createTypeFace(ownedName.toString(), style)) == face)
        Swag.assert((expect face.renderGlyph('A', 20)).width > 0)
        if style == .Bold or style == .BoldItalic do
            Swag.assert(face.isBold() or face.forceBold)
        if style == .Italic or style == .BoldItalic do
            Swag.assert(face.isItalic() or face.forceItalic)
    }
}
