using Core, Pixel

func addJpgCard(card: *DecoderCard, source: Image, quality: u8) fail
{
    var options: Jpg.EncodeOptions
    options.quality = quality
    let title    = Format.toString("Quality %", quality)
    let encoding = Format.toString("baseline JPEG, quality %", quality)
    encodeCard(card, "variant.jpg", title, encoding, sourceVariant(source, .RGB8), options)
}

func buildJpgPage() fail
{
    let source = loadSource("fox.jpg")
    addJpgCard(&g_Cards[PageJpg][0], source, 100)
    addJpgCard(&g_Cards[PageJpg][1], source, 85)
    addJpgCard(&g_Cards[PageJpg][2], source, 60)
    addJpgCard(&g_Cards[PageJpg][3], source, 30)
}
