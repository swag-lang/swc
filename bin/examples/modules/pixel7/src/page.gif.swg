using Core, Pixel

func buildGifPage() fail
{
    let source = loadSource("jellyfish.gif")
    encodeCard(&g_Cards[PageGif][0], "variant.gif", "Exact RGB palette", "64 colors with LZW", paletteVariant(source, false))
    encodeCard(&g_Cards[PageGif][1], "variant.gif", "Exact transparent palette", "64 colors, transparent border", paletteVariant(source, true))
    encodeCard(&g_Cards[PageGif][2], "variant.gif", "Quantized RGB", "128-color quantized palette", sourceVariant(source, .RGB8))
    encodeCard(&g_Cards[PageGif][3], "variant.gif", "Quantized transparency", "127 colors, soft alpha border", sourceVariant(source, .RGBA8, true))
}
