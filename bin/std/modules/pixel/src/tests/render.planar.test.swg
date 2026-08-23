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
func expectedPlanarColor(luma, chromaB, chromaR: u8)->Color
{
    let c = Math.max(cast(s32) luma - 16, 0) * 298
    let d = cast(s32) chromaB - 128
    let e = cast(s32) chromaR - 128
    return Color.fromRgb(cast(u8) Math.clamp((c + 409 * e + 128) >> 8, 0, 255),
                         cast(u8) Math.clamp((c - 100 * d - 208 * e + 128) >> 8, 0, 255),
                         cast(u8) Math.clamp((c + 516 * d + 128) >> 8, 0, 255))
}

// A planar format is a pixel format like any other: it names a channel set and a storage class,
// and an image refuses it because an image is one tightly packed row.
#test
{
    @assert(PixelFormat.RGB8.isPacked())
    @assert(PixelFormat.BGRA8.isPacked())
    @assert(!PixelFormat.Yuv420.isPacked())
    @assert(PixelFormat.Yuv420.channels() == 3)
    @assert(PixelFormat.Yuv420.bitDepth() == 8)
    @assert(!PixelFormat.Yuv420.hasAlpha())
    @assert(PixelFormat.Yuv420.bitsPerPixel() == 12)
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
    @assert(texture.isValid() and texture.pixelFormat == .Yuv420)
    @assert(texture.width == 8 and texture.height == 6)

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
            @assert(Math.abs(cast(s32) actual.r - cast(s32) expected.r) <= 1)
            @assert(Math.abs(cast(s32) actual.g - cast(s32) expected.g) <= 1)
            @assert(Math.abs(cast(s32) actual.b - cast(s32) expected.b) <= 1)
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
            @assert(image.pixelColor(x, y).r >= 250)
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
    @assert(image.pixelColor(0, 0).r >= 250)
    @assert(image.pixelColor(3, 3).r >= 250)
}
