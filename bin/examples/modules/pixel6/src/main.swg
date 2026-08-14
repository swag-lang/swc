using Core, Gdiplus, Pixel

const W                   = 1260
const H                   = 940
const TestFrames          = 30
const Margin              = 24.0
const SampleCount         = 4
const OutlineFontSize     = 48'u32
const OutlineBorder       = 5.5
const OutlineShadowMargin = 14
const OutlineSuperSample  = 3

enum OutlineMode
{
    OffsetFill
    PathStroke
}

struct TextCase
{
    label: string
    scale: f32
}

var g_Window:    Env.Window
var g_Renderer:  Pixel.RenderOgl
var g_Render:    Pixel.IRenderer = undefined
var g_Painter:   Pixel.Painter
var g_RC:        Pixel.RenderContext
var g_TypeFace:  #null *Pixel.TypeFace
var g_TitleFont: #null *Pixel.Font
var g_LabelFont: #null *Pixel.Font
var g_HelpFont:  #null *Pixel.Font
var g_GdiToken:  u64
var g_GdiText:   [SampleCount] Texture

const Samples = [
    TextCase{"50%", 0.50},
    TextCase{"75%", 0.75},
    TextCase{"100%", 1.00},
    TextCase{"125%", 1.25}]

func loadFonts() fail
{
    g_TypeFace  = try TypeFace.load("segoeui.ttf")
    g_TitleFont = g_Renderer.fonts.createFont(g_TypeFace!, 34, .Bitmap)
    g_LabelFont = g_Renderer.fonts.createFont(g_TypeFace!, 16, .Bitmap)
    g_HelpFont  = g_Renderer.fonts.createFont(g_TypeFace!, 13, .Bitmap)
}

func gdipCheck(status: GpStatus)
{
    Debug.assert(status == GdipOk, "GDI+ call failed")
}

func initGdiPlus()
{
    if g_GdiToken do
        return

    var input: GdiplusStartupInput
    input.GdiplusVersion = 1
    gdipCheck(GdiplusStartup(&g_GdiToken, &input, null))
}

func shutdownGdiPlus()
{
    if !g_GdiToken do
        return

    GdiplusShutdown(g_GdiToken)
    g_GdiToken = 0
}

func addGdiPathText(path: *GpPath, text16: const [*] u16, count: s32, family: *GpFontFamily, format: *GpStringFormat, emSize, x, y: f32)
{
    var layout: GpRectF
    layout.x      = x
    layout.y      = y
    layout.width  = 4096
    layout.height = 4096
    gdipCheck(GdipAddPathString(path, text16, count, family, GdipFontStyleRegular, emSize, &layout, format))
}

func unpremultiplyChannel(value, alpha: u8)->u8
{
    if !alpha do
        return 0
    if alpha == 255 do
        return value

    let result = (cast(u32) value * 255 + cast(u32) alpha / 2) / cast(u32) alpha
    if result > 255 do
        return 255
    return cast(u8) result
}

func unpremultiplyImage(image: *Image)
{
    var ptr = image.pixels.buffer!
    for image.width * image.height
    {
        let alpha = ptr[3]
        ptr[0] = unpremultiplyChannel(ptr[0], alpha)
        ptr[1] = unpremultiplyChannel(ptr[1], alpha)
        ptr[2] = unpremultiplyChannel(ptr[2], alpha)
        ptr    += 4
    }
}

func flipImageVertical(image: *Image)
{
    var row = Array'u8{}
    row.resize(cast(u64) image.rowStride)

    var top = image.pixels.buffer
    var bot = image.pixels.buffer + image.rowStride * (image.height - 1)
    for image.height / 2
    {
        Memory.copy(row.buffer, top, cast(u64) image.rowStride)
        Memory.copy(top, bot, cast(u64) image.rowStride)
        Memory.copy(bot, row.buffer, cast(u64) image.rowStride)
        top += image.rowStride
        bot -= image.rowStride
    }
}

// `density` is the device pixels per logical unit of the caller: the reference is
// rasterized straight at device resolution so it stays crisp on scaled displays.
func renderGdiPlusOutlineImage(text: string, scale, density: f32)->Image
{
    initGdiPlus()

    let emSize  = cast(f32) OutlineFontSize * scale * density
    let border  = OutlineBorder * scale * density
    let text16  = Utf16.toZeroTerminated(text)
    let face16  = Utf16.toZeroTerminated("Segoe UI")
    let count16 = cast(s32) (text16.count - 1)

    var family: #null *GpFontFamily
    var format: #null *GpStringFormat
    gdipCheck(GdipCreateFontFamilyFromName(face16.buffer, null, &family))
    gdipCheck(GdipCreateStringFormat(0, 0, &format))

    var measurePath: #null *GpPath
    var bounds:      GpRectF
    gdipCheck(GdipCreatePath(GdipFillModeAlternate, &measurePath))
    @assert(format != null)
    @assert(family != null)
    @assert(measurePath != null)
    addGdiPathText(measurePath, text16.buffer!, count16, family, format, emSize, 0, 0)
    gdipCheck(GdipGetPathWorldBounds(measurePath, &bounds, null, null))
    gdipCheck(GdipDeletePath(measurePath))

    let margin = cast(f32) OutlineShadowMargin * density
    let localW = Math.max(cast(s32) Math.ceil(bounds.width + border * 2 + margin * 2), 1)
    let localH = Math.max(cast(s32) Math.ceil(bounds.height + border * 2 + margin * 2), 1)

    var image = Image.create(localW, localH, .BGRA8)
    image.clear()

    var bitmap:   #null *GpBitmap
    var graphics: #null *GpGraphics
    gdipCheck(GdipCreateBitmapFromScan0(localW, localH, localW * 4, GdipPixelFormat32bppPARGB, image.pixels.buffer, &bitmap))
    @assert(bitmap != null)
    gdipCheck(GdipGetImageGraphicsContext(cast(*GpImage) bitmap, &graphics))
    @assert(graphics != null)
    gdipCheck(GdipSetSmoothingMode(graphics, GdipSmoothingModeHighQuality))
    gdipCheck(GdipSetPixelOffsetMode(graphics, GdipPixelOffsetModeHighQuality))
    gdipCheck(GdipSetTextRenderingHint(graphics, GdipTextRenderingHintAAGridFit))
    gdipCheck(GdipGraphicsClear(graphics, 0))

    var path: #null *GpPath
    gdipCheck(GdipCreatePath(GdipFillModeAlternate, &path))
    @assert(path != null)
    addGdiPathText(path, text16.buffer!, count16, family, format, emSize, margin + border - bounds.x, margin + border - bounds.y)

    var pen:   #null *GpPen
    var brush: #null *GpSolidFill
    gdipCheck(GdipCreatePen1(cast(u32) Argb.Crimson, border * 2, GdipUnitPixel, &pen))
    @assert(pen != null)
    gdipCheck(GdipSetPenLineJoin(pen, GdipLineJoinRound))
    gdipCheck(GdipCreateSolidFill(cast(u32) Argb.White, &brush))
    gdipCheck(GdipDrawPath(graphics, pen, path))
    @assert(brush != null)
    gdipCheck(GdipFillPath(graphics, cast(*GpBrush) brush, path))

    gdipCheck(GdipDeletePen(pen))
    gdipCheck(GdipDeleteBrush(cast(*GpBrush) brush))
    gdipCheck(GdipDeletePath(path))
    gdipCheck(GdipDeleteStringFormat(format))
    gdipCheck(GdipDeleteFontFamily(family))
    gdipCheck(GdipDeleteGraphics(graphics))
    gdipCheck(GdipDisposeImage(cast(*GpImage) bitmap))

    flipImageVertical(&image)
    unpremultiplyImage(&image)
    return image
}

func loadGdiReferences()
{
    for sample, idx in Samples
    {
        let image = renderGdiPlusOutlineImage("Outline", sample.scale, g_Painter.contentScale())
        g_GdiText[idx] = g_Render.addImage(image)
    }
}

func insetRect(rect: Math.Rectangle, left, top, right, bottom: f32)->Math.Rectangle
{
    var result = rect
    result.x      += left
    result.y      += top
    result.width  -= left + right
    result.height -= top + bottom
    return result
}

func drawHeader(painter: *Pixel.Painter)
{
    painter.drawString(34, 28, "Pixel outline text quality", g_TitleFont!, Argb.MidnightBlue)
    painter.drawString(36, 72, "Native GDI+ GraphicsPath reference, Pixel path-stroke outline, and the old offset-fill outline with the same blurred render-target shadow.", g_HelpFont!, Argb.DimGray)
}

func drawFrame(painter: *Pixel.Painter, rect: Math.Rectangle, title: string)
{
    painter.fillRoundRect(rect, 8, 8, Argb.White)
    painter.drawRoundRect(rect, 8, 8, Color.fromArgb(84, Argb.SlateGray), 1)
    painter.drawString(rect.x + 12, rect.y + 10, title, g_LabelFont!, Argb.DarkSlateBlue)
}

func makeOutline(text: string, size: u32, embolden: u32)->LinePathList
{
    var result = expect g_TypeFace!.buildStringOutline(text, size, embolden)
    result.flatten(.High)
    return result
}

func drawOutlineCore(painter: *Pixel.Painter, outline: *LinePathList, x, y, scale, border: f32, faceColor, outlineColor: Color, mode: OutlineMode)
{
    let drawX = x - ((outline.minBounds.x - border) * scale)
    let drawY = y - ((outline.minBounds.y - border) * scale)

    painter.pushTransform()
    painter.scaleTransform(scale, scale)
    painter.translateTransform(drawX, drawY)

    switch mode
    {
    case .OffsetFill:
        if outlineColor.a
        {
            var borderOutline = outline[]
            borderOutline.offset(border, .Round, 0.5)
            painter.fillPath(&borderOutline, outlineColor)
        }

    case .PathStroke:
        if outlineColor.a
        {
            var pen = Pen.createSolid(outlineColor, border * 2)
            pen.joinStyle = .Round
            painter.drawPath(outline, pen, .Merge)
        }
    }

    painter.fillPath(outline, faceColor)
    painter.popTransform()
}

func renderOutlineToTarget(painter: *Pixel.Painter, rt: *RenderTarget, outline: *LinePathList, textX, textY, scale: f32, mode: OutlineMode)
{
    with painter
    {
        .bindRenderTarget(rt, true)
        .setColorMaskFull()
        .setAntialiased(true)
        .clear(Argb.Zero)
        .setColorMaskColor()
        .setBlendingMode(.Alpha)
        drawOutlineCore(painter, outline, textX, textY, scale, OutlineBorder, Argb.White, Argb.Crimson, mode)
        .unbindRenderTarget()
    }
}

func drawShadowedOutline(painter: *Pixel.Painter, area: Math.Rectangle, text: string, scale: f32, mode: OutlineMode, superSample = 1)
{
    const Bold = 0'u32

    var outline    = makeOutline(text, OutlineFontSize, Bold)
    let textWidth  = ((outline.maxBounds.x - outline.minBounds.x) + 2 * OutlineBorder) * scale
    let textHeight = ((outline.maxBounds.y - outline.minBounds.y) + 2 * OutlineBorder) * scale
    let localW     = cast(s32) Math.ceil(textWidth + OutlineShadowMargin * 2)
    let localH     = cast(s32) Math.ceil(textHeight + OutlineShadowMargin * 2)
    let textX      = cast(f32) OutlineShadowMargin
    let textY      = cast(f32) OutlineShadowMargin

    // The targets store device texels while every drawing call stays in logical
    // units: destination rectangles are logical, source rectangles address texels,
    // and the painter maps logical to device at its content scale (like Pixel.Layer).
    let density = painter.contentScale()
    let devW    = cast(s32) Math.ceil(localW * density)
    let devH    = cast(s32) Math.ceil(localH * density)
    let dstRect = Math.Rectangle{0, 0, cast(f32) localW, cast(f32) localH}
    let srcRect = Math.Rectangle{0, 0, localW * density, localH * density}

    let rtText   = g_Render.acquireRenderTarget(devW, devH)
    let rtShadow = g_Render.acquireRenderTarget(devW, devH)
    let rtBlur   = g_Render.acquireRenderTarget(devW, devH)

    if superSample <= 1
    {
        renderOutlineToTarget(painter, rtText, &outline, textX, textY, scale, mode)
    }
    else
    {
        let ss      = cast(f32) superSample
        let rtSuper = g_Render.acquireRenderTarget(devW * superSample, devH * superSample)
        renderOutlineToTarget(painter, rtSuper, &outline, textX * ss, textY * ss, scale * ss, mode)

        with painter
        {
            .bindRenderTarget(rtText)
            .setShader(&g_Renderer.shaderResolve)
            .setShaderParam(g_Renderer.shaderResolve.factor, superSample)
            .setColorMaskFull()
            .setAntialiased(false)
            .setBlendingMode(.Copy)
            .setInterpolationMode(.Linear)
            .clear(Argb.Zero)
            .drawTexture(dstRect, Math.Rectangle{0, 0, srcRect.width * ss, srcRect.height * ss}, rtSuper.colorBuffer)
            .setShader()
            .unbindRenderTarget()
            .releaseRenderTarget(rtSuper)
        }
    }

    with painter
    {
        .setInterpolationMode(.Pixel)

        .bindRenderTarget(rtBlur)
        .setShader(&g_Renderer.shaderBlur)
        .setShaderParam(g_Renderer.shaderBlur.axis, 0's32)
        .setShaderParam(g_Renderer.shaderBlur.radius, 7.0)
        .setBlendingMode(.Copy)
        .setColorMaskFull()
        .clear(Argb.Zero)
        .drawTexture(dstRect, srcRect, rtText.colorBuffer)
        .setShader()
        .unbindRenderTarget()

        .bindRenderTarget(rtShadow)
        .setShader(&g_Renderer.shaderBlur)
        .setShaderParam(g_Renderer.shaderBlur.axis, 1's32)
        .setShaderParam(g_Renderer.shaderBlur.radius, 7.0)
        .setBlendingMode(.Copy)
        .setColorMaskFull()
        .clear(Argb.Zero)
        .drawTexture(dstRect, srcRect, rtBlur.colorBuffer, Color.fromArgb(150, Argb.Black))
        .setShader()
        .unbindRenderTarget()
    }

    let dst = Math.Rectangle{area.horzCenter() - localW * 0.5, area.vertCenter() - localH * 0.5, cast(f32) localW, cast(f32) localH}

    painter.setAntialiased(false)
    painter.drawTexture(Math.Rectangle{dst.x + 5, dst.y + 5, dst.width, dst.height}, srcRect, rtShadow.colorBuffer)
    painter.drawTexture(dst, srcRect, rtText.colorBuffer)

    painter.releaseRenderTarget(rtText)
    painter.releaseRenderTarget(rtShadow)
    painter.releaseRenderTarget(rtBlur)
}

func drawShadowedTexture(painter: *Pixel.Painter, area: Math.Rectangle, texture: Texture)
{
    // The reference texture is rasterized at device density: its texel size maps back
    // to logical units through the painter content scale. Destination rectangles are
    // logical, source rectangles address texels.
    let density  = painter.contentScale()
    let devW     = texture.width
    let devH     = texture.height
    let logicalW = devW / density
    let logicalH = devH / density
    let rtText   = g_Render.acquireRenderTarget(devW, devH)
    let rtBlur   = g_Render.acquireRenderTarget(devW, devH)
    let src      = Math.Rectangle{0, 0, cast(f32) devW, cast(f32) devH}
    let dstFull  = Math.Rectangle{0, 0, logicalW, logicalH}

    with painter
    {
        .bindRenderTarget(rtText, true)
        .setColorMaskFull()
        .setAntialiased(false)
        .clear(Argb.Zero)
        .setColorMaskColor()
        .setBlendingMode(.Alpha)
        .drawTexture(dstFull, src, texture)
        .unbindRenderTarget()

        .bindRenderTarget(rtBlur)
        .setShader(&g_Renderer.shaderBlur)
        .setShaderParam(g_Renderer.shaderBlur.axis, 0's32)
        .setShaderParam(g_Renderer.shaderBlur.radius, 7.0)
        .setBlendingMode(.Copy)
        .setColorMaskFull()
        .clear(Argb.Zero)
        .drawTexture(dstFull, src, rtText.colorBuffer)
        .setShader()
        .unbindRenderTarget()

        .bindRenderTarget(rtText)
        .setShader(&g_Renderer.shaderBlur)
        .setShaderParam(g_Renderer.shaderBlur.axis, 1's32)
        .setShaderParam(g_Renderer.shaderBlur.radius, 7.0)
        .setBlendingMode(.Copy)
        .setColorMaskFull()
        .clear(Argb.Zero)
        .drawTexture(dstFull, src, rtBlur.colorBuffer, Color.fromArgb(150, Argb.Black))
        .setShader()
        .unbindRenderTarget()
    }

    let dst = Math.Rectangle{area.horzCenter() - logicalW * 0.5, area.vertCenter() - logicalH * 0.5, logicalW, logicalH}

    painter.setAntialiased(false)
    painter.drawTexture(Math.Rectangle{dst.x + 5, dst.y + 5, dst.width, dst.height}, src, rtText.colorBuffer)
    painter.drawTexture(dst, src, texture)
    painter.setAntialiased(true)

    painter.releaseRenderTarget(rtText)
    painter.releaseRenderTarget(rtBlur)
}

func drawSampleGrid(painter: *Pixel.Painter, rowRect: Math.Rectangle, title: string, mode: OutlineMode)
{
    drawFrame(painter, rowRect, title)

    let body  = insetRect(rowRect, 18, 48, 18, 18)
    let gap   = 16.0
    let cellW = (body.width - gap * 3) / 4
    for sample, idx in Samples
    {
        let x    = body.x + cast(f32) idx * (cellW + gap)
        let cell = Math.Rectangle{x, body.y, cellW, body.height}
        painter.fillRoundRect(cell, 6, 6, Color.fromArgb(255, 247, 249, 251))
        painter.drawRoundRect(cell, 6, 6, Color.fromArgb(32, Argb.SlateGray), 1)
        painter.drawString(cell.x + 10, cell.y + 8, sample.label, g_HelpFont!, Argb.DimGray)
        let ss = mode == .PathStroke ? OutlineSuperSample : 1
        drawShadowedOutline(painter, insetRect(cell, 8, 22, 8, 8), "Outline", sample.scale, mode, ss)
    }
}

func drawGdiGrid(painter: *Pixel.Painter, rowRect: Math.Rectangle)
{
    drawFrame(painter, rowRect, "GDI+ reference (GraphicsPath DrawPath + FillPath)")

    let body  = insetRect(rowRect, 18, 48, 18, 18)
    let gap   = 16.0
    let cellW = (body.width - gap * 3) / 4
    for sample, idx in Samples
    {
        let x    = body.x + cast(f32) idx * (cellW + gap)
        let cell = Math.Rectangle{x, body.y, cellW, body.height}
        painter.fillRoundRect(cell, 6, 6, Color.fromArgb(255, 247, 249, 251))
        painter.drawRoundRect(cell, 6, 6, Color.fromArgb(32, Argb.SlateGray), 1)
        painter.drawString(cell.x + 10, cell.y + 8, sample.label, g_HelpFont!, Argb.DimGray)
        drawShadowedTexture(painter, insetRect(cell, 8, 22, 8, 8), g_GdiText[idx])
    }
}

func drawScene(painter: *Pixel.Painter)
{
    painter.setColorMaskFull()
    painter.clear(Color.fromArgb(255, 242, 244, 248))
    painter.setColorMaskColor()
    painter.setParams(.Antialiased)
    drawHeader(painter)

    drawGdiGrid(painter, {Margin, 108, W - Margin * 2, 246})
    drawSampleGrid(painter, {Margin, 374, W - Margin * 2, 246}, "Pixel supersampled path-stroke outline", .PathStroke)
    drawSampleGrid(painter, {Margin, 640, W - Margin * 2, 246}, "Legacy offset-fill outline", .OffsetFill)
}

func display()
{
    g_Render.begin(g_RC)
    g_Painter.begin()
    drawScene(&g_Painter)
    g_Painter.end()
    g_Painter.render()
    g_Render.end()
}

func onResize(window: *Env.Window, width, height: s32)
{
    // The client size is physical device pixels; the scene keeps drawing in logical
    // W x H units, so the painter maps them to device pixels on scaled displays.
    g_RC.width  = width
    g_RC.height = height
    g_Painter.setContentScale(window.dpiScale())
}

#main
{
    g_Window = try Env.createWindow({identifier: "pixel6", title: "Pixel example - text outline quality", width: W, height: H, flags: .Minimizable})
    try g_Window.setClientSize(W, H)
    g_Render  = &g_Renderer
    g_Painter = Pixel.Painter.create(g_Render)
    g_RC      = try g_Render.createContext(g_Window.nativeRenderHandle(), W, H)
    defer g_Render.deleteContext(&g_RC)
    g_Render.setCurrentContext(g_RC)
    g_Render.init()

    // The GDI+ references rasterize at the display density, so the content scale must
    // be known before they are generated; show() replays it through onResize anyway.
    g_Painter.setContentScale(g_Window.dpiScale())

    try loadFonts()
    loadGdiReferences()

    g_Window.callbacks.onResize = &onResize
    try g_Window.show()

    var loop: Env.WindowLoop
    if Env.isSmokeRun() do
        loop.smokeFrames = TestFrames
    while loop.next()
    {
        display()
    }

    shutdownGdiPlus()
}
