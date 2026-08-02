#global if #command == Swag.CompilerCommand.Test

using Swag, Core, Win32

private const RenderParityWidth  = 192
private const RenderParityHeight = 128
private const RenderTextWidth    = 360
private const RenderTextHeight   = 168
private const RenderLayerWidth   = 160
private const RenderLayerHeight  = 104

private alias RenderParityScene = func||(IRenderer)->Image

private func renderCpu(scene: RenderParityScene)->Image
{
    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    renderer.init()
    return scene(renderer)
}

private func renderOgl(className, title: string, width, height: s32, scene: RenderParityScene)->Image fail
{
    var window = try Env.createWindow({className: className, title: title, width: width, height: height})

    var ogl:      RenderOgl
    let renderer: IRenderer = &ogl
    var context             = try renderer.createContext(cast(#null const *void) window.nativeHandle, width, height)
    defer renderer.deleteContext(&context)

    renderer.setCurrentContext(context)
    renderer.init()
    renderer.begin(context)
    defer renderer.end()
    return scene(renderer)
}

private func makeRenderParityTexture(renderer: IRenderer)->Texture
{
    var image             = Image.create(4, 4, .BGRA8)
    let colors: [4] Color = [Color.fromArgb(Argb.Crimson),
                                    Color.fromArgb(Argb.Gold),
                                    Color.fromArgb(Argb.DodgerBlue),
                                    Color.fromArgb(Argb.LimeGreen)]

    for [y] in image.height
    {
        for [x] in image.width
        {
            let color = colors[cast(u64) ((x + y) & 3)]
            let row   = image.height - y - 1
            let pixel = (notnull image.pixels.buffer) + cast(u64) (row * image.rowStride + x * image.bytesPerPixel)
            pixel[0] = color.b
            pixel[1] = color.g
            pixel[2] = color.r
            pixel[3] = color.a
        }
    }

    return renderer.addImage(image)
}

// Records the portable painter surface once so both backends execute the exact same operations.
private func renderParityScene(renderer: IRenderer)->Image
{
    var texture = makeRenderParityTexture(renderer)
    defer renderer.removeTexture(&texture)
    var target = renderer.createRenderTarget(RenderParityWidth, RenderParityHeight)
    defer renderer.deleteRenderTarget(&target)

    var painter = Painter.create(renderer)
    painter.begin()
    painter.bindRenderTarget(&target)
    painter.setColorMaskFull()
    painter.setBlendingMode(.Copy)
    painter.clear(Color.fromArgb(255'u8, 18'u8, 22'u8, 30'u8))

    // Geometry and screen-space antialiasing.
    painter.setBlendingMode(.Alpha)
    painter.setAntialiased(true)
    painter.fillCircle(18, 18, 12, Color.fromArgb(220'u8, 239'u8, 71'u8, 111'u8))
    painter.drawRoundRect({34, 6, 34, 24}, 7, 7, Color.fromArgb(Argb.White), 3)
    painter.setAntialiased(false)
    painter.fillEllipse({74, 6, 34, 24}, Color.fromArgb(255'u8, 72'u8, 149'u8, 239'u8))
    painter.setAntialiased(true)

    painter.pushTransform()
    painter.rotateTransform(12.0'deg, 131, 18)
    painter.fillRect({114, 8, 34, 20}, Color.fromArgb(210'u8, 255'u8, 184'u8, 77'u8))
    painter.popTransform()

    // Every built-in brush family.
    let linear = Brush.createLinearGradient(6, 42, 58, 42, Color.fromArgb(Argb.Crimson), Color.fromArgb(Argb.DodgerBlue))
    painter.fillRect({6, 38, 52, 18}, linear)

    let radial = Brush.createRadialGradient(84, 47, 18, Color.fromArgb(Argb.White), Color.fromArgb(Argb.DarkViolet))
    painter.fillCircle(84, 47, 18, radial)

    let sweep = Brush.createSweepGradient(126, 47, Color.fromArgb(Argb.Gold), Color.fromArgb(Argb.DodgerBlue))
    painter.fillCircle(126, 47, 18, sweep)

    let hatch = Brush.createHatch(.DiagonalCross, Color.fromArgb(Argb.LimeGreen))
    painter.fillRect({150, 36, 34, 22}, hatch)

    // Texture sampling modes and source-rectangle handling.
    painter.setInterpolationMode(.Pixel)
    painter.drawTexture({6, 68, 34, 24}, texture)
    painter.setInterpolationMode(.Linear)
    painter.drawTexture({46, 68, 34, 24}, texture)
    painter.drawTexture({86, 68, 34, 24}, {1, 1, 2, 2}, texture)
    let tiled = Brush.createTiled(texture)
    painter.fillRect({126, 68, 58, 24}, tiled)

    // Scissor and stencil clipping must agree in surface coordinates.
    painter.setInterpolationMode(.Pixel)
    painter.setClippingRect({6, 100, 34, 20})
    painter.fillCircle(23, 110, 20, Color.fromArgb(Argb.OrangeRed))
    painter.resetClippingRect()

    painter.startClippingRegion()
    painter.fillCircle(62, 110, 14, Color.fromArgb(Argb.White))
    painter.endClippingRegion()
    painter.fillRect({44, 96, 36, 28}, Color.fromArgb(Argb.MediumPurple))
    painter.resetClippingRegion()

    // Channel masking followed by all framebuffer blend equations.
    painter.setBlendingMode(.Copy)
    painter.fillRect({86, 98, 18, 22}, Color.fromArgb(255'u8, 30'u8, 80'u8, 140'u8))
    painter.setColorMask(true, false, false, true)
    painter.fillRect({90, 102, 18, 14}, Color.fromArgb(160'u8, 240'u8, 20'u8, 20'u8))
    painter.setColorMaskFull()

    let modes: [7] BlendingMode = [.Copy, .Alpha, .Add, .Sub, .SubDst, .Min, .Max]
    for mode, [idx] in modes
    {
        let x = 114 + cast(f32) idx * 11
        painter.setBlendingMode(.Copy)
        painter.fillRect({x, 100, 9, 18}, Color.fromArgb(190'u8, 35'u8, 90'u8, 145'u8))
        painter.setBlendingMode(mode)
        painter.fillRect({x + 3, 104, 6, 10}, Color.fromArgb(135'u8, 210'u8, 70'u8, 25'u8))
    }

    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)

    let result = renderer.readRenderTarget(&target, 0, 0, RenderParityWidth, RenderParityHeight)
    return result
}

private func makeRenderParityFont(renderer: IRenderer, size: u32, mode: FontRenderMode)->*Font
{
    let face = notnull expect loadTestTypeFace(getTestDataPath("segoeui.ttf"))
    return renderer.fontCache().createFont(face, size, mode)
}

// Exercises bitmap text and every renderer-independent MTSDF effect through one atlas.
private func renderTextParityScene(renderer: IRenderer)->Image
{
    let bitmap = makeRenderParityFont(renderer, 20, .Bitmap)
    let msdf   = makeRenderParityFont(renderer, 40, .Msdf)
    var target = renderer.createRenderTarget(RenderTextWidth, RenderTextHeight)
    defer renderer.deleteRenderTarget(&target)

    var outlineGlow: TextEffect
    outlineGlow.outlineWidth = 0.16
    outlineGlow.outlineColor = Color.fromArgb(Argb.DodgerBlue)
    outlineGlow.glowColor    = Color.fromArgb(150'u8, Argb.Gold)
    outlineGlow.glowInner    = 0.04
    outlineGlow.glowOuter    = 0.42
    outlineGlow.glowPower    = 1.4

    var face: TextEffect
    face.faceDilate = 0.08
    face.softness   = 0.10
    face.bevel      = 0.65

    var shadow: TextEffect
    shadow.shadowColor    = Color.fromArgb(150'u8, Argb.Black)
    shadow.shadowOffset   = {3, 3}
    shadow.shadowDilate   = 0.08
    shadow.shadowSoftness = 0.32

    var painter = Painter.create(renderer)
    painter.begin()
    painter.bindRenderTarget(&target)
    painter.setColorMaskFull()
    painter.setBlendingMode(.Copy)
    painter.clear(Color.fromArgb(Argb.White))
    painter.setColorMaskColor()
    painter.setBlendingMode(.Alpha)
    painter.drawString(12, 8, "Bitmap Aa09", bitmap, Color.fromArgb(Argb.MidnightBlue))
    painter.drawString(12, 38, "Plain MSDF", msdf, Color.fromArgb(Argb.Crimson))
    painter.drawString(12, 82, "Outline + glow", msdf, Color.fromArgb(Argb.MidnightBlue), outlineGlow)
    painter.drawString(12, 126, "Bevel", msdf, Color.fromArgb(Argb.DarkOrange), face)
    painter.drawString(196, 126, "Shadow", msdf, Color.fromArgb(Argb.SeaGreen), shadow)
    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)

    let result = renderer.readRenderTarget(&target, 0, 0, RenderTextWidth, RenderTextHeight)
    return result
}

// Runs nested targets, paint-alpha replay, supersampling resolve and both blur axes.
private func renderLayerParityScene(renderer: IRenderer)->Image
{
    var target = renderer.createRenderTarget(RenderLayerWidth, RenderLayerHeight)
    defer renderer.deleteRenderTarget(&target)
    var painter = Painter.create(renderer)
    var layer: Layer

    painter.begin()
    painter.bindRenderTarget(&target)
    painter.setColorMaskFull()
    painter.setBlendingMode(.Copy)
    painter.clear(Color.fromArgb(255'u8, 24'u8, 30'u8, 42'u8))

    layer.begin(&painter, {width: 72, height: 48, renderScale: 2})
    painter.fillRoundRect({7, 7, 58, 34}, 9, 9, Brush.createLinearGradient(7, 7, 65, 41, Color.fromArgb(Argb.DeepPink), Color.fromArgb(Argb.DodgerBlue)))
    painter.fillCircle(36, 24, 10, Color.fromArgb(190'u8, Argb.White))
    layer.end()
    layer.draw({dstRect: {42, 26, 72, 48},
                shadow: {enabled: true, margin: 10, radius: 4, offsetX: 5, offsetY: 6,
                         color: Color.fromArgb(170'u8, Argb.Black)}})

    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)

    let result = renderer.readRenderTarget(&target, 0, 0, RenderLayerWidth, RenderLayerHeight)
    return result
}

// Image comparisons expose separate limits for small channel drift and bounded outlier pixels.
#test
{
    var expected = Image.create(2, 1, .BGRA8)
    expected.clear()
    var actual = expected

    let pixels = notnull actual.pixels.buffer
    pixels[2] = 4
    Testing.assertImagesNear(&expected, &actual, "render.parity.tolerance.delta", {maxChannelDelta: 4})

    pixels[2] = 255
    Testing.assertImagesNear(&expected, &actual, "render.parity.tolerance.outlier", {maxDifferentPixels: 1})
}

// The deterministic CPU backend is the exact, reviewable reference for portable painter output.
#test
{
    let image = renderCpu(&renderParityScene)
    Testing.assertImageGolden(&image, "render.parity.portable")
}

// OpenGL must stay visually equivalent to the CPU reference. Raster-edge differences are
// bounded explicitly; flat fills, texture interiors and state transitions still compare exactly.
#test
{
    let expected = renderCpu(&renderParityScene)
    let image    = expect renderOgl("SWAG_PIXEL_RENDER_PARITY", "Pixel renderer parity", RenderParityWidth, RenderParityHeight, &renderParityScene)
    Testing.assertImagesNear(&expected, &image, "render.parity.cpu-ogl", {maxChannelDelta: 3, maxDifferentPixels: 512})
}

// Text goldens cover bitmap sampling plus the complete built-in MTSDF effects path.
#test
{
    let image = renderCpu(&renderTextParityScene)
    Testing.assertImageGolden(&image, "render.parity.text")
}

// CPU and OpenGL implement the same built-in text programs, including MTSDF effects.
#test
{
    let expected = renderCpu(&renderTextParityScene)
    let image    = expect renderOgl("SWAG_PIXEL_TEXT_PARITY", "Pixel text parity", RenderTextWidth, RenderTextHeight, &renderTextParityScene)
    Testing.assertImagesNear(&expected, &image, "render.parity.text.cpu-ogl", {maxChannelDelta: 5, maxDifferentPixels: 1500})
}

// The CPU backend makes composite layer output deterministic and reviewable.
#test
{
    let image = renderCpu(&renderLayerParityScene)
    Testing.assertImageGolden(&image, "render.parity.layer")
}

// Layer resolve, blur, paint-alpha replay and pooled targets agree across both backends.
#test
{
    let expected = renderCpu(&renderLayerParityScene)
    let image    = expect renderOgl("SWAG_PIXEL_LAYER_PARITY", "Pixel layer parity", RenderLayerWidth, RenderLayerHeight, &renderLayerParityScene)
    Testing.assertImagesNear(&expected, &image, "render.parity.layer.cpu-ogl", {maxChannelDelta: 6, maxDifferentPixels: 1500})
}
