#global if #command == Swag.CompilerCommand.Test
#global internal

using Swag, Core, Core.Math

// Command-stream goldens for text. Text is the only primitive that writes per-vertex texture
// coordinates, so these are the goldens that pin glyph atlas addressing. See
// [[Testing.assertGolden]].
//
// Glyph slots are packed in first-use order, so tests that shared a cache would record atlas
// coordinates depending on which one ran first. Each test owns its cache, which makes it
// reproducible whatever the test order without any arrangement between tests.
func makeTextTestFont(cache: *FontCache, size: u32, mode: FontRenderMode)->*Font
{
    let face = expect TypeFace.load(getTestDataPath("segoeui.ttf"))
    return cache.createFont(face, size, mode)
}
