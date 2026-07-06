#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// RestoreOrg swaps in the original image and size, clears the forms, and undo brings
// everything back (Flatten/FlattenAll share the same restore path but need a renderer,
// so they are not exercised headless).
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    f.capture.backImgOriginal = Image.create(123, 77, .BGRA8)
    f.capture.widthOrg        = 123
    f.capture.heightOrg       = 77

    let a = captmeTestAddShape(f.capture, 10, 10, 20, 20)
    discard captmeTestAddText(f.capture, 50, 10, 30, 20)
    f.capture.selection.add(0)

    f.capture.pushUndo(f.capture.newUndo(.RestoreOrg))
    @assert(f.capture.forms.count == 0)
    @assert(f.capture.selection.count == 0)
    @assert(f.capture.width == 123)
    @assert(f.capture.height == 77)
    @assert(f.capture.backImg.width == 123)

    f.capture.undo()
    @assert(f.capture.forms.count == 2)
    @assert(@dataof(f.capture.forms[0]) == a)
    @assert(f.capture.width == 400)
    @assert(f.capture.height == 300)
    @assert(f.capture.backImg.width == 400)

    f.capture.redo()
    @assert(f.capture.forms.count == 0)
    @assert(f.capture.width == 123)

    f.capture.undo()
    f.shutdown()
}

// SetImage replaces the background image and position, and restores both on undo.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    var u = f.capture.newUndo(.SetImage)
    u.newImg      = Image.create(50, 40, .BGRA8)
    u.newImagePos = {5, 7}
    f.capture.pushUndo(u)
    @assert(f.capture.backImg.width == 50)
    @assert(f.capture.backImg.height == 40)
    @assert(f.capture.backImagePos.x == 5)
    @assert(f.capture.backImagePos.y == 7)

    f.capture.undo()
    @assert(f.capture.backImg.width == 400)
    @assert(f.capture.backImagePos.x == 0)

    f.capture.redo()
    @assert(f.capture.backImg.width == 50)
    @assert(f.capture.backImagePos.x == 5)

    f.shutdown()
}

// SetImageInside sets the inside image of the selected image forms and restores the
// previous one on undo.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    let imgForm = captmeTestAddImage(f.capture, 50, 50, 60, 40)
    imgForm.image = Image.create(10, 10, .BGRA8)
    f.capture.selection.add(0)

    var u = f.capture.newUndo(.SetImageInside)
    u.newImg = Image.create(20, 30, .BGRA8)
    f.capture.pushUndo(u)
    @assert(imgForm.image.width == 20)
    @assert(imgForm.image.height == 30)

    f.capture.undo()
    @assert(imgForm.image.width == 10)

    f.capture.redo()
    @assert(imgForm.image.width == 20)

    f.shutdown()
}

// SetTypedValue writes a field bit pattern through reflection on every accepted form
// and restores the saved values on undo.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    let shape = captmeTestAddShape(f.capture, 10, 10, 20, 20)
    let text  = captmeTestAddText(f.capture, 50, 10, 30, 20)
    shape.rotate = 33
    text.rotate  = 15
    f.capture.selection.add(0)
    f.capture.selection.add(1)

    let angle = 90.0'f32
    var u = f.capture.newUndo(.SetTypedValue)
    u.valU32 = cast #bit (u32) angle
    u.valRef = Reflection.getField(BaseForm, #nameof(BaseForm.rotate))
    f.capture.pushUndo(u)
    @assert(shape.rotate == 90)
    @assert(text.rotate == 90)

    f.capture.undo()
    @assert(shape.rotate == 33)
    @assert(text.rotate == 15)

    f.capture.redo()
    @assert(shape.rotate == 90)
    @assert(text.rotate == 90)

    f.shutdown()
}

// Regression: the per-kind undo storage is compacted (init skips forms the command does
// not apply to), so undo must walk it with a compact index, not with the selection
// index. Every case below mixes an untouched form before the touched one; before the
// fix the restore read one slot past the saved data.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    // SetText over [shape, text]
    let shape = captmeTestAddShape(f.capture, 10, 10, 20, 20)
    let text  = captmeTestAddText(f.capture, 50, 10, 30, 20)
    text.text = "before"
    f.capture.selection.add(0)
    f.capture.selection.add(1)

    var setText = f.capture.newUndo(.SetText)
    setText.text = "after"
    f.capture.pushUndo(setText)
    @assert(text.text == "after")
    f.capture.undo()
    @assert(text.text == "before")

    // SetTypedValue restricted to FormText over [shape, text]
    shape.rotate = 33
    text.rotate  = 15
    let angle = 90.0'f32
    var setVal = f.capture.newUndo(.SetTypedValue)
    setVal.valU32  = cast #bit (u32) angle
    setVal.valRef  = Reflection.getField(BaseForm, #nameof(BaseForm.rotate))
    setVal.mdlType = FormText
    f.capture.pushUndo(setVal)
    @assert(shape.rotate == 33)
    @assert(text.rotate == 90)
    f.capture.undo()
    @assert(shape.rotate == 33)
    @assert(text.rotate == 15)

    // SetFormFromModel restricted to FormShape over [text, shape]: the model values
    // land on the shape only, and undo restores the shape only.
    shape.borderSize = 3
    f.capture.selection.clear()
    f.capture.selection.add(1)
    f.capture.selection.add(0)

    let model = Memory.new'FormShape()
    model.borderSize = 9
    var style = f.capture.newUndo(.SetFormFromModel)
    style.mdlType  = FormShape
    style.mdlValue = model
    f.capture.pushUndo(style)
    @assert(shape.borderSize == 9)
    f.capture.undo()
    @assert(shape.borderSize == 3)

    f.shutdown()
}

// Regression: undoing an alignment must restore point-based forms too. The restore
// used to write BaseForm.x/y directly, which is a no-op for a line whose geometry
// lives in its end points.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    discard captmeTestAddShape(f.capture, 10, 50, 20, 20)
    let line = captmeTestAddLine(f.capture, 100, 120, 150, 170)
    f.capture.selection.add(0)
    f.capture.selection.add(1)

    f.capture.pushUndo(f.capture.newUndo(.AlignLeft))
    @assert(line.xa == 10)
    @assert(line.xb == 60)

    f.capture.undo()
    @assert(line.xa == 100)
    @assert(line.xb == 150)

    f.capture.pushUndo(f.capture.newUndo(.AlignTop))
    @assert(line.ya == 50)
    f.capture.undo()
    @assert(line.ya == 120)

    f.shutdown()
}

// Regression: SetImageInside over a mixed [shape, image] selection restores the saved
// image from the compact slot.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    discard captmeTestAddShape(f.capture, 10, 10, 20, 20)
    let imgForm = captmeTestAddImage(f.capture, 50, 50, 60, 40)
    imgForm.image = Image.create(10, 10, .BGRA8)
    f.capture.selection.add(0)
    f.capture.selection.add(1)

    var u = f.capture.newUndo(.SetImageInside)
    u.newImg = Image.create(20, 30, .BGRA8)
    f.capture.pushUndo(u)
    @assert(imgForm.image.width == 20)

    f.capture.undo()
    @assert(imgForm.image.width == 10)

    f.capture.redo()
    @assert(imgForm.image.width == 20)

    f.shutdown()
}
