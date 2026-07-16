struct QuickStyle
{
    forms: Array'IForm
}

impl QuickStyle
{
    mtd opDrop()
    {
        .clear()
    }

    func isKnownForm(itf: IForm)->bool
    {
        let type = @kindof(itf)
        return type == FormArrow or
               type == FormDraw or
               type == FormImage or
               type == FormLine or
               type == FormPolygon or
               type == FormShape or
               type == FormStep or
               type == FormText or
               type == FormCallout
    }

    func deleteOne(itf: IForm)
    {
        Memory.delete(@dataof(itf), @kindof(itf))
    }

    mtd sanitize()
    {
        var idx = 0'u64
        while idx < .forms.count
        {
            if isKnownForm(.forms[idx])
            {
                idx += 1
                continue
            }

            // Stale serialized interface values can point to an unresolved type.
            .forms.removeAtOrdered(idx)
        }
    }

    mtd remove(itf: IForm)
    {
        deleteOne(itf)
        .forms.remove(itf)
    }

    mtd clear()
    {
        for i in .forms do
            deleteOne(i)
        .forms.clear()
    }
}

// Register a freshly built default form into a quick style set (see the
// defaultQuickStyle* builders below).
func(T) addStyleForm(qs: *QuickStyle, form: *T)
{
    let it = cast(IForm) form
    it.setup(null)
    qs.forms.add(it)
}

struct QuickButton
{
    using iconBtn:     IconButton
    formItf:           IForm
    quickWnd:          *QuickWnd
}

struct QuickStylePaintForm
{
    itf:       IForm
    title:     string
}

func quickStyleReleasePaintForm(paint: *QuickStylePaintForm)
{
    if paint.itf do
        Memory.delete(@dataof(paint.itf), @kindof(paint.itf))
    paint.itf = null
}

func quickStyleNewPaintForm(srcItf: IForm)->QuickStylePaintForm
{
    // Icon painting normalizes geometry/text/points, so work on a disposable copy.
    let paintBase = MainWnd.newFormFromForm(srcItf)
    let paintItf  = @mkinterface(paintBase, @kindof(srcItf), IForm)

    var cxt: FormPaintContext
    cxt.z         = 1
    cxt.quickMode = true

    let sel  = cast(*BaseForm) @dataof(paintItf)
    let s    = cast(s32) BaseForm.adaptSize(sel.borderSize / 2, MinBorderSize, MaxBorderSize, cxt)
    let rect = Math.Rectangle{8 + s, 8 + s, 48 - 2 * s, 48 - 2 * s}

    var result: QuickStylePaintForm
    result.itf = paintItf

    switch paintItf
    {
    case FormPolygon:
        let poly = cast(*FormPolygon) @dataof(paintItf)
        poly.setDefaultShape()
    case FormDraw:
        let poly = cast(*FormDraw) @dataof(paintItf)
        poly.setDefaultShape()
    case FormText:
        let txt = cast(*FormText) @dataof(paintItf)
        txt.text = "A"
    case FormImage:
        let img = cast(*FormImage) @dataof(paintItf)
        switch img.kind
        {
        case Image:
            result.title = "image"
        case Blur:
            result.title = "blur"
        case Pixelate:
            result.title = "pixelate"
        case Zoom:
            result.title = "zoom"
        case Capture:
            result.title = "capture"
        }
    }

    paintItf.setBaseForm(cast() rect.x, cast() rect.y, cast() rect.width, cast() rect.height)

    // The callout tail lives in canvas space and is never carried by a style; give the
    // preview a shortened body and an in-cell downward tail so it renders to scale.
    if @kindof(paintItf) == FormCallout
    {
        let cl = cast(*FormCallout) @dataof(paintItf)
        cl.text = "A"
        // Read as a clean speech bubble: quick mode already normalizes the glyph size to
        // a fixed range, so a small fontSize just lands at the airy end; keep the body
        // nearly full-cell so the letter breathes, and hang a short downward tail nub.
        cl.fontSize = 10
        cl.h        = cast(s32) (cast(f32) cl.h * 0.82)
        cl.tailX    = cl.x + cast(s32) (cast(f32) cl.w * 0.28)
        cl.tailY    = cl.y + cl.h + 8
    }

    return result
}

struct QuickWnd
{
    using scrollWnd:     ScrollWnd

    layout:              *WrapLayoutCtrl
    main:                *MainWnd

    qsArrow:             QuickStyle
    qsShape:             QuickStyle
    qsImage:             QuickStyle
    qsStep:              QuickStyle
    qsLine:              QuickStyle
    qsPolygon:           QuickStyle
    qsText:              QuickStyle
    qsFavorites:         QuickStyle
    qsDraw:              QuickStyle
    qsHighlight:         QuickStyle
    qsPixSel:            QuickStyle
    qsCallout:           QuickStyle

    currentStyle:        *QuickStyle
}

impl IWnd for QuickWnd
{
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind == .MousePressed and evt.button == .Right
        {
            .btnPopup(null, evt.surfacePos)
            evt.accepted = true
            return
        }

        .scrollWnd.IWnd.onMouseEvent(evt)
    }

    mtd impl onSerializeStateEvent(evt: *SerializeStateEvent)
    {
        catch
        {
            with evt.ser
            {
                .serialize("QuickWnd.qsArrow", &me.qsArrow)
                .serialize("QuickWnd.qsShape", &me.qsShape)
                .serialize("QuickWnd.qsImage", &me.qsImage)
                .serialize("QuickWnd.qsStep", &me.qsStep)
                .serialize("QuickWnd.qsLine", &me.qsLine)
                .serialize("QuickWnd.qsPolygon", &me.qsPolygon)
                .serialize("QuickWnd.qsText", &me.qsText)
                .serialize("QuickWnd.qsFavorites", &me.qsFavorites)
                .serialize("QuickWnd.qsDraw", &me.qsDraw)
                .serialize("QuickWnd.qsHighlight", &me.qsHighlight)
                .serialize("QuickWnd.qsPixSel", &me.qsPixSel)
                .serialize("QuickWnd.qsCallout", &me.qsCallout)
            }
        }
    }
}

impl QuickWnd
{
    mtd setDefault()
    {
        .qsArrow.sanitize()
        .qsShape.sanitize()
        .qsImage.sanitize()
        .qsStep.sanitize()
        .qsLine.sanitize()
        .qsPolygon.sanitize()
        .qsText.sanitize()
        .qsFavorites.sanitize()
        .qsDraw.sanitize()
        .qsHighlight.sanitize()
        .qsPixSel.sanitize()
        .qsCallout.sanitize()

        if .qsArrow.forms.isEmpty() do
            .defaultQuickStyleArrow()
        if .qsShape.forms.isEmpty() do
            .defaultQuickStyleShape()
        if .qsImage.forms.isEmpty() do
            .defaultQuickStyleImage()
        if .qsStep.forms.isEmpty() do
            .defaultQuickStyleStep()
        if .qsLine.forms.isEmpty() do
            .defaultQuickStyleLine()
        if .qsPolygon.forms.isEmpty() do
            .defaultQuickStylePolygon()
        if .qsText.forms.isEmpty() do
            .defaultQuickStyleText()
        if .qsDraw.forms.isEmpty() do
            .defaultQuickStyleDraw()
        if .qsHighlight.forms.isEmpty() do
            .defaultQuickStyleHighlight()
        if .qsPixSel.forms.isEmpty() do
            .defaultQuickStylePixSel()
        if .qsCallout.forms.isEmpty() do
            .defaultQuickStyleCallout()

        .updateQuickStyles(forceRebuild: true)

        .main.updateModel(.qsArrow.forms[0])
        .main.updateModel(.qsLine.forms[0])
        .main.updateModel(.qsShape.forms[0])
        .main.updateModel(.qsImage.forms[0])
        .main.updateModel(.qsStep.forms[0])
        .main.updateModel(.qsPolygon.forms[0])
        .main.updateModel(.qsText.forms[0])
        .main.updateModel(.qsDraw.forms[0])
        .main.updateModel(.qsCallout.forms[0])
        .updateSelection()
    }

    mtd btnPopup(btn: #null *Button, pos: Math.Point)
    {
        let menu = MenuCtrl.createPopup(me)
        menu.addItem("Remove Quick Style", "0", disabled: !btn)
        menu.addSeparator()
        menu.addItem(ActionQuickStyle.Reset)
        let res = menu.doModal(pos, autoDestroy: true)
        if res == "0" and btn
        {
            let qbtn = cast(*QuickButton) btn
            .currentStyle.remove(qbtn.formItf)
            qbtn.destroy()
            .updateQuickStyles(forceRebuild: true)
        }
    }

    func create(parent: *Wnd, main: *MainWnd)->*QuickWnd
    {
        with let quick = Wnd.create'QuickWnd(parent, {0, 0, 0, 300})
        {
            .backgroundStyle = .Window
            .scrollWndFlags |= .ForceVertical | .SmallBar | .TransparentBar

            .layout         = WrapLayoutCtrl.create(quick)
            .layout.padding = 6
            .layout.spacing = 6
            .setView(quick.layout)

            .main = main
        }

        return quick
    }

    mtd defaultQuickStyleArrow()
    {
        mtd add(startSize, borderSize, endSize: f32, color: Color, startCap = LineCapStyle.ArrowAnchor, dash = DashStyle.None)
        {
            let form = Memory.new'FormArrow()
            form.startSize  = startSize
            form.borderSize = borderSize
            form.endSize    = endSize
            form.dashStyle  = dash
            if startSize != 0 do
                form.beginCap = startCap
            if endSize != 0 do
                form.endCap = .ArrowAnchor
            form.borderColor = color
            addStyleForm(&.qsArrow, form)
        }

        const BorderSize = 10.0
        const ArrowSize  = 5.0

        .add(0, BorderSize, ArrowSize, ColorRed)
        .add(0, BorderSize, ArrowSize, ColorGreen)
        .add(0, BorderSize, ArrowSize, ColorBlue)
        .add(0, BorderSize, ArrowSize, ColorYellow)

        .add(ArrowSize, BorderSize, ArrowSize, ColorRed)
        .add(ArrowSize, BorderSize, ArrowSize, ColorGreen)
        .add(ArrowSize, BorderSize, ArrowSize, ColorBlue)
        .add(ArrowSize, BorderSize, ArrowSize, ColorYellow)

        .add(ArrowSize * 0.5, BorderSize, ArrowSize, ColorRed, .RoundAnchor, .Dot)
        .add(ArrowSize * 0.5, BorderSize, ArrowSize, ColorGreen, .RoundAnchor, .Dot)
        .add(ArrowSize * 0.5, BorderSize, ArrowSize, ColorBlue, .RoundAnchor, .Dot)
        .add(ArrowSize * 0.5, BorderSize, ArrowSize, ColorYellow, .RoundAnchor, .Dot)
    }

    mtd defaultQuickStyleLine()
    {
        mtd add(borderSize: f32, color: Color)
        {
            let form = Memory.new'FormLine()
            form.borderSize  = borderSize
            form.borderColor = color
            addStyleForm(&.qsLine, form)
        }

        const BorderSize = 10.0

        .add(BorderSize, ColorRed)
        .add(BorderSize, ColorGreen)
        .add(BorderSize, ColorBlue)
        .add(BorderSize, ColorYellow)
        .add(BorderSize, Argb.White)
        .add(BorderSize, Argb.Gray)
        .add(BorderSize, Argb.Black)
    }

    mtd defaultQuickStyleShape()
    {
        mtd add(borderSize: f32, kind: FormShapeKind, color: Color, backColor: Color)
        {
            let form = Memory.new'FormShape()
            form.borderSize  = borderSize
            form.borderColor = color
            form.backColor   = backColor
            form.kind        = kind
            addStyleForm(&.qsShape, form)
        }

        const BorderSize = 10.0

        .add(BorderSize, .RoundRectangle, ColorRed, Argb.Zero)
        .add(BorderSize, .RoundRectangle, ColorGreen, Argb.Zero)
        .add(BorderSize, .RoundRectangle, ColorBlue, Argb.Zero)
        .add(BorderSize, .RoundRectangle, ColorYellow, Argb.Zero)

        .add(BorderSize, .Rectangle, ColorRed, Argb.Zero)
        .add(BorderSize, .Rectangle, ColorGreen, Argb.Zero)
        .add(BorderSize, .Rectangle, ColorBlue, Argb.Zero)
        .add(BorderSize, .Rectangle, ColorYellow, Argb.Zero)

        .add(BorderSize, .Ellipse, ColorRed, Argb.Zero)
        .add(BorderSize, .Ellipse, ColorGreen, Argb.Zero)
        .add(BorderSize, .Ellipse, ColorBlue, Argb.Zero)
        .add(BorderSize, .Ellipse, ColorYellow, Argb.Zero)

        .add(BorderSize, .Rectangle, Argb.White, Argb.Zero)
        .add(BorderSize, .Rectangle, Argb.Black, Argb.Zero)

        .add(0, .Rectangle, Argb.Zero, Argb.White)
        .add(0, .Rectangle, Argb.Zero, Argb.Black)
    }

    mtd defaultQuickStyleImage()
    {
        mtd add(borderSize: f32, kind: FormImageKind, color: Color)
        {
            let form = Memory.new'FormImage()
            form.borderSize  = borderSize
            form.borderColor = color
            form.backColor   = Argb.Gray
            form.kind        = kind
            if borderSize == 0 do
                form.paintShadow = false
            addStyleForm(&.qsImage, form)
        }

        .add(2, .Image, Argb.White)
        .add(2, .Zoom, Argb.White)
        .add(0, .Blur, Argb.Zero)
        .add(0, .Pixelate, Argb.Zero)
        .add(0, .Capture, Argb.Zero)
    }

    mtd defaultQuickStyleStep()
    {
        mtd add(kind: FormShapeKind, color: Color, backColor: Color)
        {
            let form = Memory.new'FormStep()
            form.borderColor = color
            form.backColor   = backColor
            form.kind        = kind
            addStyleForm(&.qsStep, form)
        }

        .add(.Ellipse, Argb.White, ColorRed)
        .add(.Ellipse, Argb.White, ColorGreen)
        .add(.Ellipse, Argb.White, ColorBlue)
        .add(.Ellipse, Argb.White, ColorYellow)

        .add(.RoundRectangle, Argb.White, ColorRed)
        .add(.RoundRectangle, Argb.White, ColorGreen)
        .add(.RoundRectangle, Argb.White, ColorBlue)
        .add(.RoundRectangle, Argb.White, ColorYellow)
    }

    mtd defaultQuickStylePolygon()
    {
        mtd add(borderSize: f32, color: Color, bezier = false)
        {
            let form = Memory.new'FormPolygon()
            form.borderSize  = borderSize
            form.borderColor = color
            form.backColor   = 0
            form.bezier      = bezier
            addStyleForm(&.qsPolygon, form)
        }

        const BorderSize = 5.0

        .add(BorderSize, ColorRed)
        .add(BorderSize, ColorGreen)
        .add(BorderSize, ColorBlue)
        .add(BorderSize, ColorYellow)

        .add(BorderSize, ColorRed, true)
        .add(BorderSize, ColorGreen, true)
        .add(BorderSize, ColorBlue, true)
        .add(BorderSize, ColorYellow, true)

        .add(BorderSize, Argb.White)
        .add(BorderSize, Argb.Black)
    }

    mtd defaultQuickStyleCallout()
    {
        mtd add(bdColor, bkColor, txColor: Color)
        {
            let form = Memory.new'FormCallout()
            form.borderSize  = 4
            form.borderColor = bdColor
            form.backColor   = bkColor
            form.textColor   = txColor
            form.roundSize   = 16
            form.fontSize    = 40
            form.text        = "A"
            addStyleForm(&.qsCallout, form)
        }

        .add(Argb.White, ColorRed, Argb.White)
        .add(Argb.White, ColorGreen, Argb.White)
        .add(Argb.White, ColorBlue, Argb.White)
        .add(Argb.White, ColorYellow, Argb.Black)
        .add(Argb.White, Argb.Black, Argb.White)
        .add(Argb.Black, Argb.White, Argb.Black)
    }

    mtd defaultQuickStyleText()
    {
        mtd add(borderSize, fontSize: f32, bdColor, bkColor: Color)
        {
            let form = Memory.new'FormText()
            form.borderSize  = borderSize
            form.borderColor = bdColor
            form.backColor   = bkColor
            form.fontSize    = fontSize
            form.text        = "A"
            addStyleForm(&.qsText, form)
        }

        .add(4, 24, Argb.White, ColorRed)
        .add(4, 24, Argb.White, ColorGreen)
        .add(4, 48, Argb.White, ColorBlue)
        .add(4, 48, Argb.White, ColorYellow)

        .add(4, 72, Argb.White, ColorRed)
        .add(4, 72, Argb.White, ColorGreen)
        .add(4, 72, Argb.White, ColorBlue)
        .add(4, 72, Argb.White, ColorYellow)

        .add(4, 48, Argb.Zero, Argb.White)
        .add(4, 48, Argb.Zero, Argb.Gray)
        .add(4, 48, Argb.Zero, Argb.Black)

        .add(4, 72, Argb.Zero, Argb.White)
        .add(4, 72, Argb.Zero, Argb.Gray)
        .add(4, 72, Argb.Zero, Argb.Black)
    }

    mtd defaultQuickStyleDraw()
    {
        mtd add(borderSize: f32, color: Color)
        {
            let form = Memory.new'FormDraw()
            form.borderSize  = borderSize
            form.borderColor = color
            addStyleForm(&.qsDraw, form)
        }

        const BorderSize = 10.0

        .add(BorderSize, ColorRed)
        .add(BorderSize, ColorGreen)
        .add(BorderSize, ColorBlue)
        .add(BorderSize, ColorYellow)

        .add(BorderSize, Argb.White)
        .add(BorderSize, Argb.Gray)
        .add(BorderSize, Argb.Black)
    }

    mtd defaultQuickStyleHighlight()
    {
        mtd addDraw(borderSize: f32, color: Color)
        {
            let form = Memory.new'FormDraw()
            form.borderSize  = borderSize
            form.borderColor = color
            form.alpha       = 30
            form.subKind     = .Highlight
            addStyleForm(&.qsHighlight, form)
        }

        mtd addShape(kind: FormShapeKind, backColor: Color)
        {
            let form = Memory.new'FormShape()
            form.borderSize  = 0
            form.borderColor = Argb.Zero
            form.backColor   = backColor
            form.alpha       = 30
            form.kind        = kind
            form.subKind     = .Highlight
            addStyleForm(&.qsHighlight, form)
        }

        mtd addPoly(backColor: Color)
        {
            let form = Memory.new'FormPolygon()
            form.borderSize  = 0
            form.borderColor = Argb.Zero
            form.backColor   = backColor
            form.alpha       = 30
            form.subKind     = .Highlight
            addStyleForm(&.qsHighlight, form)
        }

        const BorderSize = 20.0

        .addShape(.Rectangle, ColorRed)
        .addShape(.Rectangle, ColorGreen)
        .addShape(.Rectangle, ColorBlue)
        .addShape(.Rectangle, ColorYellow)

        .addDraw(BorderSize, ColorRed)
        .addDraw(BorderSize, ColorGreen)
        .addDraw(BorderSize, ColorBlue)
        .addDraw(BorderSize, ColorYellow)

        .addPoly(ColorRed)
        .addPoly(ColorGreen)
        .addPoly(ColorBlue)
        .addPoly(ColorYellow)
    }

    mtd defaultQuickStylePixSel()
    {
        mtd addDraw()
        {
            let form = Memory.new'FormDraw()
            form.subKind     = .PixSel
            form.paintShadow = false
            addStyleForm(&.qsPixSel, form)
        }

        mtd addShape(kind: FormShapeKind)
        {
            let form = Memory.new'FormShape()
            form.kind        = kind
            form.subKind     = .PixSel
            form.paintShadow = false
            addStyleForm(&.qsPixSel, form)
        }

        mtd addPoly()
        {
            let form = Memory.new'FormPolygon()
            form.subKind     = .PixSel
            form.paintShadow = false
            addStyleForm(&.qsPixSel, form)
        }

        with me
        {
            .addShape(.Rectangle)
            .addShape(.Ellipse)
            .addPoly()
            .addDraw()
        }
    }

    mtd updateSelection()
    {
        if !.currentStyle do
            return
        var done = false
        let mode = .main.getEditMode()

        // Form buttons are always the leading children (only the trailing model
        // button is ever hidden), so form 'i' maps directly to child 'i'.
        for it, i in .currentStyle.forms
        {
            let btn = cast(*IconButton) .layout.childs[i]
            let mdl = .main.modelFor(@kindof(it))
            btn.isChecked = mode == MainWnd.formToEditMode(it) and it.isSame(cast(*BaseForm) @dataof(mdl))

            if btn.isChecked do
                done = true
        }

        // The model button is optional (canAddModel), so the child list can be
        // empty; guard back() against an out-of-bounds read.
        if .layout.childs.count
        {
            let curMdl = cast(*IconButton) .layout.childs.back()
            if curMdl.userData
            {
                curMdl.show(!done)
                if !done do
                    curMdl.isChecked = true
                .layout.computeLayout()
                .setScrollSize(0, .layout.resultHeight)
            }
        }

        .invalidate()
    }

    mtd resetQuickStyles()
    {
        if !.currentStyle do
            return

        let res = MessageDlg.confirm(.surface, "This will reset the styles to the default values.")
        if res != MessageDlg.BtnYes do
            return

        .currentStyle.clear()

        // The style set was recreated in place: the existing buttons hold pointers to
        // the freed forms, so a full rebuild is mandatory (see updateQuickStyles).
        #[Swag.Complete]
        switch .main.editMode
        {
        case Arrow:
            .defaultQuickStyleArrow()
        case Shape:
            .defaultQuickStyleShape()
        case Image:
            .defaultQuickStyleImage()
        case Step:
            .defaultQuickStyleStep()
        case Line:
            .defaultQuickStyleLine()
        case Polygon:
            .defaultQuickStylePolygon()
        case Text:
            .defaultQuickStyleText()
        case Draw:
            .defaultQuickStyleDraw()
        case Highlight:
            .defaultQuickStyleHighlight()
        case PixSel:
            .defaultQuickStylePixSel()
        case Callout:
            .defaultQuickStyleCallout()
        case Favorites:
            break
        case Selection:
            break
        }

        .updateQuickStyles(forceRebuild: true)
    }

    mtd updateQuickStyles(forceRebuild = false)
    {
        func paintForm(painter: *Painter, btnp: *QuickButton)
        {
            painter.setParams(.Antialiased)
            var paintForm = quickStyleNewPaintForm(btnp.formItf)
            defer quickStyleReleasePaintForm(&paintForm)

            Capture.paintForm(painter, {}, {0, 0, 64, 64}, paintForm.itf, zoom: 1, quickMode: true)

            if @countof(paintForm.title)
            {
                let textColor = g_App.theme.colors.btnIcon_Text
                let rect = paintForm.itf.boundRect()
                painter.drawStringCenter(rect.horzCenter(), rect.bottom(), paintForm.title, btnp.getFont().regular, textColor)
            }
        }

        let edMode = .main.editMode == .Selection ? .main.getEditMode() : .main.editMode
        let prevStyle = .currentStyle
        #[Swag.Complete]
        switch edMode
        {
        case Arrow:
            .currentStyle = &.qsArrow
        case Shape:
            .currentStyle = &.qsShape
        case Image:
            .currentStyle = &.qsImage
        case Step:
            .currentStyle = &.qsStep
        case Line:
            .currentStyle = &.qsLine
        case Polygon:
            .currentStyle = &.qsPolygon
        case Text:
            .currentStyle = &.qsText
        case Favorites:
            .currentStyle = &.qsFavorites
        case Draw:
            .currentStyle = &.qsDraw
        case Highlight:
            .currentStyle = &.qsHighlight
        case PixSel:
            .currentStyle = &.qsPixSel
        case Callout:
            .currentStyle = &.qsCallout
        case Selection:
            return
        }

        if !.currentStyle do
            return

        let formItf     = .main.editModeToModel(.main.getEditMode())
        let baseForm    = cast(*BaseForm) @dataof(formItf)
        var canAddModel = false
        if baseForm
        {
            canAddModel = true
            if .main.editMode == .Highlight
            {
                if baseForm.subKind != .Highlight do
                    canAddModel = false
            }
            elif .main.editMode == .PixSel
            {
                canAddModel = false
            }
            elif baseForm.subKind == .Highlight or baseForm.subKind == .PixSel
            {
                canAddModel = false
            }
        }

        // Light path: same style target and same button population. Destroying and
        // recreating every button is only needed when the style set itself changed;
        // check states and the model button repaint from live data.
        let wantBtns = .currentStyle.forms.count + (canAddModel ? 1 : 0)
        if !forceRebuild and .currentStyle == prevStyle and .layout.childs.count == wantBtns
        {
            .updateSelection()
            return
        }

        for c in .layout.childs do
            c.destroy()

        for it in .currentStyle.forms
        {
            let btn = Wnd.create'QuickButton(.layout, null, {0, 0, 64, 64})
            btn.iconBtnFlags.add(.Checkable)
            btn.setForm(.RoundSquare)
            btn.formItf = it
            btn.quickWnd = me

            btn.sigPaintIcon = func(btn, bc, pos, flags)
            {
                paintForm(bc.painter, cast(*QuickButton) btn)
            }

            btn.sigRightPressed += func(btn)
            {
                var rect = btn.getSurfaceRect()
                let quickBtn = cast(*QuickButton) btn
                quickBtn.quickWnd.btnPopup(btn, rect.center())
            }

            btn.sigCheckChanged += func(btn)
            {
                let quickBtn = cast(*QuickButton) btn
                let quick    = quickBtn.quickWnd
                let it       = quickBtn.formItf
                if !btn.isChecked do
                    return
                quick.main.updateModel(it)

                var capture = assume quick.main.getCapture()
                if capture.selection.count
                {
                    let mdlValue = MainWnd.newFormFromForm(it)
                    let undo     = capture.newUndo(.SetFormFromModel)
                    undo.mdlType  = @kindof(it)
                    undo.mdlValue = mdlValue
                    capture.pushUndo(undo)
                }
                else
                {
                    capture.selection.clear()
                }

                quick.updateSelection()
                quick.main.updateState()
            }
        }

        if canAddModel
        {
            let btn = Wnd.create'QuickButton(.layout, null, {0, 0, 64, 64})
            btn.userData = cast(*void) 1'u64 // This is the model button
            btn.formItf  = formItf
            btn.setForm(.RoundSquare)
            btn.style.addStyleSheetColors("btnIcon_Bk          0x0")
            btn.style.addStyleSheetColors("btnIcon_HotBk       0x0")
            btn.style.addStyleSheetColors("btnIcon_PressedBk   0x0")
            .layout.sendResizeEvent()

            btn.sigPaintIcon = func(btn, bc, pos, flags)
            {
                paintForm(bc.painter, cast(*QuickButton) btn)
                var rect = btn.getClientRect()
                rect.inflate(-2, -2)
                bc.painter.setParams(.Antialiased)
                bc.painter.drawRoundRect(rect, 5, 5, Pen.createDash(.Dash, Argb.White, 2))
            }

            // Button to add a new style
            let ico  = .getTheme().getIcon24(.Plus)
            let btn1 = IconButton.create(btn, ico, {64 - 26, 2, 24, 24})
            btn1.style.addStyleSheetColors("btnIcon_Bk          $hilight")
            btn1.style.addStyleSheetColors("btnIcon_HotBk       $hilightLight")
            btn1.style.addStyleSheetColors("btnIcon_PressedBk   $hilightDark")
            btn1.style.addStyleSheetColors("btnIcon_Icon        $hilightLightContrast")
            btn1.setForm(.Round)

            .layout.sendResizeEvent()
            .setScrollSize(0, .layout.resultHeight)

            btn1.sigPressed += func|quickWnd = me|(btn)
            {
                let main = quickWnd.main
                let mdl = main.newFormFromModel(main.getEditMode())
                if mdl
                {
                    quickWnd.currentStyle.forms.add(mdl)
                    quickWnd.updateQuickStyles()
                }
            }
        }

        .updateSelection()
        .layout.computeLayout()
    }
}
