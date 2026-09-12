using Core, Pixel

func buildTgaPage() fail
{
    let source = try loadSource("sailboat.tga")

    var rle: Tga.EncodeOptions
    rle.rle = true

    try encodeCard(&g_Cards[PageTga][0], "variant.tga", "RGB input", "24-bit true-color", sourceVariant(source, .RGB8))
    try encodeCard(&g_Cards[PageTga][1], "variant.tga", "BGR input with RLE", "24-bit true-color, RLE packets", sourceVariant(source, .BGR8), rle)
    try encodeCard(&g_Cards[PageTga][2], "variant.tga", "RGBA with alpha", "32-bit true-color, soft alpha border", sourceVariant(source, .RGBA8, true))
    try encodeCard(&g_Cards[PageTga][3], "variant.tga", "BGRA with alpha and RLE", "32-bit true-color, RLE packets", sourceVariant(source, .BGRA8, true), rle)
}
