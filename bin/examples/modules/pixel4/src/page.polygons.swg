using Core, Pixel

func addPolygonPath(path: *LinePath, points: [..] Math.Vector2)
{
    if @countof(points) < 2 do
        return

    path.start(points[0].x, points[0].y)
    for pt in points where @index do
        path.lineTo(pt.x, pt.y)
    path.close()
}

func buildPolygonHoleList(rect: Math.Rectangle)->LinePathList
{
    var result: retval
    let cx = rect.horzCenter()
    let cy = rect.vertCenter() + 4

    let outer = makeHexPolygon(cx, cy, Math.min(rect.width, rect.height) * 0.34)
    let inner = [
        Math.Vector2{cx, cy - 42},
        Math.Vector2{cx + 42, cy},
        Math.Vector2{cx, cy + 42},
        Math.Vector2{cx - 42, cy},
        ]

    {
        let path = result.newPath()
        addPolygonPath(path, outer[to])
    }

    {
        let path = result.newPath()
        path.start(inner[0].x, inner[0].y)
        for i in 1 to @countof(inner)
        {
            let idx = @countof(inner) - i
            path.lineTo(inner[idx].x, inner[idx].y)
        }
        path.close()
    }

    return result
}

func drawPolygonSamplesCard(painter: *Pixel.Painter, rect: Math.Rectangle, title, subtitle: string, fillColor, strokeColor: Color, points0, points1: [..] Math.Vector2)
{
    let body   = drawPanel(painter, rect, title, subtitle)
    let center = body.horzCenter()

    painter.drawLine(center, body.y + 14, center, body.bottom() - 14, Color.fromArgb(26, Argb.SlateGray), 1)

    painter.fillPolygon(points0, Brush.createSolid(fillColor))
    drawClosedOutline(painter, points0, Pen.createSolid(strokeColor, 4))

    painter.fillPolygon(points1, Brush.createSolid(fillColor))
    drawClosedOutline(painter, points1, Pen.createSolid(strokeColor, 4))
}

func drawPolygonHoleCard(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let body = drawPanel(painter, rect, "Winding and holes", "Outer ring filled, inner ring reversed to carve a hole.")
    var list = buildPolygonHoleList(body)

    painter.fillPath(&list, Color.fromArgb(214, Argb.MediumPurple))

    var outlinePen = Pen.createSolid(Argb.Indigo, 4)
    outlinePen.begCapStyle = .None
    outlinePen.endCapStyle = .None
    outlinePen.joinStyle   = .Round
    painter.drawPath(&list, outlinePen)

    drawWrappedText(painter, {body.x + 22, body.bottom() - 38, body.width - 44, 24}, "Counter-wound inner contour", notnull g_HelpFont, Argb.Indigo)
}

func drawPolygonsPage(painter: *Pixel.Painter)
{
    drawPageHeader(painter, "Pixel polygon rendering", "Page 4 : convex fills, concave triangulation and polygon winding for holes.")

    let convexRect   = Math.Rectangle{28, 110, 452, 248}
    let concaveRect  = Math.Rectangle{500, 110, 452, 248}
    let holeRect     = Math.Rectangle{28, 386, 924, 276}
    let convexLeft   = insetRect(convexRect, 36, 88, 246, 26)
    let convexRight  = insetRect(convexRect, 246, 88, 36, 26)
    let concaveLeft  = insetRect(concaveRect, 36, 88, 246, 26)
    let concaveRight = insetRect(concaveRect, 246, 88, 36, 26)

    let diamond = [
        Math.Vector2{convexLeft.horzCenter(), convexLeft.y + 10},
        Math.Vector2{convexLeft.right() - 18, convexLeft.vertCenter()},
        Math.Vector2{convexLeft.horzCenter(), convexLeft.bottom() - 10},
        Math.Vector2{convexLeft.x + 18, convexLeft.vertCenter()},
        ]
    let hexagon = makeHexPolygon(convexRight.horzCenter(), convexRight.vertCenter(), 58)

    let star  = makeStarPolygon(concaveLeft.horzCenter(), concaveLeft.vertCenter(), 62, 26, 5)
    let arrow = makeArrowPolygon(concaveRight)

    drawPolygonSamplesCard(painter, convexRect, "Convex polygons", "Direct fills with clean straight edges and sharp corners.", Argb.CadetBlue, Argb.MidnightBlue, diamond[to], hexagon[to])
    drawPolygonSamplesCard(painter, concaveRect, "Concave polygons", "Non-convex fills go through polygon cleaning and triangulation.", Argb.Goldenrod, Argb.SaddleBrown, star[to], arrow[to])
    drawPolygonHoleCard(painter, holeRect)
}
