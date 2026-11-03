#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Swag

// A cold ordinary fallback must not enumerate every installed family before trying Segoe UI.
#test
{
    var cache: SystemFontFallbackCache
    for c in [0'rune, '\t'rune, '\n'rune, '\r'rune, '\u007F'rune, '\u0085'rune, '\u009F'rune]
    {
        let control = cache.find(c, .Italic)
        Swag.assert(not control and not cache.preferredReady and not cache.complete and cache.faces.count == 0)
    }

    let invalid = cache.find('\U0010FFFF'rune, .Regular)
    Swag.assert(not invalid and not cache.preferredReady and not cache.complete)
    let face = cache.find('A'rune, .BoldItalic)
    Swag.assert(face != null and face.face.hasChar('A'rune))
    Swag.assert(cache.preferredReady and not cache.complete and cache.families.count <= 4)
    let again = cache.find('A'rune, .BoldItalic)
    Swag.assert(again == face and cache.faces.count == 1 and not cache.complete)
    let arrow = cache.find('\u2192'rune, .BoldItalic)
    Swag.assert(arrow != null and arrow.face.hasChar('\u2192'rune) and not cache.complete)
}

// An exhausted preferred list still falls through to all installed fonts exactly once.
#test
{
    var cache: SystemFontFallbackCache
    cache.preferredReady = true
    let face = cache.find('A'rune, .Regular)
    Swag.assert(face != null and face.face.hasChar('A'rune) and cache.complete)
    let count = cache.families.count
    let again = cache.find('A'rune, .Regular)
    Swag.assert(again == face and cache.families.count == count)
}
