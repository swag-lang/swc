#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Core, Win32.Gdi32

#[Swag.TestTag("fonts.descriptors")]
#test
{
    Swag.require(FontFamily.classifySystemFontStyle(FW_DONTCARE, false) == .Regular)
    Swag.require(FontFamily.classifySystemFontStyle(FW_LIGHT, false) == .Light)
    Swag.require(FontFamily.classifySystemFontStyle(FW_REGULAR, false) == .Regular)
    Swag.require(FontFamily.classifySystemFontStyle(FW_SEMIBOLD, false) == .SemiBold)
    Swag.require(FontFamily.classifySystemFontStyle(FW_BOLD, false) == .Bold)

    Swag.require(FontFamily.classifySystemFontStyle(FW_REGULAR, true) == .Italic)
    Swag.require(FontFamily.classifySystemFontStyle(FW_SEMIBOLD, true) == .Italic)
    Swag.require(FontFamily.classifySystemFontStyle(FW_BOLD, true) == .BoldItalic)
}
