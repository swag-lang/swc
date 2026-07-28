using Core, Pixel

func buildBmpPage() fail
{
    let source = loadSource("rocket.bmp")
    encodeCard'(Bmp.Encoder)(&g_Cards[PageBmp][0], "variant.bmp", "RGB input", "24-bit BI_RGB", sourceVariant(source, .RGB8))
    encodeCard'(Bmp.Encoder)(&g_Cards[PageBmp][1], "variant.bmp", "BGR input", "24-bit BI_RGB", sourceVariant(source, .BGR8))
    encodeCard'(Bmp.Encoder)(&g_Cards[PageBmp][2], "variant.bmp", "RGBA input", "32-bit BI_RGB", sourceVariant(source, .RGBA8, true))
    encodeCard'(Bmp.Encoder)(&g_Cards[PageBmp][3], "variant.bmp", "BGRA input", "32-bit BI_RGB", sourceVariant(source, .BGRA8, true))
}

