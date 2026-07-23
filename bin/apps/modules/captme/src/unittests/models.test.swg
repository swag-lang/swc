#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Selection/model synchronization keeps normal, highlight and pixel-selection modes distinct.
#test
{
    var f: HeadlessFixture
    f.setup()

    let shape = testAddShape(f.capture, 10, 10, 40, 30, .Highlight)
    shape.kind  = .Rectangle
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
    let draw = testAddDraw(f.capture, emptyPoints.toSlice())
    draw.subKind     = .PixSel
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
    var f: HeadlessFixture
    f.setup()

    f.main.mdlFormShape.kind = .RoundRectangle
    let shape = f.main.newFormFromModel(.Shape)
    @assert(@kindof(shape) == FormShape)
    @assert((cast(*FormShape) @dataof(shape)).kind == .RoundRectangle)
    testDeleteForm(shape)

    f.main.mdlFormLine.borderSize = 9
    let line = f.main.newFormFromModel(.Line)
    @assert(@kindof(line) == FormLine)
    @assert((cast(*FormLine) @dataof(line)).borderSize == 9)
    testDeleteForm(line)

    f.main.mdlFormArrow.endSize = 8
    let arrow = f.main.newFormFromModel(.Arrow)
    @assert(@kindof(arrow) == FormArrow)
    @assert((cast(*FormArrow) @dataof(arrow)).endSize == 8)
    testDeleteForm(arrow)

    f.main.mdlFormPolygon.points.add({1, 1})
    let polygon = f.main.newFormFromModel(.Polygon, clear: true)
    @assert(@kindof(polygon) == FormPolygon)
    @assert((cast(*FormPolygon) @dataof(polygon)).points.count == 0)
    testDeleteForm(polygon)

    f.main.mdlFormDraw.points.add({1, 1})
    let draw = f.main.newFormFromModel(.Draw, clear: true)
    @assert(@kindof(draw) == FormDraw)
    @assert((cast(*FormDraw) @dataof(draw)).points.count == 0)
    testDeleteForm(draw)

    f.main.mdlFormText.fontSize = 72
    let text = f.main.newFormFromModel(.Text)
    @assert(@kindof(text) == FormText)
    @assert((cast(*FormText) @dataof(text)).fontSize == 72)
    testDeleteForm(text)

    f.main.mdlFormStep.ws = 33
    f.main.mdlFormStep.hs = 44
    let step = f.main.newFormFromModel(.Step)
    @assert(@kindof(step) == FormStep)
    @assert((cast(*FormStep) @dataof(step)).ws == 33)
    @assert((cast(*FormStep) @dataof(step)).hs == 44)
    testDeleteForm(step)

    f.main.mdlFormImage.kind = .Pixelate
    let image = f.main.newFormFromModel(.Image, clear: true)
    @assert(@kindof(image) == FormImage)
    @assert((cast(*FormImage) @dataof(image)).kind == .Pixelate)
    @assert(!(cast(*FormImage) @dataof(image)).image.isValid())
    testDeleteForm(image)

    f.main.mdlFormCallout.roundSize = 22
    f.main.mdlFormCallout.text      = "model text"
    let callout = f.main.newFormFromModel(.Callout, clear: true)
    @assert(@kindof(callout) == FormCallout)
    @assert((cast(*FormCallout) @dataof(callout)).roundSize == 22)

    // clear drops the text payload while keeping the style.
    @assert((cast(*FormCallout) @dataof(callout)).text.isEmpty())
    testDeleteForm(callout)

    f.shutdown()
}
