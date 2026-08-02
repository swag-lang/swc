enum FormStepType
{
    #[Properties.Name("1...2...3...")]
    Number
    #[Properties.Name("A...B...C...")]
    LetterUp
    #[Properties.Name("a...b...c...")]
    LetterDown
}

#[Swag.Using(Properties)]
struct FormStep
{
    using
    base:  BaseForm
    kind:  FormShapeKind = Ellipse
    index: u32           = 1
    #[Name("Step")]
    typeIndex = FormStepType.Number

    #[Serialization.NoSerialize]
    {
        ws, hs:     s32  = 48
        gizmo:      GizmoRect
        isDirty:    bool = true
        cachefSize: f32
        cacheTypeIndex   = FormStepType.Number
        pathl:      LinePathList
    }
}

impl IForm for FormStep
{
    mtd impl isSame(ptr: *BaseForm)->bool
    {
        let other = cast(*FormStep) ptr
        return .isSameBase(ptr) and
               .kind == other.kind and
               .typeIndex == other.typeIndex
    }

    mtd impl copy(dst, src: *BaseForm)
    {
        BaseForm.copyBase(dst, src)
        let dstf = cast(*FormStep) dst
        let srcf = cast(*FormStep) src
        dstf.kind      = srcf.kind
        dstf.typeIndex = srcf.typeIndex
        dstf.ws        = srcf.ws
        dstf.hs        = srcf.hs
    }

    mtd impl edit(evt: *MouseEvent, movingStart: Math.Point, localPos: Math.Point, zoom: f32)->bool
    {
        var xa = cast(s32) (movingStart.x / zoom)
        var ya = cast(s32) (movingStart.y / zoom)
        xa -= .ws / 2
        ya -= .hs / 2
        .setBaseForm(xa, ya, .ws, .hs)

        var xbu     = 0
        var ybu     = 0
        let capture = notnull .capture
        capture.snap(&xbu, &ybu, true, true, 0, me)
        xa += xbu
        ya += ybu
        .setBaseForm(xa, ya, .ws, .hs)

        .index                = capture.nextStepIndex
        capture.nextStepIndex += 1
        .isDirty              = true

        return false
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
    }

    mtd impl setBaseForm(newPosX, newPosY, newSizeX, newSizeY: s32)
    {
        .setRectForm(newPosX, newPosY, newSizeX, newSizeY)
    }

    mtd impl moveForm(newPosX, newPosY: s32)
    {
        .x += newPosX
        .y += newPosY
    }

    mtd impl movePoint(pt: u32, newPosX, newPosY: s32) {}

    mtd impl boundRect()->Math.Rectangle
    {
        return .rectFormBound()
    }

    mtd impl mouse(view: *EditView, pos: Math.Point, evt: *MouseEvent)->bool
    {
        return .gizmo.mouse(view, pos, evt)
    }

    mtd impl paintGizmo(painter: *Painter, z: f32, flags: FormFlags)
    {
        if flags.has(.Hot | .Selected)
        {
            .gizmo.rect = .boundRect() * z
            .gizmo.paint(painter, !flags.has(.Selected))
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
        let z     = cxt.z
        var fSize = Math.min(.w, .h) * 0.6
        fSize = Math.max(fSize, 8)
        let backBrush = Brush.createHatch(.CheckBoardLarge, Argb.DarkGray)

        let face = g_App.theme.res.defaultTypeFaceR

        if fSize != .cachefSize or .typeIndex != .cacheTypeIndex do
            .isDirty = true

        if .isDirty
        {
            .isDirty        = false
            .cachefSize     = fSize
            .cacheTypeIndex = .typeIndex
            .pathl.clear()

            var t: String
            let curIndex = cxt.quickMode ? 1 : .index

            switch #complete .typeIndex
            {
            case .Number:
                t = Format.toString("%", curIndex)

            case .LetterUp:

                // Wrap with modulo 26 so indices past 26 cycle back through A..Z
                // instead of spilling past 'Z' into punctuation glyphs.
                t = Format.toString("%", cast(rune) ('A'rune + (curIndex - 1) % 26))

            case .LetterDown:
                t = Format.toString("%", cast(rune) ('a'rune + (curIndex - 1) % 26))
            }

            .pathl = expect face.buildStringOutline(t, cast() fSize)
            .pathl.flatten(painter.quality())
            .pathl.offset(1, JoinStyle.Round, 0.5)
            .pathl.clean()
        }

        var bk = .backColor
        if cxt.quickMode and .alpha != 100 do
            bk.a = .highlightAlpha()

        let pp = .boundRect() * z

        switch #complete .kind
        {
        case .Ellipse:
            let sizeX = pp.width * 0.5
            let sizeY = pp.height * 0.5
            if cxt.quickMode and .alpha != 100 do
                painter.fillEllipse(pp.x + sizeX, pp.y + sizeY, sizeX, sizeY, backBrush)
            painter.fillEllipse(pp.x + sizeX, pp.y + sizeY, sizeX, sizeY, .backColor)

        case .Rectangle:
            if cxt.quickMode and .alpha != 100 do
                painter.fillRect(pp, backBrush)
            painter.fillRect(pp, bk)

        case .RoundRectangle:
            var round = cast(f32) Math.min(.w, .h)
            round /= 3
            if cxt.quickMode and .alpha != 100 do
                painter.fillRoundRect(pp, round, round, backBrush)
            painter.fillRoundRect(pp, round, round, .backColor)
        }

        let wt = (.pathl.maxBounds.x - .pathl.minBounds.x) * z
        let ht = (.pathl.maxBounds.y - .pathl.minBounds.y) * z
        let x0 = pp.horzCenter() - (wt * 0.5)
        let y0 = pp.vertCenter() - (ht * 0.5)

        let tt = painter.transform()
        with painter
        {
            .pushTransform()
            var localTransform = tt
            localTransform.tx = 0
            localTransform.ty = 0
            .setTransform(localTransform)
            .scaleTransform(z, z)
            .translateTransform(tt.tx, tt.ty)
            .translateTransform(x0 - me.pathl.minBounds.x * z, y0 - me.pathl.minBounds.y * z)
            .fillPath(&me.pathl, me.borderColor)
            .popTransform()
        }
    }

    mtd impl setup(capt: *Capture)
    {
        .capture = capt
        .gizmo.setupForForm(me)
    }
}
