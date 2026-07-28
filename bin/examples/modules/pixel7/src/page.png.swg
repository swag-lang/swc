using Core, Pixel

func buildPngPage() fail
{
    let source = loadSource("succulent.png")

    encodeCard'(Png.Encoder)(&g_Cards[PagePng][0], "variant.png", "Filtered RGB", "Deflate with adaptive filters", sourceVariant(source, .RGB8))

    var adam7: Png.EncodeOptions
    adam7.interlace = true
    encodeCard'(Png.Encoder)(&g_Cards[PagePng][1], "variant.png", "Adam7 RGB", "Interlaced Deflate with adaptive filters", sourceVariant(source, .RGB8), adam7)

    var stored: Png.EncodeOptions
    stored.filtering        = false
    stored.compressionLevel = .NoCompression
    encodeCard'(Png.Encoder)(&g_Cards[PagePng][2], "variant.png", "Stored RGB", "No compression or filtering", sourceVariant(source, .RGB8), stored)

    encodeCard'(Png.Encoder)(&g_Cards[PagePng][3], "variant.png", "Filtered RGBA with alpha", "Adaptive filters, soft alpha border", sourceVariant(source, .RGBA8, true))
}
