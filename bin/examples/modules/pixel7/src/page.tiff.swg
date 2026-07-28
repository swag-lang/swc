using Core, Pixel

func buildTiffPage() fail
{
    let source = loadSource("mountain.tiff")
    encodeCard'(Tiff.Encoder)(&g_Cards[PageTiff][0], "variant.tiff", "RGB input", "little-endian RGB, uncompressed", sourceVariant(source, .RGB8))
    encodeCard'(Tiff.Encoder)(&g_Cards[PageTiff][1], "variant.tiff", "BGR input", "little-endian RGB, uncompressed", sourceVariant(source, .BGR8))
    encodeCard'(Tiff.Encoder)(&g_Cards[PageTiff][2], "variant.tiff", "RGBA input", "little-endian RGBA, uncompressed", sourceVariant(source, .RGBA8, true))
    encodeCard'(Tiff.Encoder)(&g_Cards[PageTiff][3], "variant.tiff", "BGRA input", "little-endian RGBA, uncompressed", sourceVariant(source, .BGRA8, true))
}

