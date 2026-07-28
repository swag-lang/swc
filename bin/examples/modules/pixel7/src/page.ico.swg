using Core, Pixel

func addIcoCard(card: *DecoderCard, source: const &Image, size: s32, pixelFormat: PixelFormat, withAlpha: bool) fail
{
    let resized  = source.toResize(size, size, .Quadratic)
    let title    = Format.toString("% x % icon", size, size)
    let encoding = Format.toString("32-bit DIB from %", pixelFormat)
    encodeCard'(Ico.Encoder)(card, "variant.ico", title, encoding, sourceVariant(resized, pixelFormat, withAlpha))
}

func buildIcoPage() fail
{
    let source = loadSource("controller.ico")
    addIcoCard(&g_Cards[PageIco][0], source, 64, .RGB8, false)
    addIcoCard(&g_Cards[PageIco][1], source, 96, .BGR8, false)
    addIcoCard(&g_Cards[PageIco][2], source, 128, .RGBA8, true)
    addIcoCard(&g_Cards[PageIco][3], source, 256, .BGRA8, true)
}

