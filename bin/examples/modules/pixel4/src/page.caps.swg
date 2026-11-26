using Core, Pixel

struct CapRow
{
    label:  string
    begCap: LineCapStyle
    endCap: LineCapStyle
    color:  Color
}

const CapRows = [
    CapRow{"None / None", .None, .None, Argb.SlateGray},
    CapRow{"Round / Round", .Round, .Round, Argb.Tomato},
    CapRow{"Square / Square", .Square, .Square, Argb.SteelBlue},
    CapRow{"Triangle / Triangle", .Triangle, .Triangle, Argb.MediumSeaGreen},
    CapRow{"Arrow / None", .ArrowAnchor, .None, Argb.DarkOrange},
    CapRow{"None / Arrow 2", .None, .ArrowAnchor2, Argb.MediumPurple},
    CapRow{"Round / Square anchors", .RoundAnchor, .SquareAnchor, Argb.Goldenrod}]

func makeCapPath(left, right, y: f32)->LinePath
{
    var path: #returntype
    path.start(left, y)
    path.lineTo(right, y)
    return path
}

func drawCapRow(painter: *Pixel.Painter, rect: Math.Rectangle, row: CapRow)
{
    let baselineY = Math.round(rect.y + rect.height * 0.62)
    let startX    = rect.x + 250
    let endX      = rect.right() - 38

    painter.fillRect(rect.x, rect.y + rect.height - 1, rect.width, 1, Color.fromArgb(30, Argb.SlateGray))
    drawWrappedText(painter,
                    Math.Rectangle{rect.x + 8, rect.y + 10, 190, rect.height - 14},
                    row.label,
                    g_LabelFont,
                    Argb.DarkSlateGray)

    painter.drawLine(startX, baselineY, endX, baselineY, Color.fromArgb(44, Argb.Black), 2)
    painter.fillCircle(startX, baselineY, 3, Argb.DarkSlateGray)
    painter.fillCircle(endX, baselineY, 3, Argb.DarkSlateGray)

    var path = makeCapPath(startX, endX, baselineY)
    var pen  = Pen.createSolid(row.color, 18)
    pen.begCapStyle = row.begCap
    pen.endCapStyle = row.endCap
    pen.joinStyle   = .Round

    if isAnchorCap(row.begCap)
    {
        pen.capBegScaleX = 2.4
        pen.capBegScaleY = 2.3
    }

    if isAnchorCap(row.endCap)
    {
        pen.capEndScaleX = 2.4
        pen.capEndScaleY = 2.3
    }

    painter.drawPath(&path, pen)
}

func drawCapsPage(painter: *Pixel.Painter)
{
    drawPageHeader(painter,
                   "Pixel path drawing",
                   "Starts, endings and cap styles on the same straight segment.")

    let body = drawPanel(painter,
                         {28, 98, 924, 586},
                         "Caps and endings",
                         "The path starts on the left, ends on the right. Only the pen changes from row to row.")
    painter.drawStringCenter(body.x + 250, body.y + 9, "Path start", g_HelpFont, Argb.DimGray)
    painter.drawStringCenter(body.right() - 38, body.y + 9, "Path end", g_HelpFont, Argb.DimGray)
    const HeaderHeight = 24.0
    let rowHeight = (body.height - HeaderHeight) / cast(f32, CapRows.count)

    painter.pushClippingSurfaceRect(body)
    for i in CapRows.count
    {
        let rowRect = Math.Rectangle{body.x, body.y + HeaderHeight + i * rowHeight, body.width, rowHeight}
        drawCapRow(painter, rowRect, CapRows[i])
    }

    painter.popClippingRect()
}
