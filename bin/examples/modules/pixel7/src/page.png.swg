using Core, Pixel

func buildPngPage() fail
{
    let source = loadSource("succulent.png")

    encodeCard'(Png.Encoder)(&g_Cards[PagePng][0], "variant.png", "Filtered RGB", "Deflate with adaptive filters", sourceVariant(source, .RGB8))

    var unfiltered: Png.EncodeOptions
    unfiltered.filtering = false
    encodeCard'(Png.Encoder)(&g_Cards[PagePng][1], "variant.png", "Unfiltered RGB", "Deflate without filtering", sourceVariant(source, .RGB8), unfiltered)

    var stored: Png.EncodeOptions
    stored.filtering        = false
    stored.compressionLevel = .NoCompression
    encodeCard'(Png.Encoder)(&g_Cards[PagePng][2], "variant.png", "Stored RGB", "No compression or filtering", sourceVariant(source, .RGB8), stored)

    encodeCard'(Png.Encoder)(&g_Cards[PagePng][3], "variant.png", "Filtered RGBA", "Deflate with adaptive filters", sourceVariant(source, .RGBA8, true))
}

