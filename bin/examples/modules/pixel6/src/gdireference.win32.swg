#global if #os == Swag.TargetOs.Windows

using Core, Win32.Gdiplus, Pixel

var g_GdiToken: u64
var g_GdiText:  [SampleCount] Texture

func gdipCheck(status: GpStatus)
{
    Swag.assert(status == GdipOk, "GDI+ call failed")
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
    if not g_GdiToken do
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
    if not alpha do
        return 0
    if alpha == 255 do
        return value

    let result = (cast(u32, value) * 255 + cast(u32, alpha) / 2) / cast(u32, alpha)
    if result > 255 do
        return 255
    return cast(u8, result)
}

func unpremultiplyImage(image: *Image)
{
    var ptr = image.pixels.storage()
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
    row.resize(cast(u64, image.rowStride))

    var top = image.pixels.storage()
    var bot = image.pixels.storage() + image.rowStride * (image.height - 1)
    for image.height / 2
    {
        Memory.copy(row.storage(), top, cast(u64, image.rowStride))
        Memory.copy(top, bot, cast(u64, image.rowStride))
        Memory.copy(bot, row.storage(), cast(u64, image.rowStride))
        top += image.rowStride
        bot -= image.rowStride
    }
}

// `density` is the device pixels per logical unit of the caller: the reference is
// rasterized straight at device resolution so it stays crisp on scaled displays.
func renderGdiPlusOutlineImage(text: string, scale, density: f32)->Image
{
    initGdiPlus()

    let emSize  = cast(f32, OutlineFontSize) * scale * density
    let border  = OutlineBorder * scale * density
    let text16  = Utf16.toZeroTerminated(text)
    let face16  = Utf16.toZeroTerminated("Segoe UI")
    let count16 = cast(s32, (text16.count - 1))

    var family: *GpFontFamily?
    var format: *GpStringFormat?
    gdipCheck(GdipCreateFontFamilyFromName(face16.buffer, null, &family))
    gdipCheck(GdipCreateStringFormat(0, 0, &format))

    var measurePath: *GpPath?
    var bounds:      GpRectF
    gdipCheck(GdipCreatePath(GdipFillModeAlternate, &measurePath))
    Swag.assert(format != null)
    Swag.assert(family != null)
    Swag.assert(measurePath != null)
    addGdiPathText(measurePath, text16.storage(), count16, family, format, emSize, 0, 0)
    gdipCheck(GdipGetPathWorldBounds(measurePath, &bounds, null, null))
    gdipCheck(GdipDeletePath(measurePath))

    let margin = cast(f32, OutlineShadowMargin) * density
    let localW = Math.max(cast(s32, Math.ceil(bounds.width + border * 2 + margin * 2)), 1)
    let localH = Math.max(cast(s32, Math.ceil(bounds.height + border * 2 + margin * 2)), 1)

    var image = Image.create(localW, localH, .BGRA8)
    image.clear()

    var bitmap:   *GpBitmap?
    var graphics: *GpGraphics?
    gdipCheck(GdipCreateBitmapFromScan0(localW,
                                        localH,
                                        localW * 4,
                                        GdipPixelFormat32bppPARGB,
                                        image.pixels.buffer,
                                        &bitmap))
    Swag.assert(bitmap != null)
    gdipCheck(GdipGetImageGraphicsContext(cast(*GpImage, bitmap), &graphics))
    Swag.assert(graphics != null)
    gdipCheck(GdipSetSmoothingMode(graphics, GdipSmoothingModeHighQuality))
    gdipCheck(GdipSetPixelOffsetMode(graphics, GdipPixelOffsetModeHighQuality))
    gdipCheck(GdipSetTextRenderingHint(graphics, GdipTextRenderingHintAAGridFit))
    gdipCheck(GdipGraphicsClear(graphics, 0))

    var path: *GpPath?
    gdipCheck(GdipCreatePath(GdipFillModeAlternate, &path))
    Swag.assert(path != null)
    addGdiPathText(path,
                   text16.storage(),
                   count16,
                   family,
                   format,
                   emSize,
                   margin + border - bounds.x,
                   margin + border - bounds.y)

    var pen:   *GpPen?
    var brush: *GpSolidFill?
    gdipCheck(GdipCreatePen1(cast(u32, Argb.Crimson), border * 2, GdipUnitPixel, &pen))
    Swag.assert(pen != null)
    gdipCheck(GdipSetPenLineJoin(pen, GdipLineJoinRound))
    gdipCheck(GdipCreateSolidFill(cast(u32, Argb.White), &brush))
    gdipCheck(GdipDrawPath(graphics, pen, path))
    Swag.assert(brush != null)
    gdipCheck(GdipFillPath(graphics, cast(*GpBrush, brush), path))

    gdipCheck(GdipDeletePen(pen))
    gdipCheck(GdipDeleteBrush(cast(*GpBrush, brush)))
    gdipCheck(GdipDeletePath(path))
    gdipCheck(GdipDeleteStringFormat(format))
    gdipCheck(GdipDeleteFontFamily(family))
    gdipCheck(GdipDeleteGraphics(graphics))
    gdipCheck(GdipDisposeImage(cast(*GpImage, bitmap)))

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
    let src      = Math.Rectangle{0, 0, cast(f32, devW), cast(f32, devH)}
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

    let dst = Math.Rectangle{
        area.horzCenter() - logicalW * 0.5,
        area.vertCenter() - logicalH * 0.5,
        logicalW,
        logicalH}

    painter.setAntialiased(false)
    painter.drawTexture(Math.Rectangle{dst.x + 5, dst.y + 5, dst.width, dst.height}, src, rtText.colorBuffer)
    painter.drawTexture(dst, src, texture)
    painter.setAntialiased(true)

    painter.releaseRenderTarget(rtText)
    painter.releaseRenderTarget(rtBlur)
}

func drawGdiGrid(painter: *Pixel.Painter, rowRect: Math.Rectangle)
{
    drawFrame(painter, rowRect, "GDI+ reference (GraphicsPath DrawPath + FillPath)")

    let body  = insetRect(rowRect, 18, 48, 18, 18)
    let gap   = 16.0
    let cellW = (body.width - gap * 3) / 4
    for sample, idx in Samples
    {
        let x    = body.x + cast(f32, idx) * (cellW + gap)
        let cell = Math.Rectangle{x, body.y, cellW, body.height}
        painter.fillRoundRect(cell, 6, 6, Color.fromArgb(255, 247, 249, 251))
        painter.drawRoundRect(cell, 6, 6, Color.fromArgb(32, Argb.SlateGray), 1)
        painter.drawString(cell.x + 10, cell.y + 8, sample.label, g_HelpFont, Argb.DimGray)
        drawShadowedTexture(painter, insetRect(cell, 8, 22, 8, 8), g_GdiText[idx])
    }
}
