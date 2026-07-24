using Core, Pixel

func buildFaceSourceRect()->Math.Rectangle
{
    let width  = cast(f32) g_SourceTexture.width
    let height = cast(f32) g_SourceTexture.height
    return {width * 0.24, height * 0.18, width * 0.34, height * 0.40}
}

func buildWideSourceRect()->Math.Rectangle
{
    let width  = cast(f32) g_SourceTexture.width
    let height = cast(f32) g_SourceTexture.height
    return {width * 0.12, height * 0.24, width * 0.68, height * 0.34}
}

func buildPainterCards(_source: const &Image)
{
    let faceRect = buildFaceSourceRect()
    let wideRect = buildWideSourceRect()

    setTextureCard(&g_PainterCards[0], "Fitted draw", "drawTexture(dstRect, texture)", g_SourceTexture)
    setTextureCard(&g_PainterCards[1], "Rotate 10 deg", "rotateTransform(10 deg)", g_SourceTexture, {angle: 10.0'deg})
    setTextureCard(&g_PainterCards[2], "Rotate + scale", "rotateTransform(-12 deg)", g_SourceTexture, {angle: -12.0'deg, scale: 0.88})
    setTextureCard(&g_PainterCards[3], "Scale 70%", "smaller destination rect", g_SourceTexture, {scale: 0.70})
    setTextureCard(&g_PainterCards[4], "Face zoom linear", "drawTexture(dstRect, srcRect)", g_SourceTexture, {sourceRect: faceRect})
    setTextureCard(&g_PainterCards[5], "Face zoom pixel", "InterpolationMode.Pixel", g_SourceTexture, {sourceRect: faceRect, interpolation: .Pixel})
    setTextureCard(&g_PainterCards[6], "Offset draw", "same texture with an inner offset", g_SourceTexture, {scale: 0.84, offsetX: 18, offsetY: -10})
    setTextureCard(&g_PainterCards[7], "Wide source rect", "drawTexture(dstRect, srcRect)", g_SourceTexture, {sourceRect: wideRect})
}

func drawPainterPage(painter: *Pixel.Painter)
{
    drawPageHeader(painter, "Pixel painter transforms", "Page 4 : draw-time rotation, sampling, source-rect zoom and scaled presentation on the same texture.")
    for [i] in CardsPerPage do
        drawCard(painter, getCardRect(i), g_PainterCards[i])
}
