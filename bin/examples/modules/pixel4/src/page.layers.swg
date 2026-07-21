using Core, Pixel

func drawLayerArtwork(painter: *Pixel.Painter, width, height: s32, label: string, accent: Color)
{
    let w = cast(f32) width
    let h = cast(f32) height

    painter.fillRoundRect(16, 18, w - 32, h - 36, 24, 24, Color.fromArgb(232, Argb.White))
    painter.fillCircle(78, 78, 48, Color.fromArgb(190, Argb.DeepSkyBlue))
    painter.fillCircle(136, 76, 46, Color.fromArgb(180, Argb.Tomato))
    painter.fillCircle(104, 116, 42, Color.fromArgb(180, Argb.Goldenrod))

    var path: LinePath
    path.start(w - 136, 44)
    path.bezierTo(w - 70, 12, w - 30, 72, w - 92, 116)
    path.bezierTo(w - 150, 158, w - 196, 92, w - 136, 44)
    path.close()
    painter.fillPath(&path, Brush.createTexture(g_FillTexture))

    var pen = Pen.createSolid(Argb.White, 7)
    pen.brush     = Brush.createTiled(g_TileTexture)
    pen.joinStyle = .Round
    painter.drawPath(&path, pen)

    let textSize = Painter.measureString(label, notnull g_SubTitleFont)
    let textX = w * 0.5 - textSize.width * 0.5
    let textY = h - 52
    var textBack = accent
    textBack.a = 224
    painter.fillRoundRect(textX - 12, textY - 8, textSize.width + 24, textSize.height + 16, 10, 10, textBack)
    painter.drawString(textX, textY, label, notnull g_SubTitleFont, Argb.White)
}

func drawLayerCard(painter: *Pixel.Painter, rect: Math.Rectangle, title, subtitle: string, renderScale: s32, shadow: bool, angle: Math.Angle, accent: Color)
{
    let body = drawPanel(painter, rect, title, subtitle)
    let layerWidth  = 310
    let layerHeight = 170
    let dstRect = Math.Rectangle{body.horzCenter() - layerWidth * 0.5, body.vertCenter() - layerHeight * 0.5 + 8, layerWidth, layerHeight}

    painter.fillRoundRect(insetRect(body, 18, 14, 18, 14), 18, 18, Brush.createTiled(g_TileTexture))

    var layer: Layer
    layer.begin(&g_Renderer, painter, {width: layerWidth, height: layerHeight, renderScale: renderScale})
    painter.pushTransform()
    painter.scaleTransform(cast(f32) renderScale)
    drawLayerArtwork(painter, layerWidth, layerHeight, title, accent)
    painter.popTransform()
    layer.end()

    var drawInfo: LayerDrawInfo
    drawInfo.dstRect           = dstRect
    drawInfo.interpolationMode = .Linear
    drawInfo.shadow.enabled    = shadow
    drawInfo.shadow.offsetX    = 12
    drawInfo.shadow.offsetY    = 16
    drawInfo.shadow.radius     = 8

    painter.pushTransform()
    painter.rotateTransform(angle, dstRect.horzCenter(), dstRect.vertCenter())
    layer.draw(drawInfo)
    painter.popTransform()
}

func drawLayerPipelinePage(painter: *Pixel.Painter)
{
    drawPageHeader(painter, "Pixel layers", "Page 11 : offscreen layers, supersample resolve, blur shadows and alpha-safe composition.")
    drawLayerCard(painter, {28, 104, 452, 258}, "Layer", "begin / paint / end records a transparent layer and keeps alpha coverage isolated.", 1, false, -4.0'deg, Argb.MidnightBlue)
    drawLayerCard(painter, {500, 104, 452, 258}, "Resolve", "renderScale draws into a larger target, then shaderResolve downsamples before composition.", 3, false, 5.0'deg, Argb.Crimson)
    drawLayerCard(painter, {28, 392, 452, 272}, "Shadow", "The layer pipeline can expand into blur passes before drawing the original content back.", 1, true, -3.0'deg, Argb.SeaGreen)
    drawLayerCard(painter, {500, 392, 452, 272}, "Together", "Supersampled content, shadow blur and Max alpha composition share the same LayerDrawInfo path.", 2, true, 4.0'deg, Argb.DarkSlateBlue)
}
