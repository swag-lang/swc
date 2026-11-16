#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows or #os == Swag.TargetOs.Linux
#global private

using Core

// A test run never sees the fonts installed on the machine: every system lookup answers as if
// none were, whatever the machine holds, so nothing a test draws can depend on it.
#test
{
    Swag.require(Env.hasArgument("swag.test"))
    Swag.require(not FontFamily.hasSystemFontAccess())

    Swag.require(FontFamily.enumerateSystemFonts().isEmpty())
    Swag.require(FontFamily.enumerateSystemFontNames().isEmpty())
    for name in ["Segoe UI", "Arial", "Times New Roman", "Consolas", "DejaVu Sans", "Liberation Sans", "Noto Sans"]
    {
        Swag.require(FontFamily.findSystemFont(name).name.isEmpty(), name)
        for style in [FontFamilyStyle.Regular, .Bold, .Italic, .BoldItalic] do
            Swag.require((expect FontFamily.createTypeFace(name, style)) == null, name)
    }
}

// A bare file name is an installed font too: it is not found in the machine's font folder, while
// a face loaded from a path the test owns still is.
#test
{
    for name in ["segoeui.ttf", "arial.ttf", "DejaVuSans.ttf", "LiberationSans-Regular.ttf"]
    {
        Swag.require(not TypeFace.exists(name), name)
        var outcome: Swag.Error
        discard catch TypeFace.load(name) as outcome
        Swag.require(outcome.value() != null, name)
    }

    let path = getTestDataPath("segoeui.ttf")
    Swag.require(TypeFace.exists(path))
    Swag.require((expect TypeFace.load(path)) == (expect TypeFace.load(path)))
}

// A font cache left to its default policy does not reach for an installed face either: a rune
// its faces lack stays unresolved instead of borrowing a glyph from the machine.
#test
{
    var cache: FontCache
    let font = cache.createFont(expect fallbackTestFace(false), 19, .Bitmap, true, true)
    Swag.require(font.glyphIndex('\u2192'rune) == 0)
    Swag.require(font.resolveRune('\u2192'rune) == font)

    // A face the test supplies is still used.
    cache.setFallbackTypeFaces([expect fallbackTestFace(true)])
    Swag.require(font.resolveRune('\u2192'rune) != font)
}

// The access is a switch a system-font test turns on for itself and off again.
#test
{
    FontFamily.setSystemFontAccess(true)
    Swag.require(FontFamily.hasSystemFontAccess())
    FontFamily.setSystemFontAccess(false)
    Swag.require(not FontFamily.hasSystemFontAccess())
    Swag.require(FontFamily.enumerateSystemFontNames().isEmpty())
}
