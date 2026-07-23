#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// RestoreOrg swaps in the original image and size, clears the forms, and undo brings
// everything back.
#test
{
    var f: HeadlessFixture
    f.setup()

    f.capture.backImgOriginal = Image.create(123, 77, .BGRA8)
    f.capture.widthOrg        = 123
    f.capture.heightOrg       = 77

    let a = testAddShape(f.capture, 10, 10, 20, 20)
    discard testAddText(f.capture, 50, 10, 30, 20)
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

// Flatten renders the selected forms into the background and removes only that
// selection; undo/redo restore the shared Flatten restore path.
#test
{
    var f: HeadlessFixture
    f.setup()

    f.capture.backImg.fill(ColorBlue)
    let shape = testAddShape(f.capture, 10, 10, 30, 25)
    let text  = testAddText(f.capture, 70, 10, 30, 20)
    f.capture.selection.add(0)

    f.capture.pushUndo(f.capture.newUndo(.Flatten))
    @assert(f.capture.forms.count == 1)
    @assert(@dataof(f.capture.forms[0]) == text)
    @assert(f.capture.selection.count == 0)
    @assert(f.capture.backImg.isValid())
    @assert(f.capture.backImg.width == 400)
    @assert(f.capture.backImg.height == 300)

    f.capture.undo()
    @assert(f.capture.forms.count == 2)
    @assert(@dataof(f.capture.forms[0]) == shape)
    @assert(@dataof(f.capture.forms[1]) == text)

    f.capture.redo()
    @assert(f.capture.forms.count == 1)
    @assert(@dataof(f.capture.forms[0]) == text)

    f.shutdown()
}

// FlattenAll renders every non-pixel-selection form into the background and clears
// the form list; undo/redo use the same image/form restore data.
#test
{
    var f: HeadlessFixture
    f.setup()

    f.capture.backImg.fill(ColorBlue)
    discard testAddShape(f.capture, 10, 10, 30, 25)
    discard testAddText(f.capture, 70, 10, 30, 20)

    f.capture.pushUndo(f.capture.newUndo(.FlattenAll))
    @assert(f.capture.forms.count == 0)
    @assert(f.capture.selection.count == 0)
    @assert(f.capture.backImg.isValid())
    @assert(f.capture.backImg.width == 400)
    @assert(f.capture.backImg.height == 300)

    f.capture.undo()
    @assert(f.capture.forms.count == 2)

    f.capture.redo()
    @assert(f.capture.forms.count == 0)

    f.shutdown()
}

// SetImage replaces the background image and position, and restores both on undo.
#test
{
    var f: HeadlessFixture
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
    var f: HeadlessFixture
    f.setup()

    let imgForm = testAddImage(f.capture, 50, 50, 60, 40)
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
    var f: HeadlessFixture
    f.setup()

    let shape = testAddShape(f.capture, 10, 10, 20, 20)
    let text  = testAddText(f.capture, 50, 10, 30, 20)
    shape.rotate = 33
    text.rotate  = 15
    f.capture.selection.add(0)
    f.capture.selection.add(1)

    let angle = 90.0'f32
    var u = f.capture.newUndo(.SetTypedValue)
    u.valU32 = cast #bit (u32) angle
    u.valRef = notnull Reflection.getField(BaseForm, #nameof(BaseForm.rotate))
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
    var f: HeadlessFixture
    f.setup()

    // SetText over [shape, text]
    let shape = testAddShape(f.capture, 10, 10, 20, 20)
    let text  = testAddText(f.capture, 50, 10, 30, 20)
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
    setVal.valRef  = notnull Reflection.getField(BaseForm, #nameof(BaseForm.rotate))
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
    var f: HeadlessFixture
    f.setup()

    discard testAddShape(f.capture, 10, 50, 20, 20)
    let line = testAddLine(f.capture, 100, 120, 150, 170)
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
    var f: HeadlessFixture
    f.setup()

    discard testAddShape(f.capture, 10, 10, 20, 20)
    let imgForm = testAddImage(f.capture, 50, 50, 60, 40)
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

// Geometry signature of one form, used by the metamorphic undo test below: the
// per-kind style checks are covered elsewhere, what a long undo chain can corrupt
// is geometry (rects, endpoints, point lists, rotation) and form order.
struct UndoFuzzForm
{
    kind:   typeinfo = undefined
    rect:   Math.Rectangle
    rotate: f32
    points: Array'Math.Vector2
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
    result.kind   = @kindof(itf)
    result.rect   = itf.boundRect()
    result.rotate = (cast(*BaseForm) @dataof(itf)).rotate

    if result.kind == FormLine
    {
        let line = cast(*FormLine) @dataof(itf)
        result.points.add({cast(f32) line.xa, cast(f32) line.ya})
        result.points.add({cast(f32) line.xb, cast(f32) line.yb})
    }
    elif result.kind == FormArrow
    {
        let arrow = cast(*FormArrow) @dataof(itf)
        result.points.add({cast(f32) arrow.xa, cast(f32) arrow.ya})
        result.points.add({cast(f32) arrow.xb, cast(f32) arrow.yb})
    }
    elif result.kind == FormPolygon
    {
        let poly = cast(*FormPolygon) @dataof(itf)
        for pt in poly.points do
            result.points.add(pt)
    }
    elif result.kind == FormDraw
    {
        let draw = cast(*FormDraw) @dataof(itf)
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
    @assert(capture.width == snap.width)
    @assert(capture.height == snap.height)
    @assert(Math.abs(capture.backImagePos.x - snap.imagePos.x) < 0.01)
    @assert(Math.abs(capture.backImagePos.y - snap.imagePos.y) < 0.01)
    @assert(capture.forms.count == snap.forms.count)

    for it, idx in capture.forms
    {
        var cur = testUndoFuzzFormOf(it)
        @assert(cur.kind == snap.forms[idx].kind)
        @assert(Math.abs(cur.rect.x - snap.forms[idx].rect.x) < 0.01)
        @assert(Math.abs(cur.rect.y - snap.forms[idx].rect.y) < 0.01)
        @assert(Math.abs(cur.rect.width - snap.forms[idx].rect.width) < 0.01)
        @assert(Math.abs(cur.rect.height - snap.forms[idx].rect.height) < 0.01)
        @assert(Math.abs(cur.rotate - snap.forms[idx].rotate) < 0.01)
        @assert(cur.points.count == snap.forms[idx].points.count)
        for pt, pidx in cur.points
        {
            @assert(Math.abs(pt.x - snap.forms[idx].points[pidx].x) < 0.01)
            @assert(Math.abs(pt.y - snap.forms[idx].points[pidx].y) < 0.01)
        }
    }
}

func testUndoFuzzSelect(capture: *Capture, rng: *Random.Rng, count: u32)
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

    @assert(!f.capture.canUndo())
    var snapInitial = testUndoFuzzSnapshot(f.capture)

    var rng: Random.Rng
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
                u.oldForms.add(cast(IForm) form)
            }
            else
            {
                let form = Memory.new'FormText()
                form.IForm.setup(f.capture)
                form.IForm.setBaseForm(rng.nextS32(0, 350), rng.nextS32(0, 250), rng.nextS32(10, 80), rng.nextS32(10, 40))
                u.oldForms.add(cast(IForm) form)
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
            let u = f.capture.newUndo(.SetTypedValue)
            u.valU32 = cast #bit (u32) angle
            u.valRef = notnull Reflection.getField(BaseForm, #nameof(BaseForm.rotate))
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
            let kind = @kindof(itf)
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
                let kind = @kindof(it)
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

    @assert(f.capture.canUndo())
    var snapFinal = testUndoFuzzSnapshot(f.capture)

    while f.capture.canUndo() do
        f.capture.undo()
    @assert(!f.capture.canUndo())
    testUndoFuzzAssertState(f.capture, &snapInitial)

    while f.capture.canRedo() do
        f.capture.redo()
    @assert(!f.capture.canRedo())
    testUndoFuzzAssertState(f.capture, &snapFinal)

    while f.capture.canUndo() do
        f.capture.undo()
    testUndoFuzzAssertState(f.capture, &snapInitial)

    f.shutdown()
}
