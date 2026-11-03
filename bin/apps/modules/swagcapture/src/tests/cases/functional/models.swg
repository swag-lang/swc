#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Selection/model synchronization keeps normal, highlight and pixel-selection modes distinct.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    with let shape = testAddShape(f.capture, 10, 10, 40, 30, .Highlight)
    {
        .kind  = .Rectangle
        .alpha = 35
    }

    f.main.updateModel(shape)
    Swag.require(f.main.editMode == .Shape)
    Swag.require(f.main.mdlHighlight.buffer == &f.main.mdlFormShape)
    Swag.require(f.main.mdlFormShape.subKind == .Highlight)

    f.main.updateEditMode(shape)
    Swag.require(f.main.editMode == .Highlight)
    Swag.require(f.main.getEditMode() == .Shape)
    Swag.require(Swag.kindOf(f.main.editModeToModel(.Highlight)) == FormShape)

    var emptyPoints: Array'Math.Vector2

    with let draw = testAddDraw(f.capture, emptyPoints.toSlice())
    {
        .subKind     = .PixSel
        .paintShadow = false
    }

    f.main.updateModel(draw)
    Swag.require(f.main.mdlPixSel.buffer == &f.main.mdlFormDraw)
    Swag.require(f.main.mdlFormDraw.subKind == .PixSel)

    f.main.updateEditMode(draw)
    Swag.require(f.main.editMode == .PixSel)
    Swag.require(f.main.getEditMode() == .Draw)
    Swag.require(Swag.kindOf(f.main.editModeToModel(.PixSel)) == FormDraw)
}

// newFormFromModel clones every standard model and clears point/image payloads when requested.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    f.main.mdlFormShape.kind = .RoundRectangle
    let shape = f.main.newFormFromModel(.Shape)
    Swag.require(Swag.kindOf(shape) == FormShape)
    Swag.require(assume cast(*FormShape, shape).kind == .RoundRectangle)
    testDeleteForm(shape)

    f.main.mdlFormLine.borderSize = 9
    let line = f.main.newFormFromModel(.Line)
    Swag.require(Swag.kindOf(line) == FormLine)
    Swag.require(assume cast(*FormLine, line).borderSize == 9)
    testDeleteForm(line)

    f.main.mdlFormArrow.endSize = 8
    let arrow = f.main.newFormFromModel(.Arrow)
    Swag.require(Swag.kindOf(arrow) == FormArrow)
    Swag.require(assume cast(*FormArrow, arrow).endSize == 8)
    testDeleteForm(arrow)

    f.main.mdlFormPolygon.points.add({1, 1})
    let polygon = f.main.newFormFromModel(.Polygon, clear: true)
    Swag.require(Swag.kindOf(polygon) == FormPolygon)
    Swag.require(assume cast(*FormPolygon, polygon).points.count == 0)
    testDeleteForm(polygon)

    f.main.mdlFormDraw.points.add({1, 1})
    let draw = f.main.newFormFromModel(.Draw, clear: true)
    Swag.require(Swag.kindOf(draw) == FormDraw)
    Swag.require(assume cast(*FormDraw, draw).points.count == 0)
    testDeleteForm(draw)

    f.main.mdlFormText.fontSize = 72
    let text = f.main.newFormFromModel(.Text)
    Swag.require(Swag.kindOf(text) == FormText)
    Swag.require(assume cast(*FormText, text).fontSize == 72)
    testDeleteForm(text)

    f.main.mdlFormStep.ws = 33
    f.main.mdlFormStep.hs = 44
    let step = f.main.newFormFromModel(.Step)
    Swag.require(Swag.kindOf(step) == FormStep)
    Swag.require(assume cast(*FormStep, step).ws == 33)
    Swag.require(assume cast(*FormStep, step).hs == 44)
    testDeleteForm(step)

    f.main.mdlFormImage.kind = .Pixelate
    let image = f.main.newFormFromModel(.Image, clear: true)
    Swag.require(Swag.kindOf(image) == FormImage)
    Swag.require(assume cast(*FormImage, image).kind == .Pixelate)
    Swag.require(not assume cast(*FormImage, image).image.isValid())
    testDeleteForm(image)

    f.main.mdlFormCallout.roundSize = 22
    f.main.mdlFormCallout.text      = "model text"
    let callout = f.main.newFormFromModel(.Callout, clear: true)
    Swag.require(Swag.kindOf(callout) == FormCallout)
    Swag.require(assume cast(*FormCallout, callout).roundSize == 22)

    // clear drops the text payload while keeping the style.
    Swag.require(assume cast(*FormCallout, callout).text.isEmpty())
    testDeleteForm(callout)
}
