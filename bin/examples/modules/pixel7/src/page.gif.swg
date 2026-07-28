using Core, Pixel

func buildGifPage() fail
{
    let source = loadSource("jellyfish.gif")
    encodeCard'(Gif.Encoder)(&g_Cards[PageGif][0], "variant.gif", "Exact RGB palette", "64 colors with LZW", paletteVariant(source, false))
    encodeCard'(Gif.Encoder)(&g_Cards[PageGif][1], "variant.gif", "Exact alpha palette", "64 colors plus transparency", paletteVariant(source, true))
    encodeCard'(Gif.Encoder)(&g_Cards[PageGif][2], "variant.gif", "Quantized RGB", "128-color quantized palette", sourceVariant(source, .RGB8))
    encodeCard'(Gif.Encoder)(&g_Cards[PageGif][3], "variant.gif", "Quantized RGBA", "127 colors plus transparency", sourceVariant(source, .RGBA8, true))
}

