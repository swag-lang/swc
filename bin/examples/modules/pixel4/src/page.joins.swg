using Core, Pixel

struct JoinCard
{
    label:     string
    joinStyle: JoinStyle
    color:     Color
}

const JoinCards = [
    JoinCard{"None", .None, Argb.Gray},
    JoinCard{"Bevel", .Bevel, Argb.CadetBlue},
    JoinCard{"Round", .Round, Argb.SeaGreen},
    JoinCard{"Miter", .Miter, Argb.Crimson},
    JoinCard{"Miter bevel", .MiterBevel, Argb.DarkOrchid},
    ]

func makeJoinPath(rect: Math.Rectangle)->LinePath
{
    var path: retval
    let left = rect.x + 20
    let top  = rect.y + rect.height * 0.75
    path.start(left, top)
    path.lineTo(left + rect.width * 0.18, rect.y + rect.height * 0.18)
    path.lineTo(left + rect.width * 0.36, rect.y + rect.height * 0.74)
    path.lineTo(left + rect.width * 0.58, rect.y + rect.height * 0.28)
    path.lineTo(left + rect.width * 0.78, rect.y + rect.height * 0.78)
    path.lineTo(left + rect.width * 0.92, rect.y + rect.height * 0.24)
    return path
}

func getJoinCardRect(index: s32)->Math.Rectangle
{
    if index < 3 do
        return {28 + index * 308, 118, 288, 224}

    return {182 + (index - 3) * 308, 372, 288, 224}
}

func drawJoinCard(painter: *Pixel.Painter, rect: Math.Rectangle, card: JoinCard)
{
    let body = drawPanel(painter, rect, card.label, "")
    var path = makeJoinPath(body)

    var guide = Pen.createSolid(Color.fromArgb(60, Argb.Black), 3)
    guide.begCapStyle = .None
    guide.endCapStyle = .None
    guide.joinStyle   = .Round
    painter.drawPath(&path, guide)

    var pen = Pen.createSolid(card.color, 24)
    pen.begCapStyle    = .None
    pen.endCapStyle    = .None
    pen.joinStyle      = card.joinStyle
    pen.joinMiterLimit = 1.7
    painter.drawPath(&path, pen)
}

func drawJoinsPage(painter: *Pixel.Painter)
{
    drawPageHeader(painter, "Pixel path drawing", "Page 2 : join handling on sharp bends and reflex angles.")

    for [i] in @countof(JoinCards)
    {
        drawJoinCard(painter, getJoinCardRect(i), JoinCards[i])
    }
}
