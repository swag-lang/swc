// A speech-bubble annotation: a rounded-rectangle body holding centered text, with
// a triangular tail whose tip is a freely movable point. The body reuses the shared
// rect gizmo (resize/move) while the tail tip is a single-anchor point gizmo. Text is
// rendered by reusing FormText so glyph layout/outline/caching is not duplicated here.
struct FormCallout
{
    using base:      BaseForm
    roundSize:       f32 = 16
    tailX, tailY:    f32
    fontSize:        f32 = 40
    boldSize:        f32 = 0
    lineSpacing      = 14.0
    fontStyle        = FontFamilyStyle.Regular
    fontName:        String
    textColor:       Color = Argb.White
    text:            String
    alignHorz        = FormTextAlign.Center
    alignVert        = FormTextAlign.Center

    #[Serialization.NoSerialize]
    {
        gizmoRect:   GizmoRect
        gizmoTail:   GizmoPoints
        render:      FormText
        tailPath:    LinePath
    }
}

impl IForm for FormCallout
{
    mtd impl canRotate()->bool
    {
        // The tail tip lives in canvas space; rotating the body would desync it.
        return false
    }

    mtd impl isSame(ptr: *BaseForm)->bool
    {
        let other = cast(*FormCallout) ptr
        return .isSameBase(ptr) and
               .roundSize == other.roundSize and
               .fontSize == other.fontSize and
               .boldSize == other.boldSize and
               .fontStyle == other.fontStyle and
               .fontName == other.fontName and
               .textColor == other.textColor and
               .alignHorz == other.alignHorz and
               .alignVert == other.alignVert
    }

    mtd impl copy(dst, src: *BaseForm)
    {
        BaseForm.copyBase(dst, src)
        let d = cast(*FormCallout) dst
        let s = cast(*FormCallout) src
        d.roundSize = s.roundSize
        d.fontSize  = s.fontSize
        d.boldSize  = s.boldSize
        d.fontStyle = s.fontStyle
        d.fontName  = s.fontName
        d.textColor = s.textColor
        d.alignHorz = s.alignHorz
        d.alignVert = s.alignVert
        d.scale     = s.scale
    }

    mtd impl edit(evt: *MouseEvent, movingStart: Math.Point, localPos: Math.Point, zoom: f32)->bool
    {
        let xa = cast(s32) (movingStart.x / zoom)
        let ya = cast(s32) (movingStart.y / zoom)
        let xb = cast(s32) (localPos.x / zoom)
        let yb = cast(s32) (localPos.y / zoom)
        .setRectForm(xa, ya, xb - xa, yb - ya)

        // Until the user drags the tip, default the tail below the bubble, offset
        // left of center so it reads as a classic speech bubble.
        .tailX = cast(f32) .x + cast(f32) .w * 0.3
        .tailY = cast(f32) (.y + .h) + Math.max(cast(f32) .h * 0.6, 36)

        if evt.kind == .MouseReleased and evt.button == .Left do
            return false
        return true
    }

    mtd impl moveBaseForm(newPosX, newPosY, newSizeX, newSizeY: s32)
    {
        .moveRectForm(newPosX, newPosY, newSizeX, newSizeY)
    }

    mtd impl scaleBaseForm(scale: f32)
    {
        .x = cast(s32) (.x * scale)
        .y = cast(s32) (.y * scale)
        .w = cast(s32) (.w * scale)
        .h = cast(s32) (.h * scale)
        .tailX *= scale
        .tailY *= scale
    }

    mtd impl setBaseForm(newPosX, newPosY, newSizeX, newSizeY: s32)
    {
        .setRectForm(newPosX, newPosY, newSizeX, newSizeY)
    }

    mtd impl moveForm(newPosX, newPosY: s32)
    {
        .x += newPosX
        .y += newPosY
        .tailX += cast(f32) newPosX
        .tailY += cast(f32) newPosY
    }

    mtd impl movePoint(pt: u32, newPosX, newPosY: s32)
    {
        if pt == 0
        {
            .tailX += cast(f32) newPosX
            .tailY += cast(f32) newPosY
        }
    }

    mtd impl boundRect()->Math.Rectangle
    {
        let b    = .rectFormBound()
        let minx = Math.min(b.x, .tailX)
        let miny = Math.min(b.y, .tailY)
        let maxx = Math.max(b.right(), .tailX)
        let maxy = Math.max(b.bottom(), .tailY)
        return Math.Rectangle{minx, miny, maxx - minx, maxy - miny}
    }

    mtd impl mouse(view: *EditView, pos: Math.Point, evt: *MouseEvent)->bool
    {
        // The tail tip takes precedence; it only reports handled when hot/moving.
        if .gizmoTail.mouse(view, pos, evt) do
            return true
        return .gizmoRect.mouse(view, pos, evt)
    }

    mtd impl paintGizmo(painter: *Painter, z: f32, flags: FormFlags)
    {
        if flags.has(.Hot | .Selected)
        {
            .gizmoRect.rect          = .rectFormBound() * z
            .gizmoRect.rotateEnabled = false
            .gizmoRect.paint(painter, !flags.has(.Selected))

            .gizmoTail.anchors[0] = {.tailX * z, .tailY * z}
            .gizmoTail.paint(null, painter, !flags.has(.Selected))
        }
    }

    mtd impl isInside(pt: Math.Point)->bool
    {
        return .rectFormBound().contains(pt.x, pt.y)
    }

    mtd impl hitTest(pt: Math.Point, z: f32)->bool
    {
        return BaseForm.drawHitTest(me, pt, z)
    }

    // Base of the tail on the body edge nearest the tip, returned in form space.
    // `inN` is the inward unit normal of that edge, used to sink the tail's base into
    // the body so its fill hides the body border that runs under it.
    mtd tailBase(tip: Math.Vector2)->{ p0: Math.Vector2, p1: Math.Vector2, inN: Math.Vector2 }
    {
        var result: retval
        let b  = .rectFormBound()
        let cx = b.horzCenter()
        let cy = b.vertCenter()
        let dx = tip.x - cx
        let dy = tip.y - cy
        let hb = Math.max(Math.min(18.0, Math.min(b.width, b.height) * 0.3), 2'f32)

        // Aspect-normalized compare picks a vertical vs horizontal edge.
        if Math.abs(dx) * b.height > Math.abs(dy) * b.width
        {
            let ex = dx > 0 ? b.right() : b.x
            let by = Math.clamp(tip.y, b.y + hb, b.bottom() - hb)
            result.p0  = {ex, by - hb}
            result.p1  = {ex, by + hb}
            result.inN = {dx > 0 ? -1'f32 : 1'f32, 0}
        }
        else
        {
            let ey = dy > 0 ? b.bottom() : b.y
            let bx = Math.clamp(tip.x, b.x + hb, b.right() - hb)
            result.p0  = {bx - hb, ey}
            result.p1  = {bx + hb, ey}
            result.inN = {0, dy > 0 ? -1'f32 : 1'f32}
        }

        return result
    }

    mtd impl paint(painter: *Painter, cxt: FormPaintContext)
    {
        let z     = cxt.z
        var bSize = cxt.hitTest ? Math.max(.borderSize, 5) : .borderSize
        // Thinner mapped border in quick-style previews: the body is shrunk to make room
        // for the tail, so the default 4..8px range reads as too heavy at that scale.
        bSize     = BaseForm.adaptSize(bSize, MinBorderSize, MaxBorderSize, cxt, 2, 4)
        let rSize = BaseForm.adaptSize(.roundSize, MinRoundSize, MaxRoundSize, cxt)
        let bk    = .backColor
        let body  = .rectFormBound() * z

        let tipF     = Math.Vector2{.tailX, .tailY}
        let bodyForm = .rectFormBound()
        // An unplaced form keeps a (0,0) tip; skip the tail rather than aim it at the origin.
        let drawTail = !(Math.isZeroEpsilon(.tailX) and Math.isZeroEpsilon(.tailY)) and
                       !bodyForm.contains(tipF.x, tipF.y)

        // Body
        var pp = body
        pp.inflate(-bSize * 0.5)
        painter.fillRoundRect(pp, rSize, rSize, bk)

        var pen = Pen.createDash(.dashStyle, .borderColor, bSize)
        pen.borderPos = .Inside
        painter.drawRoundRect(body, rSize, rSize, pen)

        // Tail: filled AFTER the body border, with its base sunk into the body so the
        // fill erases the border segment under it; only the two slanted edges are then
        // stroked, so the body outline flows continuously out to the tip and back.
        if drawTail
        {
            let base  = .tailBase(tipF)
            let p0    = Math.Vector2{base.p0.x * z, base.p0.y * z}
            let p1    = Math.Vector2{base.p1.x * z, base.p1.y * z}
            let tip   = Math.Vector2{tipF.x * z, tipF.y * z}
            let inset = bSize + 2
            let f0    = Math.Vector2{p0.x + base.inN.x * inset, p0.y + base.inN.y * inset}
            let f1    = Math.Vector2{p1.x + base.inN.x * inset, p1.y + base.inN.y * inset}

            .tailPath.start(f0.x, f0.y)
            .tailPath.lineTo(tip.x, tip.y)
            .tailPath.lineTo(f1.x, f1.y)
            .tailPath.close()
            painter.fillPolygon(&.tailPath, bk)

            if .borderColor.a and bSize > 0
            {
                painter.drawLine(p0.x, p0.y, tip.x, tip.y, .borderColor, bSize)
                painter.drawLine(p1.x, p1.y, tip.x, tip.y, .borderColor, bSize)
            }
        }

        // Text (skip during hit-testing: the body triangles already cover the area).
        if !cxt.hitTest
        {
            var inner = .rectFormBound()
            let pad   = Math.max(.roundSize * 0.5, 6'f32) + .borderSize
            inner.inflate(-pad, -pad)
            inner.width  = Math.max(inner.width, 1)
            inner.height = Math.max(inner.height, 1)

            if .render.text != .text
            {
                .render.text    = .text
                .render.isDirty = true
            }

            // FormText only rebuilds its glyph face when told the font changed.
            if .render.fontName != .fontName or .render.fontStyle != .fontStyle
            {
                .render.fontName    = .fontName
                .render.fontStyle   = .fontStyle
                .render.isDirtyFont = true
            }

            .render.x           = cast(s32) inner.x
            .render.y           = cast(s32) inner.y
            .render.w           = cast(s32) inner.width
            .render.h           = cast(s32) inner.height
            .render.backColor   = .textColor
            .render.borderColor = Color.fromArgb(0, Argb.Black)
            .render.borderSize  = 0
            .render.fontSize    = .fontSize
            .render.boldSize    = .boldSize
            .render.lineSpacing = .lineSpacing
            .render.alignHorz   = .alignHorz
            .render.alignVert   = .alignVert
            .render.alpha       = 100
            .render.scale       = 0
            .render.capture     = .capture
            .render.IForm.paint(painter, cxt)
        }
    }

    mtd impl setup(capt: #null *Capture)
    {
        .capture = capt
        .gizmoRect.setupForForm(cast(IForm) me)
        .gizmoTail.anchors.resize(1)
        .gizmoTail.sigChanged = func|form = me|(diff, pt, first)
        {
            GizmoPoints.apply(form, diff, pt, first)
        }
    }
}
