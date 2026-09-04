#global if #command == Swag.CompilerCommand.Test

using Swag, Core

private const RenderParityWidth    = 192
private const RenderParityHeight   = 128
private const RenderTextWidth      = 360
private const RenderTextHeight     = 168
private const RenderLayerWidth     = 160
private const RenderLayerHeight    = 104
private const RenderSvgWidth       = 96
private const RenderSvgHeight      = 64
private const RenderSvgSupersample = 4'u8
private const RenderBlendWidth     = 180
private const RenderBlendHeight    = 48
const RenderPlanarWidth            = 64
const RenderPlanarHeight           = 48

private const ArtisticBlendModes: [15] BlendingMode = [.Multiply, .Screen, .Overlay, .Darken, .Lighten, .ColorDodge, .ColorBurn, .HardLight, .SoftLight, .Difference, .Exclusion, .Hue, .Saturation, .Color, .Luminosity]

// Opaque fill, translucent overlap, a stroke-only path and a hole: everything the
// alpha-preserving replay and the supersampling resolve have to agree on.
private const RenderSvgSource = "<svg width='96' height='64'>" ++
                                "<rect x='6' y='6' width='40' height='24' rx='7' fill='#2E86DE'/>" ++
                                "<circle cx='38' cy='24' r='14' fill='#EF476F' fill-opacity='0.5'/>" ++
                                "<path d='M 56 8 L 88 8 L 88 30 Z' fill='none' stroke='#FFD166' stroke-width='4'/>" ++
                                "<path d='M 10 38 h 34 v 20 h -34 Z M 18 52 h 18 v -8 h -18 Z' fill='#06D6A0'/>" ++
                                "<rect x='52' y='38' width='36' height='18' fill='url(#many)'/>" ++
                                "<defs><linearGradient id='many'>" ++
                                "<stop offset='0' stop-color='#ff0000'/><stop offset='.125' stop-color='#df0020'/>" ++
                                "<stop offset='.25' stop-color='#bf0040'/><stop offset='.375' stop-color='#9f0060'/>" ++
                                "<stop offset='.5' stop-color='#7f0080'/><stop offset='.625' stop-color='#60009f'/>" ++
                                "<stop offset='.75' stop-color='#4000bf'/><stop offset='.875' stop-color='#2000df'/>" ++
                                "<stop offset='1' stop-color='#0000ff'/></linearGradient></defs>" ++
                                "</svg>"

alias RenderParityScene = func||(IRenderer)->Image

func renderCpu(scene: RenderParityScene)->Image
{
    var cpu:      RenderCpu
    let renderer: IRenderer = &cpu
    renderer.init()
    return scene(renderer)
}

func renderOgl(className, title: string, width, height: s32, scene: RenderParityScene, needsAdvancedBlending = false)->Image fail
{
    var window = try Env.createWindow({identifier: className, title: title, width: width, height: height})

    // Realize the window before creating the GL context. A never-shown, never-pumped window has
    // no fully realized drawable, and its device context then yields a context whose framebuffer
    // reads back empty at random on this platform: the render target is filled correctly but the
    // read returns zeros. Realizing it and draining its queue is exactly what a real application
    // does before its first frame, and it makes the readback deterministic. It is realized off
    // the desktop: a test campaign is headless and must not flash a window at whoever runs it.
    try window.showOffScreen()
    discard Env.processWindowMessages()

    var ogl:      RenderOgl
    let renderer: IRenderer = &ogl
    var context             = try renderer.createContext(window.nativeRenderHandle(), width, height)
    defer renderer.deleteContext(&context)

    renderer.setCurrentContext(context)
    renderer.init()
    if needsAdvancedBlending and !ogl.supportsAdvancedBlending() do
        return {}
    renderer.begin(context)
    defer renderer.end()
    return scene(renderer)
}

// Reports whether `actual` is a lost windowed readback rather than a render of the scene.
//
// On this platform a freshly created windowed GL context occasionally reads back the default
// framebuffer instead of its render target — a blank buffer, or a foreign window once the parity
// window is shown — which reads as a whole-image difference from the CPU reference. Every real
// CPU/OpenGL parity difference stays under a couple thousand edge pixels at a channel delta of a
// few; a lost readback misses on a quarter of the image or more at a channel delta of tens, so the
// two are never confused.
private func readbackLost(expected, actual: const *Image)->bool
{
    if !actual.isValid() or actual.width != expected.width or actual.height != expected.height do
        return true

    let limit = (expected.width * expected.height) / 4
    var bad   = 0
    for y in expected.height
    {
        for x in expected.width
        {
            let e  = expected.pixelColor(x, y)
            let a  = actual.pixelColor(x, y)
            let dr = Math.abs(cast(s32) e.r - cast(s32) a.r)
            let dg = Math.abs(cast(s32) e.g - cast(s32) a.g)
            let db = Math.abs(cast(s32) e.b - cast(s32) a.b)
            if Math.max(Math.max(dr, dg), db) > 24
            {
                bad += 1
                if bad > limit do
                    return true
            }
        }
    }

    return false
}

// Renders the OpenGL side of a parity scene and returns it, re-rendering when the windowed readback
// is lost. The retry is what makes a real-window GL test deterministic on a live desktop; a genuine
// parity difference is never catastrophic, so it is never retried away. An unsupported
// advanced-blending context returns an invalid image on purpose — the capability answer, not a lost
// readback — and is returned as-is for the caller to skip.
func renderOglStable(className, title: string, width, height: s32, scene: RenderParityScene, expected: const *Image, needsAdvancedBlending = false)->Image fail
{
    var actual: Image
    for 5
    {
        actual = expect renderOgl(className, title, width, height, scene, needsAdvancedBlending)
        if needsAdvancedBlending and !actual.isValid() do
            break
        if !readbackLost(expected, &actual) do
            return actual
    }

    // Five lost readbacks in a row is not a rendering difference, and reporting it as one
    // sends a reader looking at the painter. Say what happened instead.
    if !needsAdvancedBlending or actual.isValid()
    {
        if readbackLost(expected, &actual)
        {
            Console.println("[ogl] the readback never returned the scene for ", title, "; the context read a blank or foreign framebuffer five times")
            Swag.assert(false)
        }
    }

    return actual
}

// Renders both backends for one scene and asserts they agree within `options`.
func assertOglParity(className, title: string, width, height: s32, scene: RenderParityScene, name: string, options: Testing.ImageGoldenOptions, needsAdvancedBlending = false) fail
{
    let expected = renderCpu(scene)
    let actual   = try renderOglStable(className, title, width, height, scene, &expected, needsAdvancedBlending)
    if needsAdvancedBlending and !actual.isValid() do
        return
    Testing.assertImagesNear(&expected, &actual, name, options)
}

// Exercises every artistic mode over opaque and partially covered backdrops. The latter row
// proves the premultiplied overlap/source-only/backdrop-only terms, not only the color formula.
private func renderBlendParityScene(renderer: IRenderer)->Image
{
    var target = renderer.createRenderTarget(RenderBlendWidth, RenderBlendHeight)
    defer renderer.deleteRenderTarget(&target)

    const OpaqueDst = Color.fromArgb(255'u8, 64'u8, 128'u8, 192'u8)
    const FaintDst  = Color.fromArgb(128'u8, 64'u8, 128'u8, 192'u8)
    const Src       = Color.fromArgb(128'u8, 192'u8, 64'u8, 128'u8)
    const Src2      = Color.fromArgb(176'u8, 48'u8, 192'u8, 96'u8)

    // Repeat the complete stream on the same target. A non-coherent context stays ordered
    // across draw calls as well as within one batch; the second clear is the first touch after
    // the previous stream's artistic pass.
    for 2
    {
        var painter = Painter.create(renderer)
        painter.begin()
        painter.bindRenderTarget(&target)
        painter.setColorMaskFull()
        painter.setBlendingMode(.Copy)
        painter.clear(Color.fromArgb(Argb.Zero))

        for mode, idx in ArtisticBlendModes
        {
            let x = cast(f32) idx * 12.0

            painter.setBlendingMode(.Copy)
            painter.fillRect(x, 0, 12, 12, OpaqueDst)
            painter.setBlendingMode(mode)
            painter.fillRect(x, 0, 12, 12, Src)

            painter.setBlendingMode(.Copy)
            painter.fillRect(x, 12, 12, 12, Color.fromArgb(Argb.Zero))
            painter.setBlendingMode(.Alpha)
            painter.fillRect(x, 12, 12, 12, FaintDst)
            painter.setBlendingMode(mode)
            painter.fillRect(x, 12, 12, 12, Src)

            // These two calls deliberately merge into one triangle batch and overlap. A
            // non-coherent backend must put a barrier between its individual primitives.
            painter.setBlendingMode(.Copy)
            painter.fillRect(x, 24, 12, 12, OpaqueDst)
            painter.setBlendingMode(mode)
            painter.fillRect(x, 24, 8, 12, Src)
            painter.fillRect(x + 4, 24, 8, 12, Src2)

            // Once a context has used a non-coherent artistic equation, later standard batches
            // are still framebuffer touches. Keep their overlapping primitives ordered too.
            painter.setBlendingMode(.Alpha)
            painter.fillRect(x, 36, 8, 12, Src)
            painter.fillRect(x + 4, 36, 8, 12, Src2)
        }

        painter.unbindRenderTarget()
        painter.end()
        renderer.draw(&painter)
    }

    return renderer.readRenderTarget(&target, 0, 0, RenderBlendWidth, RenderBlendHeight)
}

private func makeRenderParityTexture(renderer: IRenderer)->Texture
{
    var image             = Image.create(4, 4, .BGRA8)
    let colors: [4] Color = [Color.fromArgb(Argb.Crimson),
                             Color.fromArgb(Argb.Gold),
                             Color.fromArgb(Argb.DodgerBlue),
                             Color.fromArgb(Argb.LimeGreen)]

    for y in image.height
    {
        for x in image.width
        {
            let color = colors[cast(u64) ((x + y) & 3)]
            let row   = image.height - y - 1
            let pixel = image.pixels.buffer! + cast(u64) (row * image.rowStride + x * image.bytesPerPixel)
            pixel[0] = color.b
            pixel[1] = color.g
            pixel[2] = color.r
            pixel[3] = color.a
        }
    }

    return renderer.addImage(image)
}

// Records the portable painter surface once so both backends execute the exact same operations.
// Strokes measured from the centre line, over the widths, angles, joins and caps that decide
// whether one quad can stand in for a quad and two bands.
private func renderStrokeParityScene(renderer: IRenderer)->Image
{
    var target = renderer.createRenderTarget(RenderParityWidth, RenderParityHeight)
    defer renderer.deleteRenderTarget(&target)

    var painter = Painter.create(renderer)
    painter.begin()
    painter.bindRenderTarget(&target)
    painter.setColorMaskFull()
    painter.setBlendingMode(.Copy)
    painter.clear(Color.fromArgb(255'u8, 16'u8, 18'u8, 24'u8))

    painter.setBlendingMode(.Alpha)
    painter.setAntialiased(true)
    painter.setDistanceStrokes(true)

    // Widths across and below one device pixel, at an angle that lands the contour between two
    // pixel centres on both axes.
    var width = 0.35'f32
    for i in 6
    {
        let x = 8.0'f32 + cast(f32) i * 30
        painter.drawLine(x, 6, x + 22, 40, Color.fromArgb(Argb.White), width)
        width *= 1.9
    }

    // Every join and cap style the stroker can put around a measured segment.
    let joins = [JoinStyle.Bevel, JoinStyle.Round, JoinStyle.Miter, JoinStyle.MiterBevel]
    for j, i in joins
    {
        var path: LinePath
        let x = 8.0'f32 + cast(f32) i * 46
        path.start(x, 78)
        path.lineTo(x + 18, 50)
        path.lineTo(x + 36, 78)

        var pen = Pen.createSolid(Color.fromArgb(Argb.Gold), 5)
        pen.joinStyle   = j
        pen.begCapStyle = .Round
        pen.endCapStyle = .Square
        painter.drawPath(&path, pen)
    }

    // A closed contour, a curve, and a dashed pen, which keeps its own per-segment caps.
    var curve: LinePath
    curve.start(10, 96)
    curve.bezierTo(180, 112, 60, 132, 120, 78)
    painter.drawPath(&curve, Color.fromArgb(Argb.DodgerBlue), 3)

    var closed: LinePath
    closed.start(12, 106)
    closed.lineTo(44, 106)
    closed.lineTo(28, 124)
    closed.close()
    painter.drawPath(&closed, Color.fromArgb(Argb.LimeGreen), 2)

    var dashed = Pen.createSolid(Color.fromArgb(Argb.Crimson), 2)
    dashed.dashStyle = .Dash
    painter.drawLine(64, 120, 184, 120, dashed)

    // Under a transform, because the measured span is a path-space quantity and the contour it
    // places has to land where the banded one did.
    painter.pushTransform()
    painter.rotateTransform(18.0'deg, 150, 96)
    painter.scaleTransform(1.6)
    painter.drawLine(96, 58, 124, 58, Color.fromArgb(Argb.Violet), 1)
    painter.popTransform()

    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)

    return renderer.readRenderTarget(&target, 0, 0, RenderParityWidth, RenderParityHeight)
}

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
    for mode, idx in modes
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
    let face = expect loadTestTypeFace(getTestDataPath("segoeui.ttf"))!
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

// A clip pushed while a layer is bound has to clip against the layer.
//
// The scissor works in framebuffer pixels and flips vertically around the height of the bound
// target. Reading that height once per submission, from the surface, puts every clip of a shorter
// layer outside its framebuffer: the layer then records nothing at all, and a GUI window fading or
// scaling through a layer composites as an empty silhouette.
private func renderLayerClipParityScene(renderer: IRenderer)->Image
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

    layer.begin(&painter, {width: 96, height: 56})
    painter.pushClippingRect({8, 10, 74, 34})
    painter.fillRect({0, 0, 96, 56}, Color.fromArgb(Argb.DodgerBlue))
    painter.fillCircle(48, 28, 20, Color.fromArgb(Argb.Gold))
    painter.popClippingRect()
    layer.end()
    layer.draw({dstRect: {32, 24, 96, 56}})

    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)

    return renderer.readRenderTarget(&target, 0, 0, RenderLayerWidth, RenderLayerHeight)
}

// Rasterizing a vector document is a complete renderer round trip: an alpha-preserving
// supersampled pass, its resolve, and a readback. Whichever backend owns it, the image
// handed back has to be the same one.
private func renderSvgParityScene(renderer: IRenderer)->Image
{
    let drawing = expect Svg.Drawing.parse(RenderSvgSource)
    return drawing.rasterize(renderer, RenderSvgWidth, RenderSvgHeight, RenderSvgSupersample)
}

// Coverage accumulated through the supersampled pass leaves a couple of levels of drift on
// a flat interior, so an authored color is compared with the tolerance the goldens use.
private func assertSvgPixel(image: const *Image, x, y: s32, expected: Color)
{
    const Tolerance = 3
    let got = image.pixelColor(x, y)
    Swag.assert(Math.abs(cast(s32) got.a - cast(s32) expected.a) <= Tolerance)
    Swag.assert(Math.abs(cast(s32) got.r - cast(s32) expected.r) <= Tolerance)
    Swag.assert(Math.abs(cast(s32) got.g - cast(s32) expected.g) <= Tolerance)
    Swag.assert(Math.abs(cast(s32) got.b - cast(s32) expected.b) <= Tolerance)
}

// The rasterized document keeps its authored colors and coverage, and leaves the pixels it
// does not cover white: an atlas sampler interpolates across that edge, and black there is
// what puts a dark halo around a minified tile.
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

// Both backends run the same submission, so the rasterized document must come out the same
// whether a GPU or a single core filled the supersampled buffer and resolved it.
#test
{
    expect assertOglParity("SWAG_PIXEL_SVG_PARITY", "Pixel svg rasterize parity", RenderSvgWidth, RenderSvgHeight, &renderSvgParityScene, "render.parity.svg.cpu-ogl", {maxChannelDelta: 6, maxDifferentPixels: 600})
}

// Image comparisons expose separate limits for small channel drift and bounded outlier pixels.
#test
{
    var expected = Image.create(2, 1, .BGRA8)
    expected.clear()
    var actual = expected

    let pixels = actual.pixels.buffer!
    pixels[2] = 4
    Testing.assertImagesNear(&expected, &actual, "render.parity.tolerance.delta", {maxChannelDelta: 4})

    pixels[2] = 255
    Testing.assertImagesNear(&expected, &actual, "render.parity.tolerance.outlier", {maxDifferentPixels: 1})
}

// The deterministic CPU backend is the exact, reviewable reference for portable painter output.
#[Swag.TestTag("golden")]
#test
{
    let image = renderCpu(&renderParityScene)
    Testing.assertImageGolden(&image, "render.parity.portable")
}

// A capable OpenGL context implements the same artistic equations as the CPU, including partial
// backdrop coverage. Non-coherent contexts exercise the explicit barrier path; unsupported
// contexts expose their limitation through the capability query.
#test
{
    expect assertOglParity("SWAG_PIXEL_BLEND_PARITY", "Pixel blend parity", RenderBlendWidth, RenderBlendHeight, &renderBlendParityScene, "render.parity.blend.cpu-ogl", {maxChannelDelta: 3}, true)
}

// OpenGL must stay visually equivalent to the CPU reference. Raster-edge differences are
// bounded explicitly; flat fills, texture interiors and state transitions still compare exactly.
#test
{
    expect assertOglParity("SWAG_PIXEL_RENDER_PARITY", "Pixel renderer parity", RenderParityWidth, RenderParityHeight, &renderParityScene, "render.parity.cpu-ogl", {maxChannelDelta: 3, maxDifferentPixels: 512})
}

// The deterministic CPU backend is the reviewable reference for measured strokes too.
#[Swag.TestTag("golden")]
#test
{
    let image = renderCpu(&renderStrokeParityScene)
    Testing.assertImageGolden(&image, "render.parity.stroke")
}

// A measured stroke has to reach the same pixels on both backends, because the rule that turns a
// signed distance into coverage is written twice: once in the OpenGL fragment program and once in
// the software rasterizer. This is what keeps the two honest before the flag becomes a default.
#test
{
    expect assertOglParity("SWAG_PIXEL_STROKE_PARITY", "Pixel stroke parity", RenderParityWidth, RenderParityHeight, &renderStrokeParityScene, "render.parity.stroke.cpu-ogl", {maxChannelDelta: 3, maxDifferentPixels: 512})
}

// Text goldens cover bitmap sampling plus the complete built-in MTSDF effects path.
#[Swag.TestTag("golden")]
#test
{
    let image = renderCpu(&renderTextParityScene)
    Testing.assertImageGolden(&image, "render.parity.text")
}

// CPU and OpenGL implement the same built-in text programs, including MTSDF effects.
#test
{
    expect assertOglParity("SWAG_PIXEL_TEXT_PARITY", "Pixel text parity", RenderTextWidth, RenderTextHeight, &renderTextParityScene, "render.parity.text.cpu-ogl", {maxChannelDelta: 5, maxDifferentPixels: 1500})
}

// The CPU backend makes composite layer output deterministic and reviewable.
#[Swag.TestTag("golden")]
#test
{
    let image = renderCpu(&renderLayerParityScene)
    Testing.assertImageGolden(&image, "render.parity.layer")
}

// Layer resolve, blur, paint-alpha replay and pooled targets agree across both backends.
#test
{
    expect assertOglParity("SWAG_PIXEL_LAYER_PARITY", "Pixel layer parity", RenderLayerWidth, RenderLayerHeight, &renderLayerParityScene, "render.parity.layer.cpu-ogl", {maxChannelDelta: 6, maxDifferentPixels: 1500})
}

// A clipping rectangle pushed inside a layer clips the layer, on both backends.
#test
{
    expect assertOglParity("SWAG_PIXEL_LAYER_CLIP_PARITY", "Pixel layer clip parity", RenderLayerWidth, RenderLayerHeight, &renderLayerClipParityScene, "render.parity.layer.clip.cpu-ogl", {maxChannelDelta: 6, maxDifferentPixels: 1500})
}

// Builds a planar 4:2:0 picture with a different value in every corner: a luma ramp that rises
// along both axes, and chroma held constant over each half so bilinear chroma upsampling only
// differs at one seam. A backend that uploads the planes in the wrong row order, or samples them
// mirrored, cannot reproduce it.
private func makeRenderPlanarPicture(storage: *Array'u8)->Yuv420View
{
    const Width        = cast(u64) RenderPlanarWidth
    const Height       = cast(u64) RenderPlanarHeight
    const ChromaWidth  = (Width + 1) / 2
    const ChromaHeight = (Height + 1) / 2

    storage.resize(Width * Height + ChromaWidth * ChromaHeight * 2)
    let luma    = storage.buffer!
    let chromaB = luma + Width * Height
    let chromaR = chromaB + ChromaWidth * ChromaHeight

    for y in Height
    {
        for x in Width do
            luma[y * Width + x] = cast(u8) (16 + x * 110 / (Width - 1) + y * 109 / (Height - 1))
    }

    for y in ChromaHeight
    {
        for x in ChromaWidth
        {
            chromaB[y * ChromaWidth + x] = x < ChromaWidth / 2 ? 96'u8 : 168'u8
            chromaR[y * ChromaWidth + x] = y < ChromaHeight / 2 ? 96'u8 : 168'u8
        }
    }

    return {
        luma: luma,
        chromaB: chromaB,
        chromaR: chromaR,
        lumaStride: Width,
        chromaStride: ChromaWidth,
        width: RenderPlanarWidth,
        height: RenderPlanarHeight,
        matrix: .Bt709}
}

// Draws one planar picture at its own size, which is what a video view does for every frame.
func renderPlanarParityScene(renderer: IRenderer)->Image
{
    var storage: Array'u8
    let picture = makeRenderPlanarPicture(&storage)
    var texture = renderer.addImage(&picture)
    defer renderer.removeTexture(&texture)

    var target = renderer.createRenderTarget(RenderPlanarWidth, RenderPlanarHeight)
    defer renderer.deleteRenderTarget(&target)

    var painter = Painter.create(renderer)
    painter.begin()
    painter.bindRenderTarget(&target)
    painter.setColorMaskFull()
    painter.setBlendingMode(.Copy)
    painter.clear(Color.fromArgb(Argb.Zero))
    painter.drawTexture({0, 0, RenderPlanarWidth, RenderPlanarHeight}, texture)
    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)

    return renderer.readRenderTarget(&target, 0, 0, RenderPlanarWidth, RenderPlanarHeight)
}

// Checks the four corners of a drawn picture against the conversion of the corner samples of the
// planes it came from. Orientation is the whole point: a flipped picture still matches everywhere
// a test uses one flat colour, and only a corner states which way round the rows went.
private func assertPlanarCornersUpright(image: const *Image, view: const *Yuv420View)
{
    for corner in 4's32
    {
        let x        = corner & 1 ? view.width - 1 : 0
        let y        = corner & 2 ? view.height - 1 : 0
        let chromaAt = cast(u64) (y >> 1) * view.chromaStride + cast(u64) (x >> 1)
        let expected = expectedPlanarColor(view.luma[cast(u64) y * view.lumaStride + cast(u64) x], view.chromaB[chromaAt], view.chromaR[chromaAt], view.matrix, view.studioRange)
        let actual   = image.pixelColor(x, y)
        Swag.assert(Math.abs(cast(s32) actual.r - cast(s32) expected.r) <= 1)
        Swag.assert(Math.abs(cast(s32) actual.g - cast(s32) expected.g) <= 1)
        Swag.assert(Math.abs(cast(s32) actual.b - cast(s32) expected.b) <= 1)
    }
}

// A picture handed over as planes reaches the surface the way it was decoded: the first row of the
// planes is the top of the picture and the first sample of a row is its left edge.
#test
{
    var storage: Array'u8
    let picture = makeRenderPlanarPicture(&storage)
    let image   = renderCpu(&renderPlanarParityScene)
    assertPlanarCornersUpright(&image, &picture)
}

// The backend with shaders keeps the three planes and converts while it samples; the one without
// converts once on upload. Disagreeing on row order there turns every decoded video upside down,
// which no test made of one flat colour can see.
//
// The two do differ where chroma changes: sampling the half-resolution planes with the luma
// coordinates interpolates across the boundary, while converting on upload replicates one sample
// over its two-by-two block. That is one chroma texel either side of each seam of the picture
// below, and nowhere else, which is what the pixel budget stands for.
#test
{
    var storage: Array'u8
    let picture  = makeRenderPlanarPicture(&storage)
    let expected = renderCpu(&renderPlanarParityScene)
    let image    = try renderOglStable("SWAG_PIXEL_PLANAR_PARITY", "Pixel planar parity", RenderPlanarWidth, RenderPlanarHeight, &renderPlanarParityScene, &expected)
    Testing.assertImagesNear(&expected, &image, "render.parity.planar.cpu-ogl", {maxChannelDelta: 4, maxDifferentPixels: 400})
    assertPlanarCornersUpright(&image, &picture)
}

// Two clipping regions in a row. The second starts from an empty plane rather than from what
// the first wrote, and a texture filled through a region lands where the region is.
private func renderClipRegionParityScene(renderer: IRenderer)->Image
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
    painter.clear(Color.fromArgb(Argb.White))
    painter.setBlendingMode(.Alpha)

    // A texture through a circle on the left.
    painter.startClippingRegion(.Set)
    painter.fillCircle(48, 64, 40, Color.fromArgb(Argb.White))
    painter.endClippingRegion()
    var brush = Brush.createTexture(texture)
    brush.mapOver({8, 24, 80, 80})
    painter.fillRect({0, 0, 96, RenderParityHeight}, brush)
    painter.resetClippingRegion()

    // A solid fill over the whole target through a circle on the right: it must reach only that
    // circle, never the one the first region wrote.
    painter.startClippingRegion(.Set)
    painter.fillCircle(144, 64, 40, Color.fromArgb(Argb.White))
    painter.endClippingRegion()
    painter.fillRect({0, 0, RenderParityWidth, RenderParityHeight}, Color.fromArgb(Argb.DodgerBlue))
    painter.resetClippingRegion()

    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)
    return renderer.readRenderTarget(&target, 0, 0, RenderParityWidth, RenderParityHeight)
}

// Reports whether a pixel of the window around `(x, y)` is neither white nor the fill: the
// mark of an antialiased edge, which a one-bit region can never produce.
private func hasSoftEdge(image: const *Image, x, y: s32, fill: Color)->bool
{
    for dy in -1 to 1
    {
        for dx in -1 to 1
        {
            let color = image.pixelColor(x + dx, y + dy)
            if color.r > fill.r + 20 and color.r < 235 do
                return true
        }
    }

    return false
}

// A clipping region starts empty and carries coverage, on the CPU reference and on OpenGL alike.
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

    let actual = expect renderOglStable("SWAG_PIXEL_CLIP_PARITY", "Pixel clip region parity", RenderParityWidth, RenderParityHeight, &renderClipRegionParityScene, &expected)
    Testing.assertImagesNear(&expected, &actual, "render.parity.clipregion.cpu-ogl", {maxChannelDelta: 3, maxDifferentPixels: 512})
}

// Every artistic mode over a backdrop whose alpha plane is not being written. The upper row is
// drawn over a colour stored with zero alpha, the lower row over the same colour stored opaque;
// with alpha excluded from the colour mask the plane is scratch, so the two rows must agree.
private func renderOpaqueBackdropParityScene(renderer: IRenderer)->Image
{
    var target = renderer.createRenderTarget(RenderBlendWidth, RenderBlendHeight)
    defer renderer.deleteRenderTarget(&target)

    const ClearDst  = Color.fromArgb(0'u8, 64'u8, 128'u8, 192'u8)
    const OpaqueDst = Color.fromArgb(255'u8, 64'u8, 128'u8, 192'u8)
    const Src       = Color.fromArgb(128'u8, 192'u8, 64'u8, 128'u8)

    var painter = Painter.create(renderer)
    painter.begin()
    painter.bindRenderTarget(&target)
    painter.setColorMaskFull()
    painter.setBlendingMode(.Copy)
    painter.clear(ClearDst)
    painter.fillRect({0, 24, RenderBlendWidth, 24}, OpaqueDst)
    painter.setColorMaskColor()

    for mode, idx in ArtisticBlendModes
    {
        let x = cast(f32) idx * 12.0
        painter.setBlendingMode(mode)
        painter.fillRect(x, 0, 12, 24, Src)
        painter.fillRect(x, 24, 12, 24, Src)
    }

    painter.setBlendingMode(.Alpha)
    painter.unbindRenderTarget()
    painter.end()
    renderer.draw(&painter)
    return renderer.readRenderTarget(&target, 0, 0, RenderBlendWidth, RenderBlendHeight)
}

// A backdrop whose alpha is not written is opaque: the effect reads its stored colour, on the
// CPU reference and on OpenGL alike.
#test
{
    let expected = renderCpu(&renderOpaqueBackdropParityScene)
    for idx in ArtisticBlendModes.count
    {
        let x       = cast(s32) idx * 12 + 6
        let scratch = expected.pixelColor(x, 12)
        let opaque  = expected.pixelColor(x, 36)
        Swag.assert(Math.abs(cast(s32) scratch.r - cast(s32) opaque.r) <= 1)
        Swag.assert(Math.abs(cast(s32) scratch.g - cast(s32) opaque.g) <= 1)
        Swag.assert(Math.abs(cast(s32) scratch.b - cast(s32) opaque.b) <= 1)
    }

    // Alpha is excluded from what is drawn, so only the colour is compared: OpenGL leaves the
    // scratch plane opaque over the batch it made opaque, the CPU leaves it untouched.
    let actual = expect renderOglStable("SWAG_PIXEL_BACKDROP_PARITY", "Pixel opaque backdrop parity", RenderBlendWidth, RenderBlendHeight, &renderOpaqueBackdropParityScene, &expected, true)
    if !actual.isValid() do
        return
    let expectedColor = colorOnly(&expected)
    let actualColor   = colorOnly(&actual)
    Testing.assertImagesNear(&expectedColor, &actualColor, "render.parity.backdrop.cpu-ogl", {maxChannelDelta: 3})
}

// Returns a copy of `image` with an opaque alpha plane, so a comparison reads its colour alone.
private func colorOnly(image: const *Image)->Image
{
    var result = #move image.convertedTo(.RGBA8)
    for y in cast(u64) result.height
    {
        var pixel = result.pixels.buffer! + y * cast(u64) result.rowStride
        for cast(u64) result.width
        {
            pixel[3] = 255
            pixel    += 4
        }
    }

    return #move result
}
