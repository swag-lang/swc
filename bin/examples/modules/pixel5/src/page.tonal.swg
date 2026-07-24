using Core, Pixel

func buildGrayScaleImage(source: const &Image, factor: f32)->Image
{
    var result = cloneImage(source)
    result.grayScale(factor)
    return result
}

func buildContrastImage(source: const &Image, amount: f32)->Image
{
    var result = cloneImage(source)
    result.contrast(amount)
    return result
}

func buildLightnessImage(source: const &Image, amount: f32)->Image
{
    var result = cloneImage(source)
    result.lightness(amount)
    return result
}

func buildGammaImage(source: const &Image, amount: f32)->Image
{
    var result = cloneImage(source)
    result.gamma(amount)
    return result
}

func buildInvertImage(source: const &Image)->Image
{
    var result = cloneImage(source)
    result.invert()
    return result
}

func buildTonalCards(source: const &Image)
{
    setTextureCard(&g_TonalCards[0], "Original load", "Image.load + addImage", g_SourceTexture)
    setImageCard(&g_TonalCards[1], "Grayscale", "grayScale()", buildGrayScaleImage(source, 1.0))
    setImageCard(&g_TonalCards[2], "Gray blend", "grayScale(0.55)", buildGrayScaleImage(source, 0.55))
    setImageCard(&g_TonalCards[3], "Contrast +", "contrast(0.22)", buildContrastImage(source, 0.22))
    setImageCard(&g_TonalCards[4], "Contrast -", "contrast(-0.18)", buildContrastImage(source, -0.18))
    setImageCard(&g_TonalCards[5], "Lightness +", "lightness(0.18)", buildLightnessImage(source, 0.18))
    setImageCard(&g_TonalCards[6], "Gamma 1.60", "gamma(1.60)", buildGammaImage(source, 1.60))
    setImageCard(&g_TonalCards[7], "Invert", "invert()", buildInvertImage(source))
}

func drawTonalPage(painter: *Pixel.Painter)
{
    drawPageHeader(painter, "Pixel tonal filters", "Page 1 : grayscale, contrast, lightness, gamma and inversion on the same local JPG.")
    for [i] in CardsPerPage do
        drawCard(painter, getCardRect(i), g_TonalCards[i])
}
