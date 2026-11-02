#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Windows
#global private

using Core

// Requires an installed face covering the arrow used by the limited primary fixture.
#[Swag.TestTag("integration.fonts")]
#test
{
    var cache: FontCache
    let font  = cache.createFont(expect fallbackTestFace(false), 19, .Bitmap, true, true)
    let arrow = font.resolveRune('\u2192'rune)
    Swag.assert(arrow != font and arrow.glyphIndex('\u2192'rune) != 0)
    Swag.assert(arrow.cache.typeFace.isBold() or arrow.cache.typeFace.forceBold or arrow.forceBold)
    Swag.assert(arrow.cache.typeFace.isItalic() or arrow.cache.typeFace.forceItalic or arrow.forceItalic)
}
