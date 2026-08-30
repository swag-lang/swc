#global if #command == Swag.CompilerCommand.Test

using Swag, Core

// Builds a planar 4:2:0 picture of one flat colour, in the studio range a codec produces.
func flatPlanarPicture(storage: *Array'u8, width, height: s32, luma, chromaB, chromaR: u8)->Yuv420View
{
    let chromaWidth  = cast(u64) ((width + 1) / 2)
    let chromaHeight = cast(u64) ((height + 1) / 2)
    let lumaSize     = cast(u64) width * cast(u64) height
    let chromaSize   = chromaWidth * chromaHeight

    storage.resize(lumaSize + chromaSize * 2)
    Memory.set(storage.buffer!, luma, lumaSize)
    Memory.set(storage.buffer! + lumaSize, chromaB, chromaSize)
    Memory.set(storage.buffer! + lumaSize + chromaSize, chromaR, chromaSize)

    return {
        luma: storage.buffer!,
        chromaB: storage.buffer! + lumaSize,
        chromaR: storage.buffer! + lumaSize + chromaSize,
        lumaStride: cast(u64) width,
        chromaStride: chromaWidth,
        width: width,
        height: height}
}

// Returns what the conversion answers for one sample, which is what a drawn picture must show.
func expectedPlanarColor(luma, chromaB, chromaR: u8, matrix = YuvMatrix.Bt601, studioRange = true)->Color
{
    let c = Math.max(cast(s32) luma - (studioRange ? 16 : 0), 0) * (studioRange ? 298 : 256)
    let d = cast(s32) chromaB - 128
    let e = cast(s32) chromaR - 128
    var redCr, greenCb, greenCr, blueCb: s32
    switch #complete matrix
    {
    case .Bt601:
        if studioRange
        {
            redCr   = 409
            greenCb = -100
            greenCr = -208
            blueCb  = 516
        }
        else
        {
            redCr   = 359
            greenCb = -88
            greenCr = -183
            blueCb  = 454
        }

    case .Bt709:
        if studioRange
        {
            redCr   = 459
            greenCb = -55
            greenCr = -136
            blueCb  = 541
        }
        else
        {
            redCr   = 403
            greenCb = -48
            greenCr = -120
            blueCb  = 475
        }

    case .Bt2020:
        if studioRange
        {
            redCr   = 430
            greenCb = -48
            greenCr = -167
            blueCb  = 548
        }
        else
        {
            redCr   = 377
            greenCb = -42
            greenCr = -146
            blueCb  = 483
        }
    }

    return Color.fromRgb(cast(u8) Math.clamp((c + redCr * e + 128) >> 8, 0, 255),
                         cast(u8) Math.clamp((c + greenCb * d + greenCr * e + 128) >> 8, 0, 255),
                         cast(u8) Math.clamp((c + blueCb * d + 128) >> 8, 0, 255))
}

// A planar format is a pixel format like any other: it names a channel set and a storage class,
// and an image refuses it because an image is one tightly packed row.
#test
{
    Swag.assert(PixelFormat.RGB8.isPacked())
    Swag.assert(PixelFormat.BGRA8.isPacked())
    Swag.assert(!PixelFormat.Yuv420.isPacked())
    Swag.assert(PixelFormat.Yuv420.channels() == 3)
    Swag.assert(PixelFormat.Yuv420.bitDepth() == 8)
    Swag.assert(!PixelFormat.Yuv420.hasAlpha())
    Swag.assert(PixelFormat.Yuv420.bitsPerPixel() == 12)
}

// Matrix and range metadata select distinct conversions, including the sixteen-pixel SIMD path.
#test
{
    const Luma    = 100'u8
    const ChromaB = 90'u8
    const ChromaR = 200'u8

    var storage: Array'u8
    var source = flatPlanarPicture(&storage, 16, 2, Luma, ChromaB, ChromaR)
    source.matrix = .Bt709

    var image: Image
    source.convertToRgb(&image)
    let studio = expectedPlanarColor(Luma, ChromaB, ChromaR, .Bt709, true)
    Swag.assert(image.pixelColor(0, 0) == studio and image.pixelColor(15, 1) == studio)

    source.studioRange = false
    source.convertToRgb(&image)
    let full = expectedPlanarColor(Luma, ChromaB, ChromaR, .Bt709, false)
    Swag.assert(image.pixelColor(0, 0) == full and image.pixelColor(15, 1) == full)
    Swag.assert(full != studio)
}

// A picture handed over as planes travels as an ordinary texture and reaches the surface as the
// colour the conversion defines. The backend without shaders converts when it is uploaded.
#test
{
    const Luma    = 128'u8
    const ChromaB = 90'u8
    const ChromaR = 200'u8

    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    renderer.init()

    var storage: Array'u8
    let source  = flatPlanarPicture(&storage, 8, 6, Luma, ChromaB, ChromaR)
    var texture = renderer.addImage(&source)
    defer renderer.removeTexture(&texture)
    Swag.assert(texture.isValid() and texture.pixelFormat == .Yuv420)
    Swag.assert(texture.width == 8 and texture.height == 6)

    var target = renderer.createRenderTarget(8, 6)
    defer renderer.deleteRenderTarget(&target)

    var painter = Painter.create(renderer)
    painter.begin()
    painter.bindRenderTarget(&target)
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Zero))
    painter.setBlendingMode(.Copy)
    painter.drawTexture({0, 0, 8, 6}, texture)
    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)

    let image    = renderer.readRenderTarget(&target, 0, 0, 8, 6)
    let expected = expectedPlanarColor(Luma, ChromaB, ChromaR)
    for y in 6's32
    {
        for x in 8's32
        {
            let actual = image.pixelColor(x, y)
            Swag.assert(Math.abs(cast(s32) actual.r - cast(s32) expected.r) <= 1)
            Swag.assert(Math.abs(cast(s32) actual.g - cast(s32) expected.g) <= 1)
            Swag.assert(Math.abs(cast(s32) actual.b - cast(s32) expected.b) <= 1)
        }
    }
}

// A picture whose rows carry padding is read from its visible window alone: the planes of a
// decoder are padded so prediction can read past the edges, and none of that may reach a surface.
#test
{
    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    renderer.init()

    // Four luma rows of eight bytes hold a four-wide picture followed by four bytes that must
    // never be seen.
    var luma: Array'u8
    luma.resize(4 * 8)
    for row in 4'u64
    {
        for x in 8'u64 do
            luma[row * 8 + x] = x < 4 ? 235 : 16
    }

    var chroma: Array'u8
    chroma.resize(2 * 4)
    for index in 8'u64 do
        chroma[index] = 128

    let view = Yuv420View{
        luma: luma.buffer!,
        chromaB: chroma.buffer!,
        chromaR: chroma.buffer!,
        lumaStride: 8,
        chromaStride: 2,
        width: 4,
        height: 4}

    var texture = renderer.addImage(&view)
    defer renderer.removeTexture(&texture)

    var target = renderer.createRenderTarget(4, 4)
    defer renderer.deleteRenderTarget(&target)

    var painter = Painter.create(renderer)
    painter.begin()
    painter.bindRenderTarget(&target)
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Zero))
    painter.setBlendingMode(.Copy)
    painter.drawTexture({0, 0, 4, 4}, texture)
    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)

    // Studio-range 235 is white; the padding would have shown as black.
    let image = renderer.readRenderTarget(&target, 0, 0, 4, 4)
    for y in 4's32
    {
        for x in 4's32 do
            Swag.assert(image.pixelColor(x, y).r >= 250)
    }
}

// A new picture replaces the one a texture holds, which is what a player does every frame.
#test
{
    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    renderer.init()

    var firstStorage: Array'u8
    let first   = flatPlanarPicture(&firstStorage, 4, 4, 16, 128, 128)
    var texture = renderer.addImage(&first)
    defer renderer.removeTexture(&texture)

    var secondStorage: Array'u8
    let second = flatPlanarPicture(&secondStorage, 4, 4, 235, 128, 128)
    renderer.updateTexture(texture, &second)

    var target = renderer.createRenderTarget(4, 4)
    defer renderer.deleteRenderTarget(&target)

    var painter = Painter.create(renderer)
    painter.begin()
    painter.bindRenderTarget(&target)
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(Argb.Zero))
    painter.setBlendingMode(.Copy)
    painter.drawTexture({0, 0, 4, 4}, texture)
    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)

    let image = renderer.readRenderTarget(&target, 0, 0, 4, 4)
    Swag.assert(image.pixelColor(0, 0).r >= 250)
    Swag.assert(image.pixelColor(3, 3).r >= 250)
}

// The OpenGL shader consumes the same BT.709 factors as the CPU conversion.
#test
{
    let expected = renderCpu(&renderPlanarParityScene)
    let image    = expect renderOgl("SWAG_PIXEL_YUV_MATRIX", "Pixel YUV matrix", RenderPlanarWidth, RenderPlanarHeight, &renderPlanarParityScene)
    Testing.assertImagesNear(&expected, &image, "render.planar.bt709.cpu-ogl", {maxChannelDelta: 4, maxDifferentPixels: 400})
}
