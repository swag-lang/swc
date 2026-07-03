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
