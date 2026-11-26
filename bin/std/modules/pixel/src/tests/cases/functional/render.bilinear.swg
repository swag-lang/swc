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
    expect renderer.draw(&painter)

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
            Swag.require(actual == expected, Format.toString("x=% y=% actual=% expected=%", x, y, actual.argb, expected.argb))
        }
    }
}

// The scanline sampler uses device pixel centers on both axes, including mirrored draws.
#test
{
    const Width          = 128
    const Height         = 64
    const Bytes: [16] u8 = [229, 31, 149, 0, 17, 181, 83, 127,
                            255, 3, 5, 255, 64, 192, 0, 1]
    let source = Image.create(2, 2, .BGRA8, Bytes)
    var cpu: RenderCpu
    cpu.begin(Width, Height)
    let renderer: IRenderer = &cpu
    defer renderer.end()
    var texture = renderer.addImage(source)
    defer renderer.removeTexture(&texture)

    var painter = Painter.createScanline(&cpu)
    painter.begin()
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.White))
    painter.setColorMaskColor()
    painter.setAntialiased(false)
    painter.setInterpolationMode(.Linear)
    painter.setTransform(Math.Transform2{-Width, 0, 0, -Height, Width, Height})
    painter.drawTexture({0, 0, 1, 1}, texture)
    painter.end()
    expect renderer.draw(&painter)
    let image = cpu.surfaceImage()

    func overWhite(channel, alpha: u8)->u8
    {
        return cast(u8, (cast(u32, channel) * alpha + 255 * (255'u32 - alpha)) / 255)
    }

    for y in Height
    {
        let py = (cast(f32, Height - y) - 0.5) / (Height / 2) - 0.5
        let iy = cast(s32, Math.floor(py))
        let wy = cast(u32, (py - Math.floor(py)) * 65536)
        let y0 = Math.clamp(iy, 0, 1)
        let y1 = Math.clamp(iy + 1, 0, 1)
        for x in Width
        {
            let px       = (cast(f32, Width - x) - 0.5) / (Width / 2) - 0.5
            let ix       = cast(s32, Math.floor(px))
            let wx       = cast(u32, (px - Math.floor(px)) * 65536)
            let x0       = Math.clamp(ix, 0, 1)
            let x1       = Math.clamp(ix + 1, 0, 1)
            let upper    = blend(source.pixelColor(x0, y0), source.pixelColor(x1, y0), wx)
            let lower    = blend(source.pixelColor(x0, y1), source.pixelColor(x1, y1), wx)
            let sampled  = blend(upper, lower, wy)
            let expected = Color.fromArgb(255'u8, overWhite(sampled.r, sampled.a), overWhite(sampled.g, sampled.a), overWhite(sampled.b, sampled.a))
            Swag.require(image.pixelColor(cast(s32, x), cast(s32, y)) == expected)
        }
    }
}

// Every fixed-point vertical weight preserves the scalar interpolation of packed channels.
#test
{
    const A = [0'u8, 255, 0, 255, 1, 254, 31, 224, 96, 89, 100, 71, 125, 11, 209, 37]
    const B = [255'u8, 0, 0, 255, 254, 1, 224, 31, 89, 96, 71, 100, 142, 58, 69, 14]
    let a = cast(Math.Simd.U8x16, A)
    let b = cast(Math.Simd.U8x16, B)
    for weight in 65_537'u32
    {
        let packed = Math.Simd.splat(cast #bit(s16, cast(u16, weight)))
        let result = RenderCpu.lerpBgra8x4(a, b, packed, weight >= 32768)
        for channel in 16 do
            Swag.require(result[channel] == cast(u8, (cast(u32, A[channel]) * (65536 - weight) + cast(u32, B[channel]) * weight) >> 16))
    }
}


// The downscale sampler gathers four neighboring pairs and leaves a scalar tail.
#test
{
    const Width        = 67
    const Height       = 65
    const SourceWidth  = 131
    const SourceHeight = 113
    const Formats      = [PixelFormat.BGRA8, .RGBA8]
    for format in Formats
    {
        var source = Image.create(SourceWidth, SourceHeight, format)
        for i in source.pixels.count do
            source.pixels[i] = cast(u8, (17 * i + i / 503) & 255)

        var cpu: RenderCpu
        cpu.begin(Width, Height)
        let renderer: IRenderer = &cpu
        defer renderer.end()
        var texture = renderer.addImage(source)
        defer renderer.removeTexture(&texture)

        var painter = Painter.createScanline(&cpu)
        painter.begin()
        painter.setColorMaskFull()
        painter.clear(Color.fromArgb(Argb.White))
        painter.setColorMaskColor()
        painter.setAntialiased(false)
        painter.setInterpolationMode(.Linear)
        painter.setTransform(Math.Transform2{-Width, 0, 0, -Height, Width, Height})
        painter.drawTexture({0, 0, 1, 1}, texture)
        painter.end()
        expect renderer.draw(&painter)
        let image = cpu.surfaceImage()

        func overWhite(channel, alpha: u8)->u8
        {
            return cast(u8, (cast(u32, channel) * alpha + 255 * (255'u32 - alpha)) / 255)
        }

        for y in Height
        {
            let v  = 1.0 - (cast(f32, y) + 0.5 - Height) / -Height
            let py = (1.0 - v) * SourceHeight - 0.5
            let iy = cast(s32, Math.floor(py))
            let wy = cast(u32, (py - Math.floor(py)) * 65536)
            for x in Width
            {
                let px       = (cast(f32, Width - x) - 0.5) / Width * SourceWidth - 0.5
                let ix       = cast(s32, Math.floor(px))
                let wx       = cast(u32, (px - Math.floor(px)) * 65536)
                let upper    = blend(source.pixelColor(ix, iy), source.pixelColor(ix + 1, iy), wx)
                let lower    = blend(source.pixelColor(ix, iy + 1), source.pixelColor(ix + 1, iy + 1), wx)
                let sampled  = blend(upper, lower, wy)
                let expected = Color.fromArgb(255'u8, overWhite(sampled.r, sampled.a), overWhite(sampled.g, sampled.a), overWhite(sampled.b, sampled.a))
                Swag.require(image.pixelColor(cast(s32, x), cast(s32, y)) == expected)
            }
        }
    }
}
