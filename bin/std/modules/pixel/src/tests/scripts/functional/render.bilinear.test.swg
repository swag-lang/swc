#global if #command == Swag.CompilerCommand.Test
#global private

using Core

func blend(first, second: Color, weight: u32)->Color
{
    func channel(a, b: u8, weight: u32)->u8 => cast(u8, (cast(u32, a) * (65536 - weight) + cast(u32, b) * weight) >> 16)
    return Color.fromArgb(channel(first.a, second.a, weight),
                          channel(first.r, second.r, weight),
                          channel(first.g, second.g, weight),
                          channel(first.b, second.b, weight))
}

// Texture interpolation quantizes horizontal and vertical lerps separately. Alpha and clamped
// edges follow the same byte-exact reference as RGB.
#test
{
    const Bytes: [16] u8 = [229, 31, 149, 0, 17, 181, 83, 127,
                            255, 3, 5, 255, 64, 192, 0, 1]
    let source = Image.create(2, 2, .BGRA8, Bytes)
    var cpu: RenderCpu
    cpu.begin(16, 16)
    let renderer: IRenderer = &cpu
    defer renderer.end()
    var texture = renderer.addImage(source)
    defer renderer.removeTexture(&texture)
    var painter: Painter
    painter.begin()
    painter.setColorMaskFull()
    painter.setAntialiased(false)
    painter.setInterpolationMode(.Linear)
    painter.setBlendingMode(.Copy)
    painter.drawTexture({0, 0, 16, 16}, texture)
    painter.end()
    renderer.draw(&painter)

    let image = cpu.surfaceImage()
    for y in 16
    {
        for x in 16
        {
            let px       = (cast(f32, x) + 0.5) / 8 - 0.5
            let py       = (cast(f32, y) + 0.5) / 8 - 0.5
            let ix       = cast(s32, Math.floor(px))
            let iy       = cast(s32, Math.floor(py))
            let wx       = cast(u32, (px - Math.floor(px)) * 65536)
            let wy       = cast(u32, (py - Math.floor(py)) * 65536)
            let x0       = Math.clamp(ix, 0, 1)
            let x1       = Math.clamp(ix + 1, 0, 1)
            let y0       = Math.clamp(iy, 0, 1)
            let y1       = Math.clamp(iy + 1, 0, 1)
            let top      = blend(source.pixelColor(x0, y0), source.pixelColor(x1, y0), wx)
            let bottom   = blend(source.pixelColor(x0, y1), source.pixelColor(x1, y1), wx)
            let actual   = image.pixelColor(cast(s32, x), cast(s32, y))
            let expected = blend(top, bottom, wy)
            Swag.assert(actual == expected, Format.toString("x=% y=% actual=% expected=%", x, y, actual.argb, expected.argb))
        }
    }
}
