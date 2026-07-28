using Core, Pixel

func buildTgaPage() fail
{
    let source = loadSource("sailboat.tga")

    var rle: Tga.EncodeOptions
    rle.rle = true

    encodeCard'(Tga.Encoder)(&g_Cards[PageTga][0], "variant.tga", "RGB input", "24-bit true-color", sourceVariant(source, .RGB8))
    encodeCard'(Tga.Encoder)(&g_Cards[PageTga][1], "variant.tga", "BGR input with RLE", "24-bit true-color, RLE packets", sourceVariant(source, .BGR8), rle)
    encodeCard'(Tga.Encoder)(&g_Cards[PageTga][2], "variant.tga", "RGBA with alpha", "32-bit true-color, soft alpha border", sourceVariant(source, .RGBA8, true))
    encodeCard'(Tga.Encoder)(&g_Cards[PageTga][3], "variant.tga", "BGRA with alpha and RLE", "32-bit true-color, RLE packets", sourceVariant(source, .BGRA8, true), rle)
}
