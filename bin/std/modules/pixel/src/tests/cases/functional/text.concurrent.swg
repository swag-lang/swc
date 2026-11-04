#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

struct FontSample
{
    metrics: Array'f32
    pixels:  Array'u8
}

func renderFontSample(face: *TypeFace, size: u32, mode: FontRenderMode)->FontSample
{
    var result: #returntype
    var cache:  FontCache
    let font = cache.createFont(face, size, mode, true)
    result.metrics.add(font.height)
    for code in 33'u32 until 65
    {
        let glyph = font.getGlyphDesc(cast(rune, code))
        result.metrics.add([glyph.advanceX, glyph.advanceY, glyph.width, glyph.height, glyph.shiftX, glyph.shiftY])
    }

    for &atlas in font.cache.atlases do
        result.pixels.add(atlas.data.toSlice())
    return result
}

func sameFontSample(a, b: const *FontSample)->bool
{
    if a.metrics.count != b.metrics.count or a.pixels.count != b.pixels.count do
        return false
    for value, index in a.metrics where value != b.metrics[index] do
        return false
    for value, index in a.pixels where value != b.pixels[index] do
        return false
    return true
}

// Separate renderers share a face, but their glyph pixels and metrics must match serial rendering.
#test
{
    let face = expect TypeFace.load(getTestDataPath("segoeui.ttf"))
    for mode in [FontRenderMode.Bitmap, .Msdf]
    {
        let small = renderFontSample(face, 13, mode)
        let large = renderFontSample(face, 27, mode)
        var start, ready: u32
        var tasks:        [2] Swag.Task'bool
        var workers:      [2] Swag.Executor
        for &task, index in tasks
        {
            workers[index].start()
            task.submit(func|face, mode, index, small = &small, large = &large, start = &start, ready = &ready|()->bool
            {
                discard Swag.atomicAdd(ready, 1)
                while Swag.atomicLoad(start) == 0 do
                    Threading.Thread.yield()
                for 3
                {
                    let sample = renderFontSample(face, index == 0 ? 13 : 27, mode)
                    if not sameFontSample(&sample, index == 0 ? small : large) do
                        return false
                }

                return true
            },
                        executor: &workers[index])
        }

        while Swag.atomicLoad(&ready) != 2 do
            Threading.Thread.yield()
        discard Swag.atomicExchange(&start, 1)
        for &task in tasks do
            Swag.require(expect task.take())
    }
}
