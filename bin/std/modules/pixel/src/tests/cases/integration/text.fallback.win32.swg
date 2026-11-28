#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Swag

// A cold ordinary fallback must not enumerate every installed family before trying Segoe UI.
#[Swag.TestTag("integration.fonts")]
#test
{
    // This case is about the installed fonts themselves, which a test run otherwise never sees.
    FontFamily.setSystemFontAccess(true)
    defer FontFamily.setSystemFontAccess(false)

    var cache: SystemFontFallbackCache
    for c in [0_rune, '\t'_rune, '\n'_rune, '\r'_rune, '\u007F'_rune, '\u0085'_rune, '\u009F'_rune]
    {
        let control = cache.find(c, .Italic)
        Swag.require(not control and not cache.preferredReady and not cache.complete and cache.faces.count == 0)
    }

    let invalid = cache.find('\U0010FFFF'_rune, .Regular)
    Swag.require(not invalid and not cache.preferredReady and not cache.complete)
    let face = cache.find('A'_rune, .BoldItalic)
    Swag.require(face != null and face.face.hasChar('A'_rune))
    Swag.require(cache.preferredReady and not cache.complete and cache.families.count <= 4)
    let again = cache.find('A'_rune, .BoldItalic)
    Swag.require(again == face and cache.faces.count == 1 and not cache.complete)
    let arrow = cache.find('\u2192'_rune, .BoldItalic)
    Swag.require(arrow != null and arrow.face.hasChar('\u2192'_rune) and not cache.complete)
}

// An exhausted preferred list still falls through to all installed fonts exactly once.
#[Swag.TestTag("integration.fonts")]
#test
{
    // This case is about the installed fonts themselves, which a test run otherwise never sees.
    FontFamily.setSystemFontAccess(true)
    defer FontFamily.setSystemFontAccess(false)

    var cache: SystemFontFallbackCache
    cache.preferredReady = true
    let face = cache.find('A'_rune, .Regular)
    Swag.require(face != null and face.face.hasChar('A'_rune) and cache.complete)
    let count = cache.families.count
    let again = cache.find('A'_rune, .Regular)
    Swag.require(again == face and cache.families.count == count)
}
