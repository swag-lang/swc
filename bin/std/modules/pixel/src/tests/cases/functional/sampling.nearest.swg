#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A one-pixel checker enlarged by a ratio that puts some pixel centres exactly on a texel
// boundary. Each destination row and column must still read one texel row or column from end
// to end: the boundary is settled once, not per pixel by the rounding of the interpolation,
// which tore such an edge into teeth.
#test
{
    const SourceWidth  = 48
    const SourceHeight = 32
    const TargetWidth  = 160
    const TargetHeight = 112

    var source = Image.create(SourceWidth, SourceHeight, .BGRA8)
    for y in source.height
    {
        for x in source.width
        {
            let level = (x + y) & 1 ? 235'u8 : 20'u8
            let pixel = source.pixels.storage() + cast(u64, (y * source.rowStride + x * 4))
            pixel[0] = level
            pixel[1] = level
            pixel[2] = level
            pixel[3] = 255
        }
    }

    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    renderer.init()
    var texture = renderer.addImage(source)
    defer renderer.removeTexture(&texture)
    var target = renderer.createRenderTarget(TargetWidth, TargetHeight)
    defer renderer.deleteRenderTarget(&target)

    var painter = Painter.create(renderer)
    painter.begin()
    painter.bindRenderTarget(&target)
    painter.setColorMaskFull()
    painter.setBlendingMode(.Copy)
    painter.clear(Color.fromArgb(Argb.Black))
    painter.setInterpolationMode(.Pixel)

    // Snapped to 130 by 86 device pixels: rows 23 and 66 land exactly between two texel rows.
    painter.drawTexture({3, 2, SourceWidth * 2.7, SourceHeight * 2.7}, texture)
    painter.unbindRenderTarget()
    painter.end()
    expect renderer.draw(&painter)
    let image = renderer.readRenderTarget(&target, 0, 0, TargetWidth, TargetHeight)

    // On a checker, a row is the row above it or its exact inverse; a torn row is neither.
    for y in 3 until 88
    {
        let same     = image.pixelColor(3, y).r == image.pixelColor(3, y - 1).r
        var coherent = true
        for x in 3 until 133
        {
            if (image.pixelColor(x, y).r == image.pixelColor(x, y - 1).r) != same do
                coherent = false
        }

        Swag.require(coherent, "a destination row mixes two texel rows")
    }

    for x in 4 until 133
    {
        let same     = image.pixelColor(x, 2).r == image.pixelColor(x - 1, 2).r
        var coherent = true
        for y in 2 until 88
        {
            if (image.pixelColor(x, y).r == image.pixelColor(x - 1, y).r) != same do
                coherent = false
        }

        Swag.require(coherent, "a destination column mixes two texel columns")
    }
}
