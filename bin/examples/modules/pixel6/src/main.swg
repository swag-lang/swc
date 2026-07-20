using Core, Gdiplus, Pixel, Win32

const W = 1260
const H = 940
const TestFrames = 30
const Margin = 24.0
const SampleCount = 4
const OutlineFontSize = 48'u32
const OutlineBorder = 5.5
const OutlineShadowMargin = 14
const OutlineSuperSample = 3

const FixedWindowStyle = WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_CLIPSIBLINGS | WS_CLIPCHILDREN

enum OutlineMode
{
    OffsetFill
    PathStroke
}

struct TextCase
{
    label:      string
    scale:      f32
}

var g_Window:    Env.Window
var g_Renderer:  Pixel.RenderOgl
var g_Painter:   Pixel.Painter
var g_RC:        Pixel.RenderingContext
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
    TextCase{"125%", 1.25},
]

func loadFonts() throw
{
    g_TypeFace  = try TypeFace.load("segoeui.ttf")
    g_TitleFont = Font.create(assume g_TypeFace, 34, .Bitmap)
    g_LabelFont = Font.create(assume g_TypeFace, 16, .Bitmap)
    g_HelpFont  = Font.create(assume g_TypeFace, 13, .Bitmap)
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
    var ptr = image.pixels.buffer
    for image.width * image.height
    {
        let alpha = ptr[3]
        ptr[0] = unpremultiplyChannel(ptr[0], alpha)
        ptr[1] = unpremultiplyChannel(ptr[1], alpha)
        ptr[2] = unpremultiplyChannel(ptr[2], alpha)
        ptr += 4
    }
}

func flipImageVertical(image: *Image)
{
    var row = Array'u8{}
    row.resize(cast(u64) image.width8)

    var top = image.pixels.buffer
    var bot = image.pixels.buffer + image.width8 * (image.height - 1)
    for image.height / 2
    {
        Memory.copy(row.buffer, top, cast(u64) image.width8)
        Memory.copy(top, bot, cast(u64) image.width8)
        Memory.copy(bot, row.buffer, cast(u64) image.width8)
        top += image.width8
        bot -= image.width8
    }
}

func renderGdiPlusOutlineImage(text: string, scale: f32)->Image
{
    initGdiPlus()

    let emSize  = cast(f32) OutlineFontSize * scale
    let border  = OutlineBorder * scale
    let text16  = Utf16.toZeroTerminated(text)
    let face16  = Utf16.toZeroTerminated("Segoe UI")
    let count16 = cast(s32) (text16.count - 1)

    var family: #null *GpFontFamily
    var format: #null *GpStringFormat
    gdipCheck(GdipCreateFontFamilyFromName(face16.buffer, null, &family))
    gdipCheck(GdipCreateStringFormat(0, 0, &format))

    var measurePath: #null *GpPath
    var bounds: GpRectF
    gdipCheck(GdipCreatePath(GdipFillModeAlternate, &measurePath))
    addGdiPathText(assume measurePath, assume text16.buffer, count16, assume family, assume format, emSize, 0, 0)
    gdipCheck(GdipGetPathWorldBounds(assume measurePath, &bounds, null, null))
    gdipCheck(GdipDeletePath(assume measurePath))

    let margin = cast(f32) OutlineShadowMargin
    let localW = Math.max(cast(s32) Math.ceil(bounds.width + border * 2 + margin * 2), 1)
    let localH = Math.max(cast(s32) Math.ceil(bounds.height + border * 2 + margin * 2), 1)

    var image = Image.create(localW, localH, .BGRA8)
    image.clear()

    var bitmap: #null *GpBitmap
    var graphics: #null *GpGraphics
    gdipCheck(GdipCreateBitmapFromScan0(localW, localH, localW * 4, GdipPixelFormat32bppPARGB, image.pixels.buffer, &bitmap))
    gdipCheck(GdipGetImageGraphicsContext(cast(*GpImage) (assume bitmap), &graphics))
    gdipCheck(GdipSetSmoothingMode(assume graphics, GdipSmoothingModeHighQuality))
    gdipCheck(GdipSetPixelOffsetMode(assume graphics, GdipPixelOffsetModeHighQuality))
    gdipCheck(GdipSetTextRenderingHint(assume graphics, GdipTextRenderingHintAAGridFit))
    gdipCheck(GdipGraphicsClear(assume graphics, 0))

    var path: #null *GpPath
    gdipCheck(GdipCreatePath(GdipFillModeAlternate, &path))
    addGdiPathText(assume path, assume text16.buffer, count16, assume family, assume format, emSize, margin + border - bounds.x, margin + border - bounds.y)

    var pen: #null *GpPen
    var brush: #null *GpSolidFill
    gdipCheck(GdipCreatePen1(cast(u32) Argb.Crimson, border * 2, GdipUnitPixel, &pen))
    gdipCheck(GdipSetPenLineJoin(assume pen, GdipLineJoinRound))
    gdipCheck(GdipCreateSolidFill(cast(u32) Argb.White, &brush))
    gdipCheck(GdipDrawPath(assume graphics, assume pen, assume path))
    gdipCheck(GdipFillPath(assume graphics, cast(*GpBrush) (assume brush), assume path))

    gdipCheck(GdipDeletePen(assume pen))
    gdipCheck(GdipDeleteBrush(cast(*GpBrush) (assume brush)))
    gdipCheck(GdipDeletePath(assume path))
    gdipCheck(GdipDeleteStringFormat(assume format))
    gdipCheck(GdipDeleteFontFamily(assume family))
    gdipCheck(GdipDeleteGraphics(assume graphics))
    gdipCheck(GdipDisposeImage(cast(*GpImage) (assume bitmap)))

    flipImageVertical(&image)
    unpremultiplyImage(&image)
    return image
}

func loadGdiReferences()
{
    for sample, idx in Samples
    {
        let image = renderGdiPlusOutlineImage("Captme", sample.scale)
        g_GdiText[idx] = g_Renderer.addImage(image)
    }
}

func insetRect(rect: Math.Rectangle, left, top, right, bottom: f32)->Math.Rectangle
{
    var result = rect
    result.x += left
    result.y += top
    result.width -= left + right
    result.height -= top + bottom
    return result
}

func drawHeader(painter: *Pixel.Painter)
{
    painter.drawString(34, 28, "Captme outline text quality", assume g_TitleFont, Argb.MidnightBlue)
    painter.drawString(36, 72, "Native GDI+ GraphicsPath reference, Pixel path-stroke outline, and the old offset-fill outline with the same blurred render-target shadow.", assume g_HelpFont, Argb.DimGray)
}

func drawFrame(painter: *Pixel.Painter, rect: Math.Rectangle, title: string)
{
    painter.fillRoundRect(rect, 8, 8, Argb.White)
    painter.drawRoundRect(rect, 8, 8, Color.fromArgb(84, Argb.SlateGray), 1)
    painter.drawString(rect.x + 12, rect.y + 10, title, assume g_LabelFont, Argb.DarkSlateBlue)
}

func makeOutline(text: string, size: u32, embolden: u32)->LinePathList
{
    var result: retval
    assume g_TypeFace.getStringOutline(&result, text, size, embolden)
    result.flatten(.High)
    return result
}

func drawOutlineCore(painter: *Pixel.Painter, outline: *LinePathList, x, y, scale, border: f32, faceColor, outlineColor: Color, mode: OutlineMode)
{
    let drawX = x - ((outline.bvMin.x - border) * scale)
    let drawY = y - ((outline.bvMin.y - border) * scale)

    painter.pushTransform()
    painter.scaleTransform(scale, scale)
    painter.translateTransform(drawX, drawY)

    switch mode
    {
    case OffsetFill:
        if outlineColor.a
        {
            var borderOutline = dref outline
            borderOutline.offset(border, .Round, 0.5)
            painter.fillPath(&borderOutline, outlineColor)
        }

    case PathStroke:
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

    var outline = makeOutline(text, OutlineFontSize, Bold)
    let textWidth = ((outline.bvMax.x - outline.bvMin.x) + 2 * OutlineBorder) * scale
    let textHeight = ((outline.bvMax.y - outline.bvMin.y) + 2 * OutlineBorder) * scale
    let localW = cast(s32) Math.ceil(textWidth + OutlineShadowMargin * 2)
    let localH = cast(s32) Math.ceil(textHeight + OutlineShadowMargin * 2)
    let textX = cast(f32) OutlineShadowMargin
    let textY = cast(f32) OutlineShadowMargin

    let rtText = g_Renderer.getRenderTarget(localW, localH)
    let rtShadow = g_Renderer.getRenderTarget(localW, localH)
    let rtBlur = g_Renderer.getRenderTarget(localW, localH)

    if superSample <= 1
    {
        renderOutlineToTarget(painter, rtText, &outline, textX, textY, scale, mode)
    }
    else
    {
        let ss = cast(f32) superSample
        let rtSuper = g_Renderer.getRenderTarget(localW * superSample, localH * superSample)
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
            .drawTexture(Math.Rectangle{0, 0, cast(f32) localW, cast(f32) localH}, Math.Rectangle{0, 0, cast(f32) (localW * superSample), cast(f32) (localH * superSample)}, rtSuper.colorBuffer)
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
        .drawTexture(Math.Rectangle{0, 0, cast(f32) localW, cast(f32) localH}, Math.Rectangle{0, 0, cast(f32) localW, cast(f32) localH}, rtText.colorBuffer)
        .setShader()
        .unbindRenderTarget()

        .bindRenderTarget(rtShadow)
        .setShader(&g_Renderer.shaderBlur)
        .setShaderParam(g_Renderer.shaderBlur.axis, 1's32)
        .setShaderParam(g_Renderer.shaderBlur.radius, 7.0)
        .setBlendingMode(.Copy)
        .setColorMaskFull()
        .clear(Argb.Zero)
        .drawTexture(Math.Rectangle{0, 0, cast(f32) localW, cast(f32) localH}, Math.Rectangle{0, 0, cast(f32) localW, cast(f32) localH}, rtBlur.colorBuffer, Color.fromArgb(150, Argb.Black))
        .setShader()
        .unbindRenderTarget()
    }

    let dst = Math.Rectangle{area.horzCenter() - localW * 0.5, area.vertCenter() - localH * 0.5, cast(f32) localW, cast(f32) localH}
    let src = Math.Rectangle{0, 0, cast(f32) localW, cast(f32) localH}

    painter.setAntialiased(false)
    painter.drawTexture(Math.Rectangle{dst.x + 5, dst.y + 5, dst.width, dst.height}, src, rtShadow.colorBuffer)
    painter.drawTexture(dst, src, rtText.colorBuffer)

    painter.releaseRenderTarget(rtText)
    painter.releaseRenderTarget(rtShadow)
    painter.releaseRenderTarget(rtBlur)
}

func drawShadowedTexture(painter: *Pixel.Painter, area: Math.Rectangle, texture: Texture)
{
    let localW = texture.width
    let localH = texture.height
    let rtText = g_Renderer.getRenderTarget(localW, localH)
    let rtBlur = g_Renderer.getRenderTarget(localW, localH)
    let src    = Math.Rectangle{0, 0, cast(f32) localW, cast(f32) localH}

    with painter
    {
        .bindRenderTarget(rtText, true)
        .setColorMaskFull()
        .setAntialiased(false)
        .clear(Argb.Zero)
        .setColorMaskColor()
        .setBlendingMode(.Alpha)
        .drawTexture(src, src, texture)
        .unbindRenderTarget()

        .bindRenderTarget(rtBlur)
        .setShader(&g_Renderer.shaderBlur)
        .setShaderParam(g_Renderer.shaderBlur.axis, 0's32)
        .setShaderParam(g_Renderer.shaderBlur.radius, 7.0)
        .setBlendingMode(.Copy)
        .setColorMaskFull()
        .clear(Argb.Zero)
        .drawTexture(src, src, rtText.colorBuffer)
        .setShader()
        .unbindRenderTarget()

        .bindRenderTarget(rtText)
        .setShader(&g_Renderer.shaderBlur)
        .setShaderParam(g_Renderer.shaderBlur.axis, 1's32)
        .setShaderParam(g_Renderer.shaderBlur.radius, 7.0)
        .setBlendingMode(.Copy)
        .setColorMaskFull()
        .clear(Argb.Zero)
        .drawTexture(src, src, rtBlur.colorBuffer, Color.fromArgb(150, Argb.Black))
        .setShader()
        .unbindRenderTarget()
    }

    let dst = Math.Rectangle{area.horzCenter() - localW * 0.5, area.vertCenter() - localH * 0.5, cast(f32) localW, cast(f32) localH}

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

    let body = insetRect(rowRect, 18, 48, 18, 18)
    let gap = 16.0
    let cellW = (body.width - gap * 3) / 4
    for sample, idx in Samples
    {
        let x = body.x + cast(f32) idx * (cellW + gap)
        let cell = Math.Rectangle{x, body.y, cellW, body.height}
        painter.fillRoundRect(cell, 6, 6, Color.fromArgb(255, 247, 249, 251))
        painter.drawRoundRect(cell, 6, 6, Color.fromArgb(32, Argb.SlateGray), 1)
        painter.drawString(cell.x + 10, cell.y + 8, sample.label, assume g_HelpFont, Argb.DimGray)
        let ss = mode == .PathStroke ? OutlineSuperSample : 1
        drawShadowedOutline(painter, insetRect(cell, 8, 22, 8, 8), "Captme", sample.scale, mode, ss)
    }
}

func drawGdiGrid(painter: *Pixel.Painter, rowRect: Math.Rectangle)
{
    drawFrame(painter, rowRect, "GDI+ reference (GraphicsPath DrawPath + FillPath)")

    let body = insetRect(rowRect, 18, 48, 18, 18)
    let gap = 16.0
    let cellW = (body.width - gap * 3) / 4
    for sample, idx in Samples
    {
        let x = body.x + cast(f32) idx * (cellW + gap)
        let cell = Math.Rectangle{x, body.y, cellW, body.height}
        painter.fillRoundRect(cell, 6, 6, Color.fromArgb(255, 247, 249, 251))
        painter.drawRoundRect(cell, 6, 6, Color.fromArgb(32, Argb.SlateGray), 1)
        painter.drawString(cell.x + 10, cell.y + 8, sample.label, assume g_HelpFont, Argb.DimGray)
        drawShadowedTexture(painter, insetRect(cell, 8, 22, 8, 8), g_GdiText[idx])
    }
}

func drawScene(painter: *Pixel.Painter)
{
    painter.clear(Color.fromArgb(255, 242, 244, 248))
    painter.setParams(.Antialiased)
    drawHeader(painter)

    drawGdiGrid(painter, {Margin, 108, W - Margin * 2, 246})
    drawSampleGrid(painter, {Margin, 374, W - Margin * 2, 246}, "Pixel supersampled path-stroke outline", .PathStroke)
    drawSampleGrid(painter, {Margin, 640, W - Margin * 2, 246}, "Legacy offset-fill outline", .OffsetFill)
}

func display()
{
    g_Renderer.begin(g_RC)
    g_Painter.begin()
    drawScene(&g_Painter)
    g_Painter.end()
    g_Renderer.draw(&g_Painter)
    g_Renderer.end()
}

func onResize(_window: *Env.Window, width, height: s32)
{
    g_RC.width  = width
    g_RC.height = height
}

#main
{
    try Env.createWindow(&g_Window, {className: "PIXEL6_CLASS_NAME", title: "Pixel example - Captme text outline quality", width: W, height: H, style: FixedWindowStyle})
    try g_Window.setClientSize(W, H)
    g_RC = try g_Renderer.native.createContext(&g_Window, W, H)
    g_Renderer.setCurrentContext(g_RC)
    g_Renderer.init()

    try loadFonts()
    loadGdiReferences()

    g_Window.callbacks.onResize = &onResize
    try g_Window.show()

    var loop: Env.WindowLoop
    if Env.hasArg("swag.test") do
        loop.maxTestFrames = TestFrames
    while loop.next()
    {
        display()
    }

    g_Renderer.native.dropContext(g_RC)
    shutdownGdiPlus()
}
