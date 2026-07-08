#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Selection/model synchronization keeps normal, highlight and pixel-selection modes distinct.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    let shape = captmeTestAddShape(f.capture, 10, 10, 40, 30, .Highlight)
    shape.kind = .Rectangle
    shape.alpha = 35
    f.main.updateModel(cast(IForm) shape)
    @assert(f.main.editMode == .Shape)
    @assert(@dataof(f.main.mdlHighlight) == &f.main.mdlFormShape)
    @assert(f.main.mdlFormShape.subKind == .Highlight)

    f.main.updateEditMode(cast(IForm) shape)
    @assert(f.main.editMode == .Highlight)
    @assert(f.main.getEditMode() == .Shape)
    @assert(@kindof(f.main.editModeToModel(.Highlight)) == FormShape)

    var emptyPoints: Array'Math.Vector2
    let draw = captmeTestAddDraw(f.capture, emptyPoints.toSlice())
    draw.subKind = .PixSel
    draw.paintShadow = false
    f.main.updateModel(cast(IForm) draw)
    @assert(@dataof(f.main.mdlPixSel) == &f.main.mdlFormDraw)
    @assert(f.main.mdlFormDraw.subKind == .PixSel)

    f.main.updateEditMode(cast(IForm) draw)
    @assert(f.main.editMode == .PixSel)
    @assert(f.main.getEditMode() == .Draw)
    @assert(@kindof(f.main.editModeToModel(.PixSel)) == FormDraw)

    f.shutdown()
}

// QuickStyle icon previews must never mutate the live model shown by the Properties pane.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    let textItf = f.main.editModeToModel(.Text)
    textItf.setBaseForm(111, 112, 113, 114)
    f.main.mdlFormText.text = "Keep me"
    let textRectBefore = textItf.boundRect()

    var textPaint = quickStyleNewPaintForm(textItf)
    @assert(@dataof(textPaint.itf) != @dataof(textItf))
    @assert(f.main.mdlFormText.text == "Keep me")
    @assert(textItf.boundRect() == textRectBefore)
    @assert((cast(*FormText) @dataof(textPaint.itf)).text == "A")
    quickStyleReleasePaintForm(&textPaint)

    f.main.mdlFormPolygon.points.add({10, 10})
    f.main.mdlFormPolygon.points.add({40, 20})
    f.main.mdlFormPolygon.points.add({20, 50})
    let polyItf = f.main.editModeToModel(.Polygon)
    let pointBefore = f.main.mdlFormPolygon.points[0]

    var polyPaint = quickStyleNewPaintForm(polyItf)
    @assert(@dataof(polyPaint.itf) != @dataof(polyItf))
    @assert(f.main.mdlFormPolygon.points.count == 3)
    @assert(f.main.mdlFormPolygon.points[0] == pointBefore)
    @assert((cast(*FormPolygon) @dataof(polyPaint.itf)).points.count == 6)
    quickStyleReleasePaintForm(&polyPaint)

    f.shutdown()
}

// Dismissing the QuickStyle context menu must not disturb the right-side Properties pane.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()
    f.gui.surfaceWnd.view = f.main

    with f.main.quickStyleBar = SplitterCtrl.create(f.main, {600, 0, 300, 650}, vertical: true)
    {
        .splitterFlags.add(.HideBars)
    }

    f.main.quickWnd = QuickWnd.create(f.main.quickStyleBar, f.main)
    f.main.propWnd  = PropWnd.create(f.main.quickStyleBar, f.main)
    with let quickPane = f.main.quickStyleBar.addPane(f.main.quickWnd, title: true)
    {
        .tryPreserveSize = true
    }
    discard f.main.quickStyleBar.addPane(f.main.propWnd, title: true)
    f.main.quickStyleBar.setPaneSize(0, 300)

    f.main.quickWnd.setDefault()
    f.main.propWnd.selectionHasChanged()
    f.gui.pump()

    let propRectBefore       = f.main.propWnd.position
    let mainLayoutPosBefore  = f.main.propWnd.mainLayout.position
    let propScrollBefore     = f.main.propWnd.scrollSize
    let propScrollBarBefore  = Math.Rectangle{0, f.main.propWnd.posBoxV, 0, f.main.propWnd.sizeBoxV}
    let quickPaneSizeBefore  = f.main.quickStyleBar.items[0].size
    var sliderCtrlBefore: *SliderCtrl
    foreach child in f.main.propWnd.mainLayout.childs
    {
        if child.type == SliderCtrl
        {
            sliderCtrlBefore = cast(*SliderCtrl) child
            break
        }
    }
    @assert(sliderCtrlBefore != null)
    let sliderCtrlPosBefore = sliderCtrlBefore.position
    let sliderTrackPosBefore = sliderCtrlBefore.slider.position
    let sliderEditPosBefore = sliderCtrlBefore.edit.position
    let propChildCountBefore = f.main.propWnd.mainLayout.childs.count
    var didDismiss = false

    f.gui.app.sigFrame += func|host = &f.gui, dismissed = &didDismiss|(app)
    {
        if dref dismissed do
            return

        @assert(host.dismissPopupMenu())
        dref dismissed = true
    }

    f.main.quickWnd.btnPopup(null, {620, 20})
    f.gui.pump()

    @assert(didDismiss)
    @assert(f.main.propWnd.position == propRectBefore)
    @assert(f.main.propWnd.scrollSize == propScrollBefore)
    @assert(Math.Rectangle{0, f.main.propWnd.posBoxV, 0, f.main.propWnd.sizeBoxV} == propScrollBarBefore)
    @assert(f.main.quickStyleBar.items[0].size == quickPaneSizeBefore)
    @assert(f.main.propWnd.mainLayout.position == mainLayoutPosBefore)
    @assert(sliderCtrlBefore.position == sliderCtrlPosBefore)
    @assert(sliderCtrlBefore.slider.position == sliderTrackPosBefore)
    @assert(sliderCtrlBefore.edit.position == sliderEditPosBefore)
    @assert(f.main.propWnd.mainLayout.childs.count == propChildCountBefore)

    f.shutdown()
}

// newFormFromModel clones every standard model and clears point/image payloads when requested.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    f.main.mdlFormShape.kind = .RoundRectangle
    let shape = f.main.newFormFromModel(.Shape)
    @assert(@kindof(shape) == FormShape)
    @assert((cast(*FormShape) @dataof(shape)).kind == .RoundRectangle)
    captmeTestDeleteForm(shape)

    f.main.mdlFormLine.borderSize = 9
    let line = f.main.newFormFromModel(.Line)
    @assert(@kindof(line) == FormLine)
    @assert((cast(*FormLine) @dataof(line)).borderSize == 9)
    captmeTestDeleteForm(line)

    f.main.mdlFormArrow.endSize = 8
    let arrow = f.main.newFormFromModel(.Arrow)
    @assert(@kindof(arrow) == FormArrow)
    @assert((cast(*FormArrow) @dataof(arrow)).endSize == 8)
    captmeTestDeleteForm(arrow)

    f.main.mdlFormPolygon.points.add({1, 1})
    let polygon = f.main.newFormFromModel(.Polygon, clear: true)
    @assert(@kindof(polygon) == FormPolygon)
    @assert((cast(*FormPolygon) @dataof(polygon)).points.count == 0)
    captmeTestDeleteForm(polygon)

    f.main.mdlFormDraw.points.add({1, 1})
    let draw = f.main.newFormFromModel(.Draw, clear: true)
    @assert(@kindof(draw) == FormDraw)
    @assert((cast(*FormDraw) @dataof(draw)).points.count == 0)
    captmeTestDeleteForm(draw)

    f.main.mdlFormText.fontSize = 72
    let text = f.main.newFormFromModel(.Text)
    @assert(@kindof(text) == FormText)
    @assert((cast(*FormText) @dataof(text)).fontSize == 72)
    captmeTestDeleteForm(text)

    f.main.mdlFormStep.ws = 33
    f.main.mdlFormStep.hs = 44
    let step = f.main.newFormFromModel(.Step)
    @assert(@kindof(step) == FormStep)
    @assert((cast(*FormStep) @dataof(step)).ws == 33)
    @assert((cast(*FormStep) @dataof(step)).hs == 44)
    captmeTestDeleteForm(step)

    f.main.mdlFormImage.kind = .Pixelate
    let image = f.main.newFormFromModel(.Image, clear: true)
    @assert(@kindof(image) == FormImage)
    @assert((cast(*FormImage) @dataof(image)).kind == .Pixelate)
    @assert(!(cast(*FormImage) @dataof(image)).image.isValid())
    captmeTestDeleteForm(image)

    f.shutdown()
}

// Default quick styles cover every visible Captme tool family with stable counts and subkind tagging.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    let quick = QuickWnd.create(f.main, f.main)
    quick.setDefault()

    @assert(quick.qsArrow.forms.count == 12)
    @assert(quick.qsLine.forms.count == 7)
    @assert(quick.qsShape.forms.count == 16)
    @assert(quick.qsImage.forms.count == 5)
    @assert(quick.qsStep.forms.count == 8)
    @assert(quick.qsPolygon.forms.count == 10)
    @assert(quick.qsText.forms.count == 14)
    @assert(quick.qsDraw.forms.count == 7)
    @assert(quick.qsHighlight.forms.count == 12)
    @assert(quick.qsPixSel.forms.count == 4)

    foreach it in quick.qsHighlight.forms
    {
        let base = cast(*BaseForm) @dataof(it)
        @assert(base.subKind == .Highlight)
        @assert(base.alpha == 30)
    }

    foreach it in quick.qsPixSel.forms
    {
        let base = cast(*BaseForm) @dataof(it)
        @assert(base.subKind == .PixSel)
        @assert(!base.paintShadow)
    }

    @assert(@kindof(quick.qsImage.forms[0]) == FormImage)
    @assert((cast(*FormImage) @dataof(quick.qsImage.forms[0])).kind == .Image)
    @assert((cast(*FormImage) @dataof(quick.qsImage.forms[1])).kind == .Zoom)
    @assert((cast(*FormImage) @dataof(quick.qsImage.forms[2])).kind == .Blur)
    @assert((cast(*FormImage) @dataof(quick.qsImage.forms[3])).kind == .Pixelate)
    @assert((cast(*FormImage) @dataof(quick.qsImage.forms[4])).kind == .Capture)

    quick.destroy()
    f.gui.pump()
    f.shutdown()
}

// Reset quick styles goes through the real confirmation dialog and rebuilds the
// current style without leaving stale modal surfaces behind.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    let quick = QuickWnd.create(f.main, f.main)
    f.main.quickWnd = quick
    f.main.editMode = .Shape
    quick.setDefault()

    let extra = Memory.new'FormShape()
    extra.IForm.setup(f.capture)
    quick.qsShape.forms.add(cast(IForm) extra)
    quick.updateQuickStyles(forceRebuild: true)
    @assert(quick.qsShape.forms.count == 17)
    @assert(quick.currentStyle == &quick.qsShape)

    var modalFrames: u32
    var didClick: bool
    f.gui.app.sigFrame += func|host = &f.gui, frames = &modalFrames, didClick = &didClick|(app)
    {
        dref frames += 1
        if !dref didClick
        {
            @assert(host.clickModalButton(Dialog.BtnYes))
            dref didClick = true
        }
    }

    @assert(captmeTestActionExecute'ActionQuickStyle(f.main, ActionQuickStyle.Reset))
    f.gui.pump()

    @assert(didClick)
    @assert(modalFrames == 1)
    @assert(f.gui.app.surfaces.count == 0)
    @assert(quick.currentStyle == &quick.qsShape)
    @assert(quick.qsShape.forms.count == 16)

    quick.destroy()
    f.gui.pump()
    f.shutdown()
}

// The QuickStyle context menu can drive the same reset flow as a user: popup
// item, posted command and confirmation dialog.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    let quick = QuickWnd.create(f.main, f.main)
    f.main.quickWnd = quick
    f.main.editMode = .Shape
    f.main.registerAction'ActionQuickStyle()
    quick.setPosition({0, 0, 300, 300})
    quick.setDefault()

    let extra = Memory.new'FormShape()
    extra.IForm.setup(f.capture)
    quick.qsShape.forms.add(cast(IForm) extra)
    quick.updateQuickStyles(forceRebuild: true)
    @assert(quick.qsShape.forms.count == 17)

    var frameCount: u32
    var clickedMenu: bool
    var clickedConfirm: bool
    f.gui.app.sigFrame += func|host = &f.gui, frames = &frameCount, clickedMenu = &clickedMenu, clickedConfirm = &clickedConfirm|(app)
    {
        dref frames += 1
        if !dref clickedMenu
        {
            @assert(host.clickPopupMenuItem(ActionQuickStyle.Reset))
            dref clickedMenu = true
            return
        }

        if !dref clickedConfirm
        {
            @assert(host.clickModalButton(Dialog.BtnYes))
            dref clickedConfirm = true
        }
    }

    f.gui.clickWnd(quick.layout.childs[0], Input.MouseButton.Right)

    @assert(clickedMenu)
    @assert(clickedConfirm)
    @assert(frameCount == 2)
    @assert(f.gui.app.surfaces.count == 0)
    @assert(quick.qsShape.forms.count == 16)

    quick.destroy()
    f.gui.pump()
    f.shutdown()
}

// QuickStyle.sanitize and clear preserve known Captme forms and release them through the style owner.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    var quickStyle: QuickStyle
    let shape = Memory.new'FormShape()
    shape.IForm.setup(f.capture)
    quickStyle.forms.add(cast(IForm) shape)

    quickStyle.sanitize()
    @assert(quickStyle.forms.count == 1)
    @assert(@kindof(quickStyle.forms[0]) == FormShape)

    quickStyle.clear()
    @assert(quickStyle.forms.count == 0)

    f.shutdown()
}
