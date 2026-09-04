#[Swag.Using(Properties)]
#[Serialization.TypeKey("swag.capture.form.line")]
struct FormLine
{
    using base: BaseForm
    #[Name("Outline"), SliderMinMax(MinOutlineSize, MaxOutlineSize)]
    outlineSize:  f32
    outlineColor: Color        = Argb.Black
    beginCap:     LineCapStyle = .Round
    endCap:       LineCapStyle = .Round
    dashCap:      DashCapStyle = .None
    #[Name("Start Size"), SliderMinMax(MinCapSize, MaxCapSize)]
    startSize: f32 = 4
    #[Name("End Size"), SliderMinMax(MinCapSize, MaxCapSize)]
    endSize:        f32 = 4
    xa, ya, xb, yb: f32
    xc, yc:         f32 = 10
    cacheCoords:    Math.Rectangle
    cacheCoords2:   Math.Point
    cacheBv:        Math.Rectangle

    #[Serialization.NoSerialize]
    {
        gizmo: GizmoPoints
    }
}

impl FormLine
{
    // The stroke and the two line-end scales this line paints with in one context.
    //
    // A preset cell reads the same values to know how much room its sample needs, so the
    // preview sizes cannot drift away from the room reserved for them and leave an arrow
    // head cut flat by the edge of its cell.
    mtd paintSizes(cxt: FormPaintContext)->{ stroke: f32, begScale: f32, endScale: f32 }
    {
        var result: retval
        let base = cxt.hitTest ? Math.max(.borderSize, 5) : .borderSize
        result.stroke   = BaseForm.adaptSize(base, MinBorderSize, MaxBorderSize, cxt, 6, 9)
        result.begScale = cxt.quickMode ? BaseForm.adaptSize(.startSize, MinCapSize, MaxCapSize, cxt, 1, 3) : .startSize
        result.endScale = cxt.quickMode ? BaseForm.adaptSize(.endSize, MinCapSize, MaxCapSize, cxt, 1, 3) : .endSize
        return result
    }

    // The contour keeps this logical thickness at every zoom, like the contour of a text path.
    mtd paintOutlineSize(cxt: FormPaintContext)->f32
    {
        return BaseForm.adaptSize(.outlineSize, MinOutlineSize, MaxOutlineSize, cxt, 0, 3)
    }

    // The pen one paint of this line uses, contour included.
    //
    // The contour is the pen's own border: the renderer keeps the silhouette of the stroke it
    // draws and pushes it out by `outline`, so the shaft, every dash end and an arrow head all
    // carry the same thickness of it. Stroking a second, wider pen underneath instead gave a
    // proportionally larger arrow, whose black edge thinned along each of its sloped sides, and a
    // dash pattern measured against that wider stroke, which no longer lined up with the dashes
    // drawn over it.
    mtd createPaintPen(color: Color, stroke, begScale, endScale, outline: f32)->Pen
    {
        with var result = Pen.createDash(.dashStyle, color, stroke)
        {
            .dashBlankScale  = 0.25
            .begCapStyle     = me.beginCap
            .endCapStyle     = me.endCap
            .capBegScaleX    = begScale
            .capEndScaleX    = endScale
            .capBegScaleY    = 2
            .capEndScaleY    = 2
            .dashBegCapStyle = me.dashCap
            .dashEndCapStyle = me.dashCap
            .outlineSize     = outline
            .outlineColor    = me.outlineColor
        }

        return result
    }
}

impl IForm for FormLine
{
    mtd impl isSame(ptr: *BaseForm)->bool
    {
        let other = cast(*FormLine) ptr
        return .isSameBase(ptr) and
               .outlineSize == other.outlineSize and
               .outlineColor == other.outlineColor and
               .beginCap == other.beginCap and
               .endCap == other.endCap and
               .startSize == other.startSize and
               .endSize == other.endSize and
               .dashCap == other.dashCap and
               .bezier == other.bezier
    }

    mtd impl copy(dst, src: *BaseForm)
    {
        BaseForm.copyBase(dst, src)
        let dstf = cast(*FormLine) dst
        let srcf = cast(*FormLine) src
        dstf.outlineSize  = srcf.outlineSize
        dstf.outlineColor = srcf.outlineColor
        dstf.beginCap     = srcf.beginCap
        dstf.endCap       = srcf.endCap
        dstf.startSize    = srcf.startSize
        dstf.endSize      = srcf.endSize
        dstf.dashCap      = srcf.dashCap
        dstf.bezier       = srcf.bezier
    }

    mtd impl edit(evt: *MouseEvent, movingStart: Math.Point, localPos: Math.Point, zoom: f32)->bool
    {
        .xa = cast(s32) (movingStart.x / zoom)
        .ya = cast(s32) (movingStart.y / zoom)
        .xb = cast(s32) (localPos.x / zoom)
        .yb = cast(s32) (localPos.y / zoom)

        var xbu     = 0
        var ybu     = 0
        let capture = .capture!
        capture.snap(&xbu, &ybu, true, true, 1, me)
        .xb += xbu
        .yb += ybu

        if evt.kind == .Released and evt.button == .Left do
            return false
        return true
    }

    mtd impl moveBaseForm(newPosX, newPosY, newSizeX, newSizeY: s32)
    {
        .xa, .xb += newPosX
        .ya, .yb += newPosY
    }

    mtd impl scaleBaseForm(scale: f32)
    {
        .xa, .xb *= scale
        .ya, .yb *= scale
    }

    mtd impl setBaseForm(newPosX, newPosY, newSizeX, newSizeY: s32)
    {
        .xa = newPosX
        .ya = newPosY
        .xb = .xa + newSizeX
        .yb = .ya + newSizeY
    }

    mtd impl moveForm(newPosX, newPosY: s32)
    {
        .xa, .xb += newPosX
        .ya, .yb += newPosY
    }

    mtd impl movePoint(pt: u32, newPosX, newPosY: s32)
    {
        switch pt
        {
        case 0:
            .xa += newPosX
            .ya += newPosY

        case 1:
            .xb += newPosX
            .yb += newPosY

        case 2:
            .xc += newPosX
            .yc += newPosY
        }
    }

    mtd impl boundRect()->Math.Rectangle
    {
        if .bezier
        {
            let newCoords  = Math.Rectangle{.xa, .ya, .xb, .yb}
            let newCoords2 = Math.Point{.xc, .yc}
            if .cacheCoords == newCoords and .cacheCoords2 == newCoords2 do
                return .cacheBv
            .cacheCoords  = newCoords
            .cacheCoords2 = newCoords2
            .cacheBv      = Math.Curve.bezierBounds({.xa, .ya}, {.xb, .yb}, {.xa + .xc, .ya + .yc})
        }
        else
        {
            let x0 = Math.min(.xa, .xb)
            let y0 = Math.min(.ya, .yb)
            let x1 = Math.max(.xa, .xb)
            let y1 = Math.max(.ya, .yb)
            .cacheBv = Math.Rectangle{x0, y0, x1 - x0, y1 - y0}
        }

        return .cacheBv
    }

    mtd impl mouse(view: *EditView, pos: Math.Point, evt: *MouseEvent)->bool
    {
        return .gizmo.mouse(view, pos, evt)
    }

    mtd impl paintGizmo(painter: *Painter, z: f32, flags: FormFlags)
    {
        if flags.has(.Hot | .Selected)
        {
            .gizmo.anchors[0] = {.xa * z, .ya * z}
            .gizmo.anchors[1] = {.xb * z, .yb * z}
            if .gizmo.anchors.count == 3
            {
                .gizmo.anchors[2] = {(.xa + .xc) * z, (.ya + .yc) * z}
                painter.drawLine(.gizmo.anchors[0].x, .gizmo.anchors[0].y, .gizmo.anchors[2].x, .gizmo.anchors[2].y, Argb.White, 2)
                painter.drawLine(.gizmo.anchors[1].x, .gizmo.anchors[1].y, .gizmo.anchors[2].x, .gizmo.anchors[2].y, Argb.White, 2)
            }

            .gizmo.paint(null, painter, !flags.has(.Selected))
        }
    }

    mtd impl isInside(pt: Math.Point)->bool
    {
        return false
    }

    mtd impl hitTest(pt: Math.Point, z: f32)->bool
    {
        return BaseForm.drawHitTest(me, pt, z)
    }

    mtd impl paint(painter: *Painter, cxt: FormPaintContext)
    {
        let {bSize, sSize, eSize} = .paintSizes(cxt)
        let outlineSize           = .paintOutlineSize(cxt)

        if .bezier
        {
            // Add an anchor the first time, when transforming from 'linear' to 'bezier'
            if .gizmo.anchors.count == 2
            {
                var v = Math.Vector2{.xb, .yb} - Math.Vector2{.xa, .ya}
                v *= 0.5
                var vn = v.cross(1).normalizedOrZero()
                vn  *= v.length() * 0.25
                .xc = v.x + vn.x
                .yc = v.y + vn.y
                .gizmo.anchors.resize(3)
            }

            if cxt.quickMode
            {
                .xc = .xa
                .yc = Math.abs(.ya - .yb) * 0.75
            }
        }
        elif .gizmo.anchors.count == 3
        {
            .gizmo.anchors.resize(2)
        }

        let z       = cxt.z
        let contour = (.subKind != .PixSel and .outlineColor.a) ? outlineSize : 0
        let pen     = .createPaintPen(.borderColor, bSize, sSize, eSize, contour)
        if .bezier do
            painter.drawBezier(.xa * z, .ya * z, .xb * z, .yb * z, (.xa + .xc) * z, (.ya + .yc) * z, pen)
        else do
            painter.drawLine(.xa * z, .ya * z, .xb * z, .yb * z, pen)
    }

    mtd impl setup(capt: *Capture?)
    {
        .capture = capt
        .gizmo.anchors.resize(3)

        .gizmo.sigChanged = func|form = me|(diff, pt, first) { GizmoPoints.apply(form, diff, pt, first) }
    }
}
