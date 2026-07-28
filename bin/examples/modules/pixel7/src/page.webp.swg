using Core, Pixel

func buildWebpPage() fail
{
    let source = loadSource("robot.webp")
    encodeCard'(Webp.Encoder)(&g_Cards[PageWebp][0], "variant.webp", "RGB input", "lossless VP8L", sourceVariant(source, .RGB8))
    encodeCard'(Webp.Encoder)(&g_Cards[PageWebp][1], "variant.webp", "BGR input", "lossless VP8L", sourceVariant(source, .BGR8))
    encodeCard'(Webp.Encoder)(&g_Cards[PageWebp][2], "variant.webp", "RGBA input", "lossless VP8L, opaque alpha", sourceVariant(source, .RGBA8))
    encodeCard'(Webp.Encoder)(&g_Cards[PageWebp][3], "variant.webp", "RGBA with alpha", "lossless VP8L, variable alpha", sourceVariant(source, .RGBA8, true))
}

