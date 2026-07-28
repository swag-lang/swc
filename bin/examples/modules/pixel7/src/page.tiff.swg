using Core, Pixel

func buildTiffPage() fail
{
    let source = loadSource("mountain.tiff")

    var packBits: Tiff.EncodeOptions
    packBits.compression = .PackBits

    var lzw: Tiff.EncodeOptions
    lzw.compression = .Lzw

    encodeCard'(Tiff.Encoder)(&g_Cards[PageTiff][0], "variant.tiff", "RGB input", "little-endian RGB, uncompressed", sourceVariant(source, .RGB8))
    encodeCard'(Tiff.Encoder)(&g_Cards[PageTiff][1], "variant.tiff", "BGR input with PackBits", "little-endian RGB, PackBits", sourceVariant(source, .BGR8), packBits)
    encodeCard'(Tiff.Encoder)(&g_Cards[PageTiff][2], "variant.tiff", "RGBA with alpha", "little-endian RGBA, soft alpha border", sourceVariant(source, .RGBA8, true))
    encodeCard'(Tiff.Encoder)(&g_Cards[PageTiff][3], "variant.tiff", "BGRA with alpha and LZW", "little-endian RGBA, LZW with horizontal differencing", sourceVariant(source, .BGRA8, true), lzw)
}
