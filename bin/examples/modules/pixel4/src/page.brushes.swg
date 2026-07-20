using Core, Pixel

func drawBrushCellBackground(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    painter.fillRoundRect(rect, 18, 18, Color.fromArgb(255, 250, 251, 252))
    painter.drawRoundRect(rect, 18, 18, Color.fromArgb(42, Argb.SlateGray), 1)
}

func drawBrushCellLabel(painter: *Pixel.Painter, rect: Math.Rectangle, title, subtitle: string)
{
    painter.drawString(rect.x + 18, rect.bottom() - 48, title, assume g_LabelFont, Argb.DarkSlateBlue)
    drawWrappedText(painter, {rect.x + 18, rect.bottom() - 28, rect.width - 36, 24}, subtitle, assume g_HelpFont, Argb.DimGray)
}

func drawFilledBrushCells(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let cellGap    = 20.0
    let cellWidth  = (rect.width - 2 * cellGap) / 3.0
    let leftCell   = Math.Rectangle{rect.x, rect.y, cellWidth, rect.height}
    let middleCell = Math.Rectangle{leftCell.right() + cellGap, rect.y, cellWidth, rect.height}
    let rightCell  = Math.Rectangle{middleCell.right() + cellGap, rect.y, cellWidth, rect.height}

    drawBrushCellBackground(painter, leftCell)
    drawBrushCellBackground(painter, middleCell)
    drawBrushCellBackground(painter, rightCell)

    {
        let shapeRect = insetRect(leftCell, 26, 22, 26, 82)
        let fillBrush = Brush.createTexture(g_FillTexture)
        var pen       = Pen.createHatch(.DiagonalCross, Color.fromArgb(210, Argb.MidnightBlue), 10)
        pen.borderPos = .Inside
        pen.joinStyle = .Round
        painter.fillRoundRect(shapeRect, 30, 30, fillBrush)
        painter.drawRoundRect(shapeRect, 30, 30, pen)
        drawBrushCellLabel(painter, leftCell, "Full texture fill", "Brush.createTexture + Pen.createHatch")
    }

    {
        let center    = Math.Vector2{middleCell.horzCenter(), middleCell.y + middleCell.height * 0.40}
        let fillBrush = Brush.createTiled(g_TileTexture)
        var pen       = Pen.createSolid(Argb.White, 16)
        pen.brush     = Brush.createTexture(g_FillTexture)
        pen.borderPos = .Inside
        painter.fillCircle(center.x, center.y, 72, fillBrush)
        painter.drawCircle(center.x, center.y, 72, pen)
        drawBrushCellLabel(painter, middleCell, "Tiled texture fill", "Brush.createTiled + textured outline")
    }

    {
        let center    = Math.Vector2{rightCell.horzCenter(), rightCell.y + rightCell.height * 0.38}
        let star      = makeStarPolygon(center.x, center.y, 82, 36, 6)
        let fillBrush = Brush.createHatch(.OutlinedDiamond, Color.fromArgb(224, Argb.DarkMagenta))
        var pen       = Pen.createSolid(Argb.White, 12)
        pen.brush     = Brush.createTiled(g_TileTexture)
        pen.joinStyle = .Round
        painter.fillPolygon(star[to], fillBrush)
        drawClosedOutline(painter, star[to], pen)
        drawBrushCellLabel(painter, rightCell, "Hatch fill", "Brush.createHatch + tiled outline")
    }
}

func drawOutlinedBrushCells(painter: *Pixel.Painter, rect: Math.Rectangle)
{
    let cellGap    = 20.0
    let cellWidth  = (rect.width - 2 * cellGap) / 3.0
    let leftCell   = Math.Rectangle{rect.x, rect.y, cellWidth, rect.height}
    let middleCell = Math.Rectangle{leftCell.right() + cellGap, rect.y, cellWidth, rect.height}
    let rightCell  = Math.Rectangle{middleCell.right() + cellGap, rect.y, cellWidth, rect.height}

    drawBrushCellBackground(painter, leftCell)
    drawBrushCellBackground(painter, middleCell)
    drawBrushCellBackground(painter, rightCell)

    {
        let shapeRect = insetRect(leftCell, 26, 22, 26, 82)
        var pen       = Pen.createHatch(.Weave, Color.fromArgb(220, Argb.Teal), 18)
        pen.borderPos = .Inside
        pen.joinStyle = .Round
        painter.drawRoundRect(shapeRect, 26, 26, pen)
        drawBrushCellLabel(painter, leftCell, "Hatch pen", "Outlined round rectangle")
    }

    {
        let shapeRect = insetRect(middleCell, 26, 22, 26, 82)
        var blob      = makeBlobPath(shapeRect)
        blob.flatten(.Normal)
        var pen       = Pen.createSolid(Argb.White, 18)
        pen.brush     = Brush.createTexture(g_FillTexture)
        pen.joinStyle = .Round
        painter.drawPath(&blob, pen)
        drawBrushCellLabel(painter, middleCell, "Texture pen", "Curved outline with a stretched brush")
    }

    {
        let body   = insetRect(rightCell, 26, 16, 26, 82)
        let points = makeArrowPolygon(body)
        var pen    = Pen.createSolid(Argb.White, 16)
        pen.brush  = Brush.createTiled(g_TileTexture)
        pen.joinStyle = .Round
        drawClosedOutline(painter, points[to], pen)
        drawBrushCellLabel(painter, rightCell, "Tiled texture pen", "Polygon outline repeating the pattern")
    }
}

func drawBrushesPage(painter: *Pixel.Painter)
{
    drawPageHeader(painter, "Pixel brush rendering", "Page 5 : drawing and filling forms with texture, tiled and hatch brushes.")

    let fillBody = drawPanel(painter, {28, 104, 924, 272}, "Filled forms", "Three non-solid brushes filling the same kinds of primitives used across the showcase.")
    drawFilledBrushCells(painter, fillBody)

    let drawBody = drawPanel(painter, {28, 402, 924, 262}, "Drawn forms", "The same brush family can drive pen strokes as well, including closed paths and rounded geometry.")
    drawOutlinedBrushCells(painter, drawBody)
}
