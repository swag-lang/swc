struct FormPolygon
{
    using base:     BaseForm
    points:         Array'Math.Vector2

    #[Serialization.NoSerialize]
    {
        gizmo:        GizmoPoints
        linePath:     LinePath
    }
}

impl FormPolygon
{
    mtd setDefaultShape()
    {
        .points.clear()
        .points.add({0, 10})
        .points.add({16, 0})
        .points.add({36, 10})
        .points.add({48, 32})
        .points.add({36, 48})
        .points.add({0, 48})
    }
}

impl IForm for FormPolygon
{
    mtd impl isSame(ptr: #nonull *BaseForm)->bool
    {
        let other = cast(#nonull *FormPolygon) ptr
        return .isSameBase(ptr) and .bezier == other.bezier
    }

    mtd impl copy(dst, src: #nonull *BaseForm)
    {
        BaseForm.copyBase(dst, src)
        let dstf = cast(#nonull *FormPolygon) dst
        let srcf = cast(#nonull *FormPolygon) src
        dstf.bezier = srcf.bezier
    }

    mtd impl edit(evt: #nonull *MouseEvent, movingStart: Math.Point, localPos: Math.Point, zoom: f32)->bool
    {
        if evt.kind == .MouseDoubleClick and evt.button == .Left
        {
            if .points.count > 3 do
                .points.removeBack()
            return false
        }

        let x0 = cast(s32) (localPos.x / zoom)
        let y0 = cast(s32) (localPos.y / zoom)

        if .points.count < 2
        {
            let xs = cast(s32) (movingStart.x / zoom)
            let ys = cast(s32) (movingStart.y / zoom)
            .points.add({xs, ys})
            .points.add({x0, y0})
        }
        elif evt.kind == .MouseReleased and evt.button == .Left
        {
            .points.add({x0, y0})
        }
        else
        {
            .points[.points.count - 1].x = x0
            .points[.points.count - 1].y = y0
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
        scalePointsTo(&.points, .boundRect(), newPosX, newPosY, newSizeX, newSizeY)
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
        return boundOfPoints(&.points)
    }

    mtd impl mouse(view: #nonull *EditView, pos: Math.Point, evt: #nonull *MouseEvent)->bool
    {
        return .gizmo.mouse(view, pos, evt)
    }

    mtd impl paintGizmo(painter: #nonull *Painter, z: f32, flags: FormFlags)
    {
        if flags.has(.Hot | .Selected)
        {
            .gizmo.anchors.clear()
            for pt in .points do
                .gizmo.anchors.add({pt.x * z, pt.y * z})
            let col = .subKind == .PixSel ? Argb.Yellow : Argb.White
            .gizmo.paint(null, painter, !flags.has(.Selected), col)
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

    mtd impl paint(painter: #nonull *Painter, cxt: FormPaintContext)
    {
        var dash  = .dashStyle
        var bSize = cxt.hitTest ? Math.max(.borderSize, 5) : .borderSize
        bSize = BaseForm.adaptSize(bSize, MinBorderSize, MaxBorderSize, cxt)

        let backBrush = Brush.createHatch(.CheckBoardLarge, Argb.DarkGray)
        var bk        = .backColor
        if cxt.quickMode and .alpha != 100 and .subKind == .Highlight do
            bk.a = .highlightAlpha()

        if .subKind == .PixSel
        {
            (bSize, dash) = .applyPixSelStyle(painter, cxt)
            bk.a = 5
        }

        var pen = Pen.createDash(dash, .borderColor, bSize)

        let z = cxt.z
        .linePath.start(.points[0].x * z, .points[0].y * z)
        for i in 1 until .points.count
        {
            if .bezier do
                .linePath.curveTo(.points[i].x * z, .points[i].y * z)
            else do
                .linePath.lineTo(.points[i].x * z, .points[i].y * z)
        }

        .linePath.close()

        if cxt.quickMode
        {
            if .alpha != 100 and .subKind == .Highlight do
                painter.fillPath(&.linePath, backBrush)
            painter.fillPath(&.linePath, bk)
        }
        else do
            painter.fillPolygon(&.linePath, bk)

        pen.joinStyle = .joinStyle
        painter.drawPath(&.linePath, pen)
    }

    mtd impl setup(capt: #nonull *Capture)
    {
        .capture          = capt
        .gizmo.sigChanged = func|form = me|(diff, pt, first)
        {
            GizmoPoints.apply(form, diff, pt, first)
        }
    }
}
