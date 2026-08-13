using Core, Pixel

func buildKernelImage(source: Image, kernel: Image.Kernel)->Image
{
    var result = cloneImage(source)
    result.applyKernel(kernel)
    return result
}

func buildWarmGradeImage(source: Image)->Image
{
    var result = cloneImage(source)
    result.colorize(0.08, 0.52, strength: 0.34)
    result.gamma(1.18)
    result.contrast(0.10)
    return result
}

func buildCoolGradeImage(source: Image)->Image
{
    var result = cloneImage(source)
    result.colorize(0.58, 0.46, strength: 0.38)
    result.gamma(1.10)
    result.contrast(0.08)
    return result
}

func buildSepiaImage(source: Image)->Image
{
    var result = cloneImage(source)
    result.grayscale(0.40)
    result.colorize(0.11, 0.38, strength: 0.50)
    result.gamma(1.08)
    return result
}

func buildKernelCards(source: Image)
{
    setImageCard(&g_KernelCards[0], "Sharpen 3x3", "applyKernel(Sharpen3x3Strong)", buildKernelImage(source, .Sharpen3x3Strong))
    setImageCard(&g_KernelCards[1], "Blur 3x3", "applyKernel(GaussianBlur3x3Light)", buildKernelImage(source, .GaussianBlur3x3Light))
    setImageCard(&g_KernelCards[2], "Blur 5x5", "applyKernel(GaussianBlur5x5)", buildKernelImage(source, .GaussianBlur5x5))
    setImageCard(&g_KernelCards[3], "Edge detect", "applyKernel(Laplacian8)", buildKernelImage(source, .Laplacian8))
    setImageCard(&g_KernelCards[4], "Emboss left", "applyKernel(EmbossLeft3x3Light)", buildKernelImage(source, .EmbossLeft3x3Light))
    setImageCard(&g_KernelCards[5], "Warm grade", "colorize + gamma + contrast", buildWarmGradeImage(source))
    setImageCard(&g_KernelCards[6], "Cool grade", "colorize + gamma + contrast", buildCoolGradeImage(source))
    setImageCard(&g_KernelCards[7], "Sepia blend", "grayscale + colorize", buildSepiaImage(source))
}

func drawKernelPage(painter: *Pixel.Painter)
{
    drawPageHeader(painter, "Pixel kernels and grading", "Page 2 : convolution filters and simple color grading, all built from the local source image.")
    for i in CardsPerPage do
        drawCard(painter, getCardRect(i), g_KernelCards[i])
}
