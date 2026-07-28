using Core, Pixel

func buildTgaPage() fail
{
    let source = loadSource("sailboat.tga")
    encodeCard'(Tga.Encoder)(&g_Cards[PageTga][0], "variant.tga", "RGB input", "24-bit true-color", sourceVariant(source, .RGB8))
    encodeCard'(Tga.Encoder)(&g_Cards[PageTga][1], "variant.tga", "BGR input", "24-bit true-color", sourceVariant(source, .BGR8))
    encodeCard'(Tga.Encoder)(&g_Cards[PageTga][2], "variant.tga", "RGBA input", "32-bit true-color", sourceVariant(source, .RGBA8, true))
    encodeCard'(Tga.Encoder)(&g_Cards[PageTga][3], "variant.tga", "BGRA input", "32-bit true-color", sourceVariant(source, .BGRA8, true))
}

