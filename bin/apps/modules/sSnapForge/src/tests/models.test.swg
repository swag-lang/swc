#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Selection/model synchronization keeps normal, highlight and pixel-selection modes distinct.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let shape = testAddShape(f.capture, 10, 10, 40, 30, .Highlight)
    shape.kind  = .Rectangle
    shape.alpha = 35
    f.main.updateModel(shape)
    Swag.assert(f.main.editMode == .Shape)
    Swag.assert(f.main.mdlHighlight.buffer == &f.main.mdlFormShape)
    Swag.assert(f.main.mdlFormShape.subKind == .Highlight)

    f.main.updateEditMode(shape)
    Swag.assert(f.main.editMode == .Highlight)
    Swag.assert(f.main.getEditMode() == .Shape)
    Swag.assert(Swag.kindOf(f.main.editModeToModel(.Highlight)) == FormShape)

    var emptyPoints: Array'Math.Vector2
    let draw = testAddDraw(f.capture, emptyPoints.toSlice())
    draw.subKind     = .PixSel
    draw.paintShadow = false
    f.main.updateModel(draw)
    Swag.assert(f.main.mdlPixSel.buffer == &f.main.mdlFormDraw)
    Swag.assert(f.main.mdlFormDraw.subKind == .PixSel)

    f.main.updateEditMode(draw)
    Swag.assert(f.main.editMode == .PixSel)
    Swag.assert(f.main.getEditMode() == .Draw)
    Swag.assert(Swag.kindOf(f.main.editModeToModel(.PixSel)) == FormDraw)
}

// newFormFromModel clones every standard model and clears point/image payloads when requested.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    f.main.mdlFormShape.kind = .RoundRectangle
    let shape = f.main.newFormFromModel(.Shape)
    Swag.assert(Swag.kindOf(shape) == FormShape)
    Swag.assert((cast(*FormShape) shape.buffer).kind == .RoundRectangle)
    testDeleteForm(shape)

    f.main.mdlFormLine.borderSize = 9
    let line = f.main.newFormFromModel(.Line)
    Swag.assert(Swag.kindOf(line) == FormLine)
    Swag.assert((cast(*FormLine) line.buffer).borderSize == 9)
    testDeleteForm(line)

    f.main.mdlFormArrow.endSize = 8
    let arrow = f.main.newFormFromModel(.Arrow)
    Swag.assert(Swag.kindOf(arrow) == FormArrow)
    Swag.assert((cast(*FormArrow) arrow.buffer).endSize == 8)
    testDeleteForm(arrow)

    f.main.mdlFormPolygon.points.add({1, 1})
    let polygon = f.main.newFormFromModel(.Polygon, clear: true)
    Swag.assert(Swag.kindOf(polygon) == FormPolygon)
    Swag.assert((cast(*FormPolygon) polygon.buffer).points.count == 0)
    testDeleteForm(polygon)

    f.main.mdlFormDraw.points.add({1, 1})
    let draw = f.main.newFormFromModel(.Draw, clear: true)
    Swag.assert(Swag.kindOf(draw) == FormDraw)
    Swag.assert((cast(*FormDraw) draw.buffer).points.count == 0)
    testDeleteForm(draw)

    f.main.mdlFormText.fontSize = 72
    let text = f.main.newFormFromModel(.Text)
    Swag.assert(Swag.kindOf(text) == FormText)
    Swag.assert((cast(*FormText) text.buffer).fontSize == 72)
    testDeleteForm(text)

    f.main.mdlFormStep.ws = 33
    f.main.mdlFormStep.hs = 44
    let step = f.main.newFormFromModel(.Step)
    Swag.assert(Swag.kindOf(step) == FormStep)
    Swag.assert((cast(*FormStep) step.buffer).ws == 33)
    Swag.assert((cast(*FormStep) step.buffer).hs == 44)
    testDeleteForm(step)

    f.main.mdlFormImage.kind = .Pixelate
    let image = f.main.newFormFromModel(.Image, clear: true)
    Swag.assert(Swag.kindOf(image) == FormImage)
    Swag.assert((cast(*FormImage) image.buffer).kind == .Pixelate)
    Swag.assert(!(cast(*FormImage) image.buffer).image.isValid())
    testDeleteForm(image)

    f.main.mdlFormCallout.roundSize = 22
    f.main.mdlFormCallout.text      = "model text"
    let callout = f.main.newFormFromModel(.Callout, clear: true)
    Swag.assert(Swag.kindOf(callout) == FormCallout)
    Swag.assert((cast(*FormCallout) callout.buffer).roundSize == 22)

    // clear drops the text payload while keeping the style.
    Swag.assert((cast(*FormCallout) callout.buffer).text.isEmpty())
    testDeleteForm(callout)
}
