#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// QuickStyle icon previews must never mutate the live model shown by the Properties pane.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let textItf = f.main.editModeToModel(.Text)
    textItf.setBaseForm(111, 112, 113, 114)
    f.main.mdlFormText.text = "Keep me"
    let textRectBefore = textItf.boundRect()

    var textPaint = quickStyleNewPaintForm(textItf)
    @assert(@dataof(textPaint.itf) != @dataof(textItf))
    @assert(f.main.mdlFormText.text == "Keep me")
    @assert(textItf.boundRect() == textRectBefore)
    @assert((cast(*FormText) @dataof(textPaint.itf!)).text == "A")
    quickStyleReleasePaintForm(&textPaint)

    f.main.mdlFormPolygon.points.add({10, 10})
    f.main.mdlFormPolygon.points.add({40, 20})
    f.main.mdlFormPolygon.points.add({20, 50})
    let polyItf     = f.main.editModeToModel(.Polygon)
    let pointBefore = f.main.mdlFormPolygon.points[0]

    var polyPaint = quickStyleNewPaintForm(polyItf)
    @assert(@dataof(polyPaint.itf) != @dataof(polyItf))
    @assert(f.main.mdlFormPolygon.points.count == 3)
    @assert(f.main.mdlFormPolygon.points[0] == pointBefore)
    @assert((cast(*FormPolygon) @dataof(polyPaint.itf!)).points.count == 6)
    quickStyleReleasePaintForm(&polyPaint)
}

// A preset sample is centered in its cell whether or not the style carries an outline.
//
// A line of text is placed by the outline it actually paints, and a form with no outline has an
// empty border path. Measured on that path alone it answered a zero extent, so the glyph started
// at the middle of the cell instead of being centered in it, and the plain text presets showed an
// 'A' hanging out of the bottom right corner of their cell.
#test
{
    func newTextStyle(border: Color)->IForm
    {
        let form = Memory.new'FormText()
        form.borderSize  = 4
        form.fontSize    = 48
        form.borderColor = border
        form.backColor   = Argb.White
        form.text        = "A"
        let itf: IForm = form
        itf.setup(null)
        return itf
    }

    // Bounding box of everything the cell painted, read back from the rendered pixels: the
    // sample is drawn by the form itself, so nothing but the picture can say where it landed.
    func inkBounds(image: *Image)->Math.Rectangle
    {
        var x0, y0 = Swag.S32.Max
        var x1, y1 = Swag.S32.Min
        for y in image.height
        {
            for x in image.width
            {
                let color = image.pixelColor(cast() x, cast() y)
                if color.r < 128 or color.g < 128 or color.b < 128 do
                    continue
                x0 = Math.min(x0, cast(s32) x)
                y0 = Math.min(y0, cast(s32) y)
                x1 = Math.max(x1, cast(s32) x)
                y1 = Math.max(y1, cast(s32) y)
            }
        }

        return {cast() x0, cast() y0, cast(f32) (x1 - x0), cast(f32) (y1 - y0)}
    }

    var f: HeadlessFixture
    f.setup(QuickCellSize, QuickCellSize)
    defer f.shutdown()

    for border in [Argb.White, Argb.Zero]
    {
        let itf = newTextStyle(border)
        defer testDeleteForm(itf)

        let btn = IconButton.create(&f.gui.root, {}, {0, 0, QuickCellSize, QuickCellSize})
        defer btn.destroy()
        btn.iconPainter = func|itf|(btn, bc, pos, flags)
        {
            var paint = quickStyleNewPaintForm(itf)
            defer quickStyleReleasePaintForm(&paint)
            Capture.paintForm(bc.painter, {}, {0, 0, QuickCellSize, QuickCellSize}, paint.itf!, zoom: 1, quickMode: true)
        }

        var image = f.gui.render(btn)
        let ink   = inkBounds(&image)
        @assert(ink.width > 4 and ink.height > 4)
        @assert(Math.abs(ink.horzCenter() - QuickCellSize * 0.5) <= 2)
        @assert(Math.abs(ink.vertCenter() - QuickCellSize * 0.5) <= 2)

        // Half the cell is the ceiling a glyph takes; the rest is what separates one preset
        // from the next.
        @assert(ink.width <= QuickCellSize * 0.6)
        @assert(ink.height <= QuickCellSize * 0.6)
    }
}

// Dismissing the QuickStyle context menu must not disturb the right-side Properties pane.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    f.gui.surfaceWnd.view = f.main

    with f.main.quickStyleBar = SplitterCtrl.create(f.main, {600, 0, 300, 650}, vertical: true)
    {
        .flags.add(.HideDividers)
    }

    f.main.quickWnd = QuickWnd.create(f.main.quickStyleBar, f.main)
    f.main.propWnd  = PropWnd.create(f.main.quickStyleBar, f.main)
    with let quickPane = f.main.quickStyleBar.addPane(f.main.quickWnd)
    {
        .preserveSize = true
    }

    discard f.main.quickStyleBar.addPane(f.main.propWnd)
    f.main.quickStyleBar.setPaneSize(0, 300)

    f.main.quickWnd.setDefault()
    f.main.propWnd.selectionHasChanged()
    f.gui.pump()

    let propRectBefore      = f.main.propWnd.position
    let topLayoutPosBefore  = f.main.propWnd.topLayout.position
    let gridPosBefore       = f.main.propWnd.grid.position
    let gridItemCountBefore = f.main.propWnd.grid.items.count
    let quickPaneSizeBefore = f.main.quickStyleBar.items[0]!.size

    // The sliders are generated by the Properties grid: take the first grid slider row
    // as the "layout did not move" sentinel.
    var sliderCtrlBefore: #null *SliderCtrl
    for item in f.main.propWnd.grid.items
    {
        let it = item!
        if @isset(it.sliderBox)
        {
            sliderCtrlBefore = it.sliderBox
            break
        }
    }

    let sliderBefore         = sliderCtrlBefore!
    let sliderCtrlPosBefore  = sliderBefore.position
    let sliderTrackPosBefore = sliderBefore.slider.position
    let sliderEditPosBefore  = sliderBefore.edit.position
    let propChildCountBefore = f.main.propWnd.topLayout.children.count
    var didDismiss           = false

    f.gui.app.sigFrame += func|host = &f.gui, dismissed = &didDismiss|(app)
    {
        if dismissed[] do
            return

        @assert(host.dismissPopupMenu())
        dismissed[] = true
    }

    f.gui.clickWnd(f.main.quickWnd.layout.children[0], Input.MouseButton.Right)
    f.gui.pump()

    @assert(didDismiss)
    @assert(f.main.propWnd.position == propRectBefore)
    @assert(f.main.propWnd.grid.position == gridPosBefore)
    @assert(f.main.propWnd.grid.items.count == gridItemCountBefore)
    @assert(f.main.quickStyleBar.items[0]!.size == quickPaneSizeBefore)
    @assert(f.main.propWnd.topLayout.position == topLayoutPosBefore)
    @assert(sliderBefore.position == sliderCtrlPosBefore)
    @assert(sliderBefore.slider.position == sliderTrackPosBefore)
    @assert(sliderBefore.edit.position == sliderEditPosBefore)
    @assert(f.main.propWnd.topLayout.children.count == propChildCountBefore)
}

// Default quick styles cover every visible sSnapForge tool family with subkind tagging.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let quick = QuickWnd.create(f.main, f.main)
    quick.setDefault()

    @assert(quick.qsArrow.forms.count > 0)
    @assert(quick.qsLine.forms.count > 0)
    @assert(quick.qsShape.forms.count > 0)
    @assert(quick.qsImage.forms.count > 0)
    @assert(quick.qsStep.forms.count > 0)
    @assert(quick.qsPolygon.forms.count > 0)
    @assert(quick.qsText.forms.count > 0)
    @assert(quick.qsDraw.forms.count > 0)
    @assert(quick.qsHighlight.forms.count > 0)
    @assert(quick.qsPixSel.forms.count > 0)

    for it in quick.qsHighlight.forms
    {
        let base = cast(*BaseForm) @dataof(it)
        @assert(base.subKind == .Highlight)
        @assert(base.alpha < 100)
    }

    for it in quick.qsPixSel.forms
    {
        let base = cast(*BaseForm) @dataof(it)
        @assert(base.subKind == .PixSel)
        @assert(!base.paintShadow)
    }

    // Every image-form kind must be present in the default image styles.
    var imageKinds: Array'FormImageKind
    for it in quick.qsImage.forms
    {
        @assert(@kindof(it) == FormImage)
        imageKinds.add((cast(*FormImage) @dataof(it)).kind)
    }

    @assert(imageKinds.contains(FormImageKind.Image))
    @assert(imageKinds.contains(FormImageKind.Zoom))
    @assert(imageKinds.contains(FormImageKind.Blur))
    @assert(imageKinds.contains(FormImageKind.Pixelate))
    @assert(imageKinds.contains(FormImageKind.Capture))

    quick.destroy()
    f.gui.pump()
}

// A preset cell names what it shows on its tooltip, and that name follows a live language switch.
//
// The word is written once, when the cell is built, so a window that answers a switch by
// repainting alone keeps the previous language on every image preset.
#test
{
    // The tooltip of the preset showing a blurred area, empty when no cell carries one. Blur is
    // the kind whose two wordings differ, so it is the one that can tell the tables apart.
    func blurTip(quick: *QuickWnd)->String
    {
        var result: retval
        for c in quick.layout.children
        {
            let btn = cast(*QuickButton) c
            if btn.userData or !btn.formItf do
                continue
            if @kindof(btn.formItf!) != FormImage do
                continue
            if (cast(*FormImage) @dataof(btn.formItf!)).kind == .Blur do
                return btn.toolTip
        }

        return result
    }

    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    // Whatever this test switches to, the next one starts on the reference wording.
    defer discard catch f.gui.app.setLanguage(Gui.ReferenceLanguage)

    let quick = QuickWnd.create(f.main, f.main)
    f.main.quickWnd = quick
    f.main.editMode = .Image
    quick.setDefault()
    quick.updateQuickStyles(forceRebuild: true)
    @assert(blurTip(quick) == appStrings().prop_KindBlur)

    expect f.gui.app.setLanguage("fr")
    f.gui.notify(.LanguageChanged)
    f.gui.pump()
    @assert(blurTip(quick) == "Flou")

    quick.destroy()
    f.gui.pump()
}

// Reset quick styles goes through the real confirmation dialog and rebuilds the
// current style without leaving stale modal surfaces behind.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    let quick = QuickWnd.create(f.main, f.main)
    f.main.quickWnd = quick
    f.main.editMode = .Shape
    quick.setDefault()
    let defaultCount = quick.qsShape.forms.count

    let extra = Memory.new'FormShape()
    extra.IForm.setup(f.capture)
    quick.qsShape.forms.add(extra)
    quick.updateQuickStyles(forceRebuild: true)
    @assert(quick.qsShape.forms.count == defaultCount + 1)
    @assert(quick.currentStyle == &quick.qsShape)

    f.gui.clickModalButtonWhenShown(Dialog.BtnYes)

    f.main.sendCommandEvent(ActionQuickStyle.Reset)
    f.gui.pump()

    @assert(f.gui.autoHandled)
    @assert(f.gui.openedSurfaceCount() == 0)
    @assert(quick.currentStyle == &quick.qsShape)
    @assert(quick.qsShape.forms.count == defaultCount)

    quick.destroy()
    f.gui.pump()
}

// The QuickStyle context menu can drive the same reset flow as a user: popup
// item, posted command and confirmation dialog.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    let quick = QuickWnd.create(f.main, f.main)
    f.main.quickWnd = quick
    f.main.editMode = .Shape
    quick.setPosition({0, 0, 300, 300})
    quick.setDefault()
    let defaultCount = quick.qsShape.forms.count

    let extra = Memory.new'FormShape()
    extra.IForm.setup(f.capture)
    quick.qsShape.forms.add(extra)
    quick.updateQuickStyles(forceRebuild: true)
    @assert(quick.qsShape.forms.count == defaultCount + 1)

    f.gui.clickPopupMenuItemWhenShown(ActionQuickStyle.Reset)
    f.gui.thenClickModalButton(Dialog.BtnYes)

    f.gui.clickWnd(quick.layout.children[0], Input.MouseButton.Right)

    @assert(f.gui.autoHandled)
    @assert(f.gui.openedSurfaceCount() == 0)
    @assert(quick.qsShape.forms.count == defaultCount)

    quick.destroy()
    f.gui.pump()
}

// QuickStyle.sanitize and clear preserve known sSnapForge forms and release them through the style owner.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    var quickStyle: QuickStyle
    let shape = Memory.new'FormShape()
    shape.IForm.setup(f.capture)
    quickStyle.forms.add(shape)

    quickStyle.sanitize()
    @assert(quickStyle.forms.count == 1)
    @assert(@kindof(quickStyle.forms[0]) == FormShape)

    quickStyle.clear()
    @assert(quickStyle.forms.count == 0)
}
