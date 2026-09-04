#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// RestoreOrg swaps in the original image and size, clears the forms, and undo brings
// everything back.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    f.capture.backImgOriginal = Image.create(123, 77, .BGRA8)
    f.capture.widthOrg        = 123
    f.capture.heightOrg       = 77

    let a = testAddShape(f.capture, 10, 10, 20, 20)
    discard testAddText(f.capture, 50, 10, 30, 20)
    f.capture.selection.add(0)

    f.capture.pushUndo(f.capture.newUndo(.RestoreOrg))
    Swag.assert(f.capture.forms.count == 0)
    Swag.assert(f.capture.selection.count == 0)
    Swag.assert(f.capture.width == 123)
    Swag.assert(f.capture.height == 77)
    Swag.assert(f.capture.backImg.width == 123)

    f.capture.undo()
    Swag.assert(f.capture.forms.count == 2)
    Swag.assert(f.capture.forms[0].buffer == a)
    Swag.assert(f.capture.width == 400)
    Swag.assert(f.capture.height == 300)
    Swag.assert(f.capture.backImg.width == 400)

    f.capture.redo()
    Swag.assert(f.capture.forms.count == 0)
    Swag.assert(f.capture.width == 123)

    f.capture.undo()
}

// Flatten renders the selected forms into the background and removes only that
// selection; undo/redo restore the shared Flatten restore path.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    f.capture.backImg.fill(ColorBlue)
    let shape = testAddShape(f.capture, 10, 10, 30, 25)
    let text  = testAddText(f.capture, 70, 10, 30, 20)
    f.capture.selection.add(0)

    f.capture.pushUndo(f.capture.newUndo(.Flatten))
    Swag.assert(f.capture.forms.count == 1)
    Swag.assert(f.capture.forms[0].buffer == text)
    Swag.assert(f.capture.selection.count == 0)
    Swag.assert(f.capture.backImg.isValid())
    Swag.assert(f.capture.backImg.width == 400)
    Swag.assert(f.capture.backImg.height == 300)

    f.capture.undo()
    Swag.assert(f.capture.forms.count == 2)
    Swag.assert(f.capture.forms[0].buffer == shape)
    Swag.assert(f.capture.forms[1].buffer == text)

    f.capture.redo()
    Swag.assert(f.capture.forms.count == 1)
    Swag.assert(f.capture.forms[0].buffer == text)
}

// FlattenAll renders every non-pixel-selection form into the background and clears
// the form list; undo/redo use the same image/form restore data.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    f.capture.backImg.fill(ColorBlue)
    discard testAddShape(f.capture, 10, 10, 30, 25)
    discard testAddText(f.capture, 70, 10, 30, 20)

    f.capture.pushUndo(f.capture.newUndo(.FlattenAll))
    Swag.assert(f.capture.forms.count == 0)
    Swag.assert(f.capture.selection.count == 0)
    Swag.assert(f.capture.backImg.isValid())
    Swag.assert(f.capture.backImg.width == 400)
    Swag.assert(f.capture.backImg.height == 300)

    f.capture.undo()
    Swag.assert(f.capture.forms.count == 2)

    f.capture.redo()
    Swag.assert(f.capture.forms.count == 0)
}

// SetImage replaces the background image and position, and restores both on undo.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    var u = f.capture.newUndo(.SetImage)
    u.newImg      = Image.create(50, 40, .BGRA8)
    u.newImagePos = {5, 7}
    f.capture.pushUndo(u)
    Swag.assert(f.capture.backImg.width == 50)
    Swag.assert(f.capture.backImg.height == 40)
    Swag.assert(f.capture.backImagePos.x == 5)
    Swag.assert(f.capture.backImagePos.y == 7)

    f.capture.undo()
    Swag.assert(f.capture.backImg.width == 400)
    Swag.assert(f.capture.backImagePos.x == 0)

    f.capture.redo()
    Swag.assert(f.capture.backImg.width == 50)
    Swag.assert(f.capture.backImagePos.x == 5)
}

// SetImageInside sets the inside image of the selected image forms and restores the
// previous one on undo.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let imgForm = testAddImage(f.capture, 50, 50, 60, 40)
    imgForm.image = Image.create(10, 10, .BGRA8)
    f.capture.selection.add(0)

    var u = f.capture.newUndo(.SetImageInside)
    u.newImg = Image.create(20, 30, .BGRA8)
    f.capture.pushUndo(u)
    Swag.assert(imgForm.image.width == 20)
    Swag.assert(imgForm.image.height == 30)

    f.capture.undo()
    Swag.assert(imgForm.image.width == 10)

    f.capture.redo()
    Swag.assert(imgForm.image.width == 20)
}

// SetTypedValue writes a field bit pattern through reflection on every accepted form
// and restores the saved values on undo.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let shape = testAddShape(f.capture, 10, 10, 20, 20)
    let text  = testAddText(f.capture, 50, 10, 30, 20)
    shape.rotate = 33
    text.rotate  = 15
    f.capture.selection.add(0)
    f.capture.selection.add(1)

    let angle = 90.0'f32
    var u     = f.capture.newUndo(.SetTypedValue)
    u.valU32 = cast #bit (u32) angle
    u.valRef = Reflection.findField(BaseForm, #nameof(BaseForm.rotate))!
    f.capture.pushUndo(u)
    Swag.assert(shape.rotate == 90)
    Swag.assert(text.rotate == 90)

    f.capture.undo()
    Swag.assert(shape.rotate == 33)
    Swag.assert(text.rotate == 15)

    f.capture.redo()
    Swag.assert(shape.rotate == 90)
    Swag.assert(text.rotate == 90)
}

// Regression: the per-kind undo storage is compacted (init skips forms the command does
// not apply to), so undo must walk it with a compact index, not with the selection
// index. Every case below mixes an untouched form before the touched one; before the
// fix the restore read one slot past the saved data.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    // SetText over [shape, text]
    let shape = testAddShape(f.capture, 10, 10, 20, 20)
    let text  = testAddText(f.capture, 50, 10, 30, 20)
    text.text = "before"
    f.capture.selection.add(0)
    f.capture.selection.add(1)

    var setText = f.capture.newUndo(.SetText)
    setText.text = "after"
    f.capture.pushUndo(setText)
    Swag.assert(text.text == "after")
    f.capture.undo()
    Swag.assert(text.text == "before")

    // SetTypedValue restricted to FormText over [shape, text]
    shape.rotate = 33
    text.rotate  = 15
    let angle  = 90.0'f32
    var setVal = f.capture.newUndo(.SetTypedValue)
    setVal.valU32  = cast #bit (u32) angle
    setVal.valRef  = Reflection.findField(BaseForm, #nameof(BaseForm.rotate))!
    setVal.mdlType = FormText
    f.capture.pushUndo(setVal)
    Swag.assert(shape.rotate == 33)
    Swag.assert(text.rotate == 90)
    f.capture.undo()
    Swag.assert(shape.rotate == 33)
    Swag.assert(text.rotate == 15)

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
    Swag.assert(shape.borderSize == 9)
    f.capture.undo()
    Swag.assert(shape.borderSize == 3)
}

// Regression: undoing an alignment must restore point-based forms too. The restore
// used to write BaseForm.x/y directly, which is a no-op for a line whose geometry
// lives in its end points.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    discard testAddShape(f.capture, 10, 50, 20, 20)
    let line = testAddLine(f.capture, 100, 120, 150, 170)
    f.capture.selection.add(0)
    f.capture.selection.add(1)

    f.capture.pushUndo(f.capture.newUndo(.AlignLeft))
    Swag.assert(line.xa == 10)
    Swag.assert(line.xb == 60)

    f.capture.undo()
    Swag.assert(line.xa == 100)
    Swag.assert(line.xb == 150)

    f.capture.pushUndo(f.capture.newUndo(.AlignTop))
    Swag.assert(line.ya == 50)
    f.capture.undo()
    Swag.assert(line.ya == 120)
}

// Regression: SetImageInside over a mixed [shape, image] selection restores the saved
// image from the compact slot.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    discard testAddShape(f.capture, 10, 10, 20, 20)
    let imgForm = testAddImage(f.capture, 50, 50, 60, 40)
    imgForm.image = Image.create(10, 10, .BGRA8)
    f.capture.selection.add(0)
    f.capture.selection.add(1)

    var u = f.capture.newUndo(.SetImageInside)
    u.newImg = Image.create(20, 30, .BGRA8)
    f.capture.pushUndo(u)
    Swag.assert(imgForm.image.width == 20)

    f.capture.undo()
    Swag.assert(imgForm.image.width == 10)

    f.capture.redo()
    Swag.assert(imgForm.image.width == 20)
}

// Geometry signature of one form, used by the metamorphic undo test below: the
// per-kind style checks are covered elsewhere, what a long undo chain can corrupt
// is geometry (rects, endpoints, point lists, rotation) and form order.
struct UndoFuzzForm
{
    late kind: typeinfo
    rect:      Math.Rectangle
    rotate:    f32
    points:    Array'Math.Vector2
}

struct UndoFuzzState
{
    width:    s32
    height:   s32
    imagePos: Math.Point
    forms:    Array'UndoFuzzForm
}

func testUndoFuzzFormOf(itf: IForm)->UndoFuzzForm
{
    var result: retval
    result.kind   = Swag.kindOf(itf)
    result.rect   = itf.boundRect()
    result.rotate = (cast(*BaseForm) itf.buffer).rotate

    if result.kind == FormLine
    {
        let line = cast(*FormLine) itf.buffer
        result.points.add({cast(f32) line.xa, cast(f32) line.ya})
        result.points.add({cast(f32) line.xb, cast(f32) line.yb})
    }
    elif result.kind == FormArrow
    {
        let arrow = cast(*FormArrow) itf.buffer
        result.points.add({cast(f32) arrow.xa, cast(f32) arrow.ya})
        result.points.add({cast(f32) arrow.xb, cast(f32) arrow.yb})
    }
    elif result.kind == FormPolygon
    {
        let poly = cast(*FormPolygon) itf.buffer
        for pt in poly.points do
            result.points.add(pt)
    }
    elif result.kind == FormDraw
    {
        let draw = cast(*FormDraw) itf.buffer
        for pt in draw.points do
            result.points.add(pt)
    }

    return result
}

func testUndoFuzzSnapshot(capture: *Capture)->UndoFuzzState
{
    var result: retval
    result.width    = capture.width
    result.height   = capture.height
    result.imagePos = capture.backImagePos
    for it in capture.forms do
        result.forms.add(testUndoFuzzFormOf(it))
    return result
}

// Selection is deliberately not part of the state compare: several undo kinds
// legitimately restore it differently from where the random walk left it.
func testUndoFuzzAssertState(capture: *Capture, snap: *UndoFuzzState)
{
    Swag.assert(capture.width == snap.width)
    Swag.assert(capture.height == snap.height)
    Swag.assert(Math.abs(capture.backImagePos.x - snap.imagePos.x) < 0.01)
    Swag.assert(Math.abs(capture.backImagePos.y - snap.imagePos.y) < 0.01)
    Swag.assert(capture.forms.count == snap.forms.count)

    for it, idx in capture.forms
    {
        var cur = testUndoFuzzFormOf(it)
        Swag.assert(cur.kind == snap.forms[idx].kind)
        Swag.assert(Math.abs(cur.rect.x - snap.forms[idx].rect.x) < 0.01)
        Swag.assert(Math.abs(cur.rect.y - snap.forms[idx].rect.y) < 0.01)
        Swag.assert(Math.abs(cur.rect.width - snap.forms[idx].rect.width) < 0.01)
        Swag.assert(Math.abs(cur.rect.height - snap.forms[idx].rect.height) < 0.01)
        Swag.assert(Math.abs(cur.rotate - snap.forms[idx].rotate) < 0.01)
        Swag.assert(cur.points.count == snap.forms[idx].points.count)
        for pt, pidx in cur.points
        {
            Swag.assert(Math.abs(pt.x - snap.forms[idx].points[pidx].x) < 0.01)
            Swag.assert(Math.abs(pt.y - snap.forms[idx].points[pidx].y) < 0.01)
        }
    }
}

func testUndoFuzzSelect(capture: *Capture, rng: *Random.Generator, count: u32)
{
    capture.selection.clear()
    let total = cast(u32) capture.forms.count
    let want  = cast(u64) Math.min(count, total)
    while capture.selection.count < want
    {
        let idx = cast(u64) rng.nextU32(0, total)
        if !capture.selection.contains(idx) do
            capture.selection.add(idx)
    }
}

// Metamorphic undo/redo check: apply a long, seeded random sequence of undoable
// operations, then undo everything and require the exact initial geometry; redo
// everything and require the final geometry; undo once more to close the loop.
// This exercises interactions between undo kinds (create/delete/reorder over
// forms referenced by earlier records) that the case-by-case tests never combine.
// The seed is fixed so any failure is reproducible.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    discard testAddShape(f.capture, 10, 10, 40, 30)
    discard testAddShape(f.capture, 60, 20, 30, 30)
    discard testAddText(f.capture, 100, 10, 50, 20)
    discard testAddLine(f.capture, 20, 80, 90, 120)
    discard testAddArrow(f.capture, 120, 80, 180, 130)
    discard testAddStep(f.capture, 200, 40, 30, 30)

    var points: Array'Math.Vector2
    points.add({30, 150})
    points.add({80, 150})
    points.add({60, 200})
    discard testAddPolygon(f.capture, points.toSlice())
    discard testAddDraw(f.capture, points.toSlice())

    Swag.assert(!f.capture.canUndo())
    var snapInitial = testUndoFuzzSnapshot(f.capture)

    var rng: Random.Generator
    rng.seedU32(0x51CA97)

    let alignKinds   = [UndoKind.AlignLeft, UndoKind.AlignCenter, UndoKind.AlignRight, UndoKind.AlignTop, UndoKind.AlignMiddle, UndoKind.AlignBottom]
    let arrangeKinds = [UndoKind.MoveToFront, UndoKind.MoveToBack, UndoKind.MoveForward, UndoKind.MoveBackward]

    var step = 0
    while step < 140
    {
        step += 1
        let op = rng.nextU32(0, 10)

        if op == 0
        {
            testUndoFuzzSelect(f.capture, &rng, rng.nextU32(1, 4))
            let u = f.capture.newUndo(.OffsetSelection)
            u.newPosX = rng.nextS32(-8, 9)
            u.newPosY = rng.nextS32(-8, 9)
            f.capture.pushUndo(u)
        }
        elif op == 1
        {
            testUndoFuzzSelect(f.capture, &rng, 2)
            f.capture.pushUndo(f.capture.newUndo(alignKinds[rng.nextU32(0, 6)]))
        }
        elif op == 2
        {
            testUndoFuzzSelect(f.capture, &rng, 1)
            f.capture.pushUndo(f.capture.newUndo(arrangeKinds[rng.nextU32(0, 4)]))
        }
        elif op == 3
        {
            if f.capture.forms.count > 4
            {
                testUndoFuzzSelect(f.capture, &rng, 1)
                f.capture.pushUndo(f.capture.newUndo(.DeleteSelection))
            }
        }
        elif op == 4
        {
            let u = f.capture.newUndo(.CreateForm)
            if rng.nextBool()
            {
                let form = Memory.new'FormShape()
                form.IForm.setup(f.capture)
                form.IForm.setBaseForm(rng.nextS32(0, 350), rng.nextS32(0, 250), rng.nextS32(5, 60), rng.nextS32(5, 60))
                u.oldForms.add(form)
            }
            else
            {
                let form = Memory.new'FormText()
                form.IForm.setup(f.capture)
                form.IForm.setBaseForm(rng.nextS32(0, 350), rng.nextS32(0, 250), rng.nextS32(10, 80), rng.nextS32(10, 40))
                u.oldForms.add(form)
            }

            f.capture.pushUndo(u)
        }
        elif op == 5
        {
            testUndoFuzzSelect(f.capture, &rng, rng.nextU32(1, 4))
            f.capture.pushUndo(f.capture.newUndo(.ResetRotation))
        }
        elif op == 6
        {
            testUndoFuzzSelect(f.capture, &rng, rng.nextU32(1, 3))
            let angle = cast(f32) rng.nextS32(0, 360)
            let u     = f.capture.newUndo(.SetTypedValue)
            u.valU32 = cast #bit (u32) angle
            u.valRef = Reflection.findField(BaseForm, #nameof(BaseForm.rotate))!
            f.capture.pushUndo(u)
        }
        elif op == 7
        {
            let idx = cast(u64) rng.nextU32(0, cast(u32) f.capture.forms.count)
            let itf = f.capture.forms[idx]
            let u   = f.capture.newUndo(.MoveBaseForm)
            u.baseForm = itf
            u.newPosX  = rng.nextS32(-10, 11)
            u.newPosY  = rng.nextS32(-10, 11)

            // Size deltas rescale the point list of point-based forms, which is not
            // exactly invertible in f32; keep them for the integer box forms only.
            let kind = Swag.kindOf(itf)
            if kind == FormShape or kind == FormText or kind == FormStep
            {
                u.newSizeX = rng.nextS32(-3, 8)
                u.newSizeY = rng.nextS32(-3, 8)
            }

            f.capture.pushUndo(u)
        }
        elif op == 8
        {
            var candidates: Array'u64
            for it, idx in f.capture.forms
            {
                let kind = Swag.kindOf(it)
                if kind == FormLine or kind == FormArrow do
                    candidates.add(idx)
            }

            if candidates.count > 0
            {
                let itf = f.capture.forms[candidates[rng.nextU32(0, cast(u32) candidates.count)]]
                let u   = f.capture.newUndo(.MovePoint)
                u.baseForm = itf
                u.pointIdx = rng.nextU32(0, 2)
                u.newPosX  = rng.nextS32(-10, 11)
                u.newPosY  = rng.nextS32(-10, 11)
                f.capture.pushUndo(u)
            }
        }
        else
        {
            let u = f.capture.newUndo(.MoveCapture)
            u.newPosX  = rng.nextS32(-3, 4)
            u.newPosY  = rng.nextS32(-3, 4)
            u.newSizeX = rng.nextS32(-2, 5)
            u.newSizeY = rng.nextS32(-2, 5)
            if f.capture.width + u.newSizeX < 100 do
                u.newSizeX = 2
            if f.capture.height + u.newSizeY < 100 do
                u.newSizeY = 2
            f.capture.pushUndo(u)
        }
    }

    Swag.assert(f.capture.canUndo())
    var snapFinal = testUndoFuzzSnapshot(f.capture)

    while f.capture.canUndo() do
        f.capture.undo()
    Swag.assert(!f.capture.canUndo())
    testUndoFuzzAssertState(f.capture, &snapInitial)

    while f.capture.canRedo() do
        f.capture.redo()
    Swag.assert(!f.capture.canRedo())
    testUndoFuzzAssertState(f.capture, &snapFinal)

    while f.capture.canUndo() do
        f.capture.undo()
    testUndoFuzzAssertState(f.capture, &snapInitial)
}
