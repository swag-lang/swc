#global if #command == Swag.CompilerCommand.Test
using Swag, Core

#test
{
    let image = renderCpu(&renderSvgParityScene)
    assertImage(image, RenderSvgWidth, RenderSvgHeight, .BGRA8)

    // Outside every shape, and inside the hole of the last path: transparent, and white.
    let white = Color.fromArgb(0'u8, 255'u8, 255'u8, 255'u8)
    assertPixel(image, 2, 2, white)
    assertPixel(image, 27, 48, white)

    // Flat interiors: the rounded rect, the ring around the hole, and the stroke of the
    // path that has no fill at all.
    assertSvgPixel(&image, 16, 16, Color.fromArgb(255'u8, 0x2E'u8, 0x86'u8, 0xDE'u8))
    assertSvgPixel(&image, 14, 41, Color.fromArgb(255'u8, 0x06'u8, 0xD6'u8, 0xA0'u8))
    assertSvgPixel(&image, 70, 8, Color.fromArgb(255'u8, 0xFF'u8, 0xD1'u8, 0x66'u8))

    // The half-transparent circle over the rounded rect resolves to a blend of the two,
    // opaque because the rect below it is.
    let blended = image.pixelColor(38, 24)
    Swag.assert(blended.a == 255)
    Swag.assert(blended.r > 0x2E and blended.r < 0xEF)
    Swag.assert(blended.b > 0x6F and blended.b < 0xDE)
}
#test
{
    var expected = Image.create(2, 1, .BGRA8)
    expected.clear()
    var actual = expected

    let pixels = actual.pixels.storage()
    pixels[2] = 4
    Testing.assertImagesNear(&expected, &actual, "render.parity.tolerance.delta", {maxChannelDelta: 4})

    pixels[2] = 255
    Testing.assertImagesNear(&expected, &actual, "render.parity.tolerance.outlier", {maxDifferentPixels: 1})
}
#test
{
    var storage: Array'u8
    let picture = makeRenderPlanarPicture(&storage)
    let image   = renderCpu(&renderPlanarParityScene)
    assertPlanarCornersUpright(&image, &picture)
}
#test
{
    let expected = renderCpu(&renderClipRegionParityScene)
    let blue     = Color.fromArgb(Argb.DodgerBlue)
    let white    = Color.fromArgb(Argb.White)
    Swag.assert(expected.pixelColor(144, 64) == blue)
    Swag.assert(expected.pixelColor(48, 64) != blue and expected.pixelColor(48, 64) != white)
    Swag.assert(expected.pixelColor(96, 8) == white)

    // The circle's edge, where it runs diagonally, is a ramp rather than a staircase.
    Swag.assert(hasSoftEdge(&expected, 172, 36, blue))
}
#test
{
    let expected = renderCpu(&renderOpaqueBackdropParityScene)
    for idx in ArtisticBlendModes.count
    {
        let x       = cast(s32, idx) * 12 + 6
        let scratch = expected.pixelColor(x, 12)
        let opaque  = expected.pixelColor(x, 36)
        Swag.assert(Math.abs(cast(s32, scratch.r) - cast(s32, opaque.r)) <= 1)
        Swag.assert(Math.abs(cast(s32, scratch.g) - cast(s32, opaque.g)) <= 1)
        Swag.assert(Math.abs(cast(s32, scratch.b) - cast(s32, opaque.b)) <= 1)
    }
}
#test
{
    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    renderer.init()
    let font   = makeRenderParityFont(renderer, 40, .Msdf)
    var target = renderer.createRenderTarget(RenderTextWidth, RenderTextHeight)
    defer renderer.deleteRenderTarget(&target)

    var effect: TextEffect
    effect.outlineColor = Color.fromArgb(Argb.Zero)
    effect.glowColor    = Color.fromArgb(150'u8, Argb.Gold)
    effect.glowInner    = 0.04
    effect.glowOuter    = 0.42
    effect.glowPower    = 1.4
    var painter = Painter.create(renderer)
    painter.begin()
    painter.bindRenderTarget(&target)
    painter.setColorMaskFull()
    painter.setBlendingMode(.Copy)
    painter.clear(Color.fromArgb(Argb.Zero))
    painter.drawString(12, 82, "Outline + glow", font, Color.fromArgb(Argb.Zero), effect)
    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)

    let image = renderer.readRenderTarget(&target, 0, 0, RenderTextWidth, RenderTextHeight)
    var fractional: u32
    for y in image.height
    {
        for x in image.width
        {
            let color = image.pixelColor(x, y)
            if color.a == 0 do
                continue
            Swag.assert(color.r == effect.glowColor.r and
                        color.g == effect.glowColor.g and
                        color.b == effect.glowColor.b)
            Swag.assert(color.a <= effect.glowColor.a)
            if color.a < effect.glowColor.a do
                fractional += 1
        }
    }

    Swag.assert(fractional != 0)
}
