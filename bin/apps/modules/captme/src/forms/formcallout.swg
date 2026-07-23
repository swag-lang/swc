// A speech-bubble annotation: a rounded-rectangle body holding centered text, with
// a triangular tail whose tip is a freely movable point. The body reuses the shared
// rect gizmo (resize/move) while the tail tip is a single-anchor point gizmo. Text is
// rendered by reusing FormText so glyph layout/outline/caching is not duplicated here.
// Field order below is the display order of the generated properties panel;
// serialization matches fields by name, so it is free to follow the UI.
#[Swag.Using(Properties)]
struct FormCallout
{
    using base:      BaseForm
    #[Name("Font"), FontName]
    fontName: String
    #[Name("Text"), MultiLine]
    text: String
    #[Name("Font Style")]
    fontStyle        = FontFamilyStyle.Regular
    #[Name("Align")]
    alignHorz        = FormTextAlign.Center
    #[Name("Vertical Align")]
    alignVert        = FormTextAlign.Center
    #[Name("Size"), SliderMinMax(MinFontSize, MaxFontSize)]
    fontSize: f32 = 40
    #[Name("Round"), SliderMinMax(MinRoundSize, MaxRoundSize)]
    roundSize:    f32 = 16
    tailX, tailY: f32
    boldSize:     f32 = 0
    lineSpacing      = 14.0
    textColor: Color = Argb.White

    #[Serialization.NoSerialize]
    {
        gizmoRect: GizmoRect
        gizmoTail: GizmoPoints
        render:    FormText
        tailPath:  LinePath
    }
}

impl FormCallout
{
    // Half-base width and centre of the tail along one body edge. `tailLen` is the
    // tip's perpendicular distance to that edge; `cr` is the corner-arc radius. The base
    // is: no wider than the tail is long (keeps short tails pointed, not squat), fits
    // inside the straight span between the two rounded corners, and centred under the
    // tip but pulled onto that straight span — so it never attaches past a corner arc,
    // which is what left a gap/overshoot when the tip pointed toward a corner.
    func tailSpan(tipCoord, tailLen, edgeLo, edgeHi, minWH, cr: f32)->{ hb: f32, c: f32 }
    {
        var res: retval

        var hb = Math.max(Math.min(18.0, minWH * 0.3), 2'f32)
        hb = Math.max(Math.min(hb, tailLen * 0.6), 2'f32)

        let sLo = edgeLo + cr
        let sHi = edgeHi - cr
        hb = Math.max(Math.min(hb, (sHi - sLo) * 0.5), 2'f32)

        let lo = sLo + hb
        let hi = sHi - hb
        res.hb = hb
        res.c  = lo > hi ? (edgeLo + edgeHi) * 0.5 : Math.clamp(tipCoord, lo, hi)
        return res
    }

    // Base of the tail on the body edge nearest the tip, returned in form space.
    // `inN` is the inward unit normal of that edge, used to sink the tail's base into
    // the body so its fill hides the body border that runs under it. `cornerR` is the
    // rounded-corner radius (form space) so the base stays off the corner arcs.
    mtd tailBase(tip: Math.Vector2, cornerR: f32)->{ p0: Math.Vector2, p1: Math.Vector2, inN: Math.Vector2 }
    {
        var result: retval
        let b  = .rectFormBound()
        let cx = b.horzCenter()
        let cy = b.vertCenter()
        let dx = tip.x - cx
        let dy = tip.y - cy

        let cr    = Math.min(cornerR, Math.min(b.width, b.height) * 0.5)
        let minWH = Math.min(b.width, b.height)

        // Aspect-normalized compare picks a vertical vs horizontal edge.
        if Math.abs(dx) * b.height > Math.abs(dy) * b.width
        {
            let ex = dx > 0 ? b.right() : b.x
            let s  = tailSpan(tip.y, Math.abs(tip.x - ex), b.y, b.bottom(), minWH, cr)
            result.p0  = {ex, s.c - s.hb}
            result.p1  = {ex, s.c + s.hb}
            result.inN = {dx > 0 ? -1'f32 : 1'f32, 0}
        }
        else
        {
            let ey = dy > 0 ? b.bottom() : b.y
            let s  = tailSpan(tip.x, Math.abs(tip.y - ey), b.x, b.right(), minWH, cr)
            result.p0  = {s.c - s.hb, ey}
            result.p1  = {s.c + s.hb, ey}
            result.inN = {0, dy > 0 ? -1'f32 : 1'f32}
        }

        return result
    }

    // Sample a corner arc (a0Deg..a1Deg, screen convention: +x right, +y down) into an
    // already-started path.
    func addArc(path: *LinePath, cx, cy, r, a0Deg, a1Deg: f32)
    {
        const Seg = 8
        for k in Seg + 1
        {
            let ang = Math.toRadians(a0Deg + (a1Deg - a0Deg) * (cast(f32) k / Seg))
            path.lineTo(cx + r * Math.cos(ang), cy + r * Math.sin(ang))
        }
    }

    // Build the whole callout outline — rounded body with the tail spliced into edge
    // `edge` (0=bottom, 1=top, 2=right, 3=left) — as ONE closed path. Rendering body and
    // tail from a single fill + single stroke makes the tail fuse seamlessly with the
    // body: no overlapping fills/strokes to misalign at the corner where they meet.
    func buildOutline(path: *LinePath, b: Math.Rectangle, r: f32, p0, p1, tip: Math.Vector2, edge: s32)
    {
        // Top edge, left → right.
        path.start(b.x + r, b.y)
        if edge == 1
        {
            path.lineTo(p0.x, p0.y)
            path.lineTo(tip.x, tip.y)
            path.lineTo(p1.x, p1.y)
        }

        path.lineTo(b.right() - r, b.y)
        addArc(path, b.right() - r, b.y + r, r, 270, 360)

        // Right edge, top → bottom.
        if edge == 2
        {
            path.lineTo(p0.x, p0.y)
            path.lineTo(tip.x, tip.y)
            path.lineTo(p1.x, p1.y)
        }

        path.lineTo(b.right(), b.bottom() - r)
        addArc(path, b.right() - r, b.bottom() - r, r, 0, 90)

        // Bottom edge, right → left (p1 is the right base point, so it comes first).
        if edge == 0
        {
            path.lineTo(p1.x, p1.y)
            path.lineTo(tip.x, tip.y)
            path.lineTo(p0.x, p0.y)
        }

        path.lineTo(b.x + r, b.bottom())
        addArc(path, b.x + r, b.bottom() - r, r, 90, 180)

        // Left edge, bottom → top (p1 is the lower base point, so it comes first).
        if edge == 3
        {
            path.lineTo(p1.x, p1.y)
            path.lineTo(tip.x, tip.y)
            path.lineTo(p0.x, p0.y)
        }

        path.lineTo(b.x, b.y + r)
        addArc(path, b.x + r, b.y + r, r, 180, 270)

        path.close()
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
        .x     = cast(s32) (.x * scale)
        .y     = cast(s32) (.y * scale)
        .w     = cast(s32) (.w * scale)
        .h     = cast(s32) (.h * scale)
        .tailX *= scale
        .tailY *= scale
    }

    mtd impl setBaseForm(newPosX, newPosY, newSizeX, newSizeY: s32)
    {
        .setRectForm(newPosX, newPosY, newSizeX, newSizeY)
    }

    mtd impl moveForm(newPosX, newPosY: s32)
    {
        .x     += newPosX
        .y     += newPosY
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

    mtd impl paint(painter: *Painter, cxt: FormPaintContext)
    {
        let z     = cxt.z
        var bSize = cxt.hitTest ? Math.max(.borderSize, 5) : .borderSize

        // Quick-mode preview maps the border into a thin range (like FormText's, 2..4)
        // rather than the heavy shape range (4..8): at icon scale a fat outline is the
        // main thing that reads as clumsy. Full-scale rendering is unaffected (adaptSize
        // returns size*z there and ignores this range).
        bSize = BaseForm.adaptSize(bSize, MinBorderSize, MaxBorderSize, cxt, 2, 4)
        let rSize = BaseForm.adaptSize(.roundSize, MinRoundSize, MaxRoundSize, cxt)
        let bk    = .backColor
        let body  = .rectFormBound() * z

        let tipF     = Math.Vector2{.tailX, .tailY}
        let bodyForm = .rectFormBound()

        // An unplaced form keeps a (0,0) tip; skip the tail rather than aim it at the origin.
        let drawTail = !(Math.isZeroEpsilon(.tailX) and Math.isZeroEpsilon(.tailY)) and
                       !bodyForm.contains(tipF.x, tipF.y)

        // Body + tail as ONE closed outline, so the tail fuses seamlessly with the
        // rounded body: a single fill and a single stroke leave no overlapping edges to
        // misalign at the junction (which is what glitched when the tail met a corner).
        let r = Math.min(rSize, Math.min(body.width, body.height) * 0.5)
        if drawTail
        {
            let base = .tailBase(tipF, rSize / z)
            let p0   = Math.Vector2{base.p0.x * z, base.p0.y * z}
            let p1   = Math.Vector2{base.p1.x * z, base.p1.y * z}
            let tip  = Math.Vector2{tipF.x * z, tipF.y * z}
            let edge = base.inN.y < 0 ? 0 : (base.inN.y > 0 ? 1 : (base.inN.x < 0 ? 2 : 3))
            FormCallout.buildOutline(&.tailPath, body, r, p0, p1, tip, edge)
        }
        else
        {
            .tailPath.setRoundRect(body.x, body.y, body.width, body.height, r, r)
        }

        if bk.a do
            painter.fillPath(&.tailPath, bk)

        if .borderColor.a and bSize > 0
        {
            var pen = Pen.createDash(.dashStyle, .borderColor, bSize)
            pen.joinStyle = .Round
            pen.borderPos = .Inside
            painter.drawPath(&.tailPath, pen)
        }

        // Text (skip during hit-testing: the body triangles already cover the area).
        if !cxt.hitTest
        {
            var inner = .rectFormBound()

            // Text padding is a form-space inset. The raw round/border values are sized
            // for full-scale bubbles; at preview scale they would swallow the whole tiny
            // body and leave a degenerate (near-zero-height) text box, throwing the glyph
            // off-centre. In quick mode derive the pad from the already-mapped sizes so
            // the "A" keeps an airy, correctly centred box.
            var pad = Math.max(.roundSize * 0.5, 6'f32) + .borderSize
            if cxt.quickMode do
                pad = Math.max(rSize * 0.5, 2'f32) + bSize
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
        .gizmoTail.sigChanged = func|form = me|(diff, pt, first) { GizmoPoints.apply(form, diff, pt, first) }
    }
}
