struct FormDraw
{
    using base: BaseForm
    points:     Array'Math.Vector2
    anchorSize: f32 = 12
}

impl FormDraw
{
    mtd setDefaultShape()
    {
        .points.clear()
        .points.add({48, 0})
        .points.add({0, 12})
        .points.add({34, 28})
        .points.add({0, 48})
    }
}

impl IForm for FormDraw
{
    mtd impl isSame(ptr: *BaseForm)->bool
    {
        return .isSameBase(ptr)
    }

    mtd impl copy(dst, src: *BaseForm)
    {
        BaseForm.copyBase(dst, src)
    }

    mtd impl edit(evt: *MouseEvent, movingStart: Math.Point, localPos: Math.Point, zoom: f32)->bool
    {
        if evt.kind == .MouseReleased and evt.button == .Left do
            return false

        let x0 = localPos.x / zoom
        let y0 = localPos.y / zoom

        if .points.count < 2
        {
            let xs = movingStart.x / zoom
            let ys = movingStart.y / zoom
            .points.add({xs, ys})
            .points.add({x0, y0})
        }
        elif evt.kind == .MouseMove
        {
            let xs = Math.abs(x0 - .points.back().x)
            let ys = Math.abs(y0 - .points.back().y)
            if xs > 5 or ys > 5 do
                .points.add({x0, y0})
        }
        else
        {
            .points[.points.count - 1] = {x0, y0}
        }

        return true
    }

    mtd impl moveBaseForm(newPosX, newPosY, newSizeX, newSizeY: s32)
    {
        offsetPoints(&.points, newPosX, newPosY)
    }

    mtd impl scaleBaseForm(scale: f32)
    {
        scalePointsBy(&.points, scale)
    }

    mtd impl setBaseForm(newPosX, newPosY, newSizeX, newSizeY: s32)
    {
        var bound = .boundRect()
        bound.inflate(-.borderSize * 0.5)
        scalePointsTo(&.points, bound, newPosX, newPosY, newSizeX, newSizeY)
    }

    mtd impl moveForm(newPosX, newPosY: s32)
    {
        offsetPoints(&.points, newPosX, newPosY)
    }

    mtd impl movePoint(pt: u32, newPosX, newPosY: s32)
    {
        .points[pt].x += newPosX
        .points[pt].y += newPosY
    }

    mtd impl boundRect()->Math.Rectangle
    {
        if !.points.count do
            .setDefaultShape()
        return boundOfPoints(&.points, .borderSize * 0.5)
    }

    mtd impl mouse(view: *EditView, pos: Math.Point, evt: *MouseEvent)->bool
    {
        return false
    }

    mtd impl paintGizmo(painter: *Painter, z: f32, flags: FormFlags)
    {
        if flags.has(.Hot | .Selected)
        {
            let anchorSize2 = .anchorSize * 0.5
            let col         = .subKind == .PixSel ? Argb.Yellow : Argb.White
            let color       = Color.getBlend(Argb.Black, col, (flags & .Hot) ? 0.8 : 1)

            let start = .points[0] * z
            painter.fillCircle(start.x, start.y, anchorSize2, color)
            painter.drawCircle(start.x, start.y, anchorSize2, Argb.Black, anchorSize2 * 0.3)
            let end = .points.back() * z
            painter.fillCircle(end.x, end.y, anchorSize2, color)
            painter.drawCircle(end.x, end.y, anchorSize2, Argb.Black, anchorSize2 * 0.3)
        }
    }

    mtd impl isInside(pt: Math.Point)->bool
    {
        return Math.Geometry.polyContains(.points, {pt.x, pt.y})
    }

    mtd impl hitTest(pt: Math.Point, z: f32)->bool
    {
        return BaseForm.drawHitTest(me, pt, z)
    }

    mtd impl paint(painter: *Painter, cxt: FormPaintContext)
    {
        var dash  = .dashStyle
        var bSize = BaseForm.adaptSize(.borderSize, MinBorderSize, MaxBorderSize, cxt)
        bSize = Math.max(bSize, 2)

        let z   = cxt.z
        var pl: LinePath
        pl.start(.points[0].x * z, .points[0].y * z)
        for i in 1 until .points.count do
            pl.lineTo(.points[i].x * z, .points[i].y * z)

        if .subKind == .PixSel
        {
            pl.close()
                (bSize, dash) = .applyPixSelStyle(painter, cxt)
            .backColor.a = 5
            painter.fillPath(&pl, .backColor)
        }

        var pen = Pen.createDash(dash, .borderColor, bSize)
        pen.joinStyle = .Round

        if cxt.quickMode and .alpha != 100 and .subKind == .Highlight
        {
            var pen1 = pen
            pen1.brush = Brush.createHatch(.CheckBoardLarge, Argb.DarkGray)
            painter.drawPath(&pl, pen1)
            pen.brush.color.a = .highlightAlpha()
        }

        painter.drawPath(&pl, pen)
    }

    mtd impl setup(capt: *Capture)
    {
        .capture = capt
    }
}
