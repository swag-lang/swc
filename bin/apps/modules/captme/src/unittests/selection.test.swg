#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Selection commands cover all, same type, invert and deselect behavior.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup(registerHeadlessCommands: true)

    discard captmeTestAddShape(f.capture, 10, 10, 10, 10)
    discard captmeTestAddText(f.capture, 30, 10, 10, 10)
    discard captmeTestAddShape(f.capture, 50, 10, 10, 10)

    f.main.sendCommandEvent(ActionSelection.SelectAll)
    @assert(f.capture.selection.count == 3)

    f.capture.selection.clear()
    f.capture.selection.add(0)
    f.main.sendCommandEvent(ActionSelection.SelectSameAll)
    @assert(f.capture.selection.count == 2)
    @assert(f.capture.selection.contains(0))
    @assert(f.capture.selection.contains(2))

    f.main.sendCommandEvent(ActionSelection.InvertSelection)
    @assert(f.capture.selection.count == 1)
    @assert(f.capture.selection[0] == 1)

    f.main.sendCommandEvent(ActionSelection.DeSelectAll)
    @assert(f.capture.selection.count == 0)

    let snap = f.main.snap
    f.main.sendCommandEvent(ActionSelection.Snap)
    @assert(f.main.snap != snap)

    f.shutdown()
}

// Alignment undo stores the correct axis for every horizontal and vertical variant.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    let a = captmeTestAddShape(f.capture, 20, 50, 20, 20)
    let b = captmeTestAddShape(f.capture, 80, 10, 40, 60)
    f.capture.selection.add(0)
    f.capture.selection.add(1)

    f.capture.pushUndo(f.capture.newUndo(.AlignLeft))
    @assert(a.x == 20)
    @assert(b.x == 20)
    f.capture.undo()
    @assert(a.x == 20)
    @assert(b.x == 80)

    f.capture.pushUndo(f.capture.newUndo(.AlignRight))
    @assert(a.x == 100)
    @assert(b.x == 80)
    f.capture.undo()
    @assert(a.x == 20)
    @assert(b.x == 80)

    f.capture.pushUndo(f.capture.newUndo(.AlignCenter))
    @assert(a.x == 60)
    @assert(b.x == 50)
    f.capture.undo()
    @assert(a.x == 20)
    @assert(b.x == 80)

    f.capture.pushUndo(f.capture.newUndo(.AlignTop))
    @assert(a.y == 10)
    @assert(b.y == 10)
    f.capture.undo()
    @assert(a.y == 50)
    @assert(b.y == 10)

    f.capture.pushUndo(f.capture.newUndo(.AlignBottom))
    @assert(a.y == 50)
    @assert(b.y == 10)
    f.capture.undo()
    @assert(a.y == 50)
    @assert(b.y == 10)

    f.capture.pushUndo(f.capture.newUndo(.AlignMiddle))
    @assert(a.y == 30)
    @assert(b.y == 10)
    f.capture.undo()
    @assert(a.y == 50)
    @assert(b.y == 10)

    f.shutdown()
}

// Arrange commands reorder forms and restore both order and selection on undo.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    let a = captmeTestAddShape(f.capture, 0, 0, 10, 10)
    let b = captmeTestAddShape(f.capture, 20, 0, 10, 10)
    let c = captmeTestAddText(f.capture, 40, 0, 10, 10)

    f.capture.selection.add(0)
    f.capture.pushUndo(f.capture.newUndo(.MoveToFront))
    @assert(@dataof(f.capture.forms[2]) == a)
    @assert(f.capture.selection.contains(2))
    f.capture.undo()
    @assert(@dataof(f.capture.forms[0]) == a)
    @assert(@dataof(f.capture.forms[1]) == b)
    @assert(@dataof(f.capture.forms[2]) == c)
    @assert(f.capture.selection.contains(0))

    f.capture.selection.clear()
    f.capture.selection.add(2)
    f.capture.pushUndo(f.capture.newUndo(.MoveToBack))
    @assert(@dataof(f.capture.forms[0]) == c)
    @assert(f.capture.selection.contains(0))
    f.capture.undo()
    @assert(@dataof(f.capture.forms[0]) == a)
    @assert(@dataof(f.capture.forms[1]) == b)
    @assert(@dataof(f.capture.forms[2]) == c)

    f.capture.selection.clear()
    f.capture.selection.add(0)
    f.capture.pushUndo(f.capture.newUndo(.MoveForward))
    @assert(@dataof(f.capture.forms[1]) == a)
    @assert(f.capture.selection.contains(1))
    f.capture.undo()
    @assert(@dataof(f.capture.forms[0]) == a)

    f.capture.selection.clear()
    f.capture.selection.add(2)
    f.capture.pushUndo(f.capture.newUndo(.MoveBackward))
    @assert(@dataof(f.capture.forms[1]) == c)
    @assert(f.capture.selection.contains(1))
    f.capture.undo()
    @assert(@dataof(f.capture.forms[2]) == c)

    f.shutdown()
}

// Offset commands group by serial, undo/redo together and truncate redo after a new edit.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    let a = captmeTestAddShape(f.capture, 10, 10, 10, 10)
    let b = captmeTestAddShape(f.capture, 30, 30, 10, 10)
    f.capture.selection.add(0)
    f.capture.selection.add(1)

    let serial = f.capture.undoMgr.newSerial()

    var u0 = f.capture.newUndo(.OffsetSelection)
    u0.newPosX = 5
    f.capture.pushUndo(u0, serial)

    var u1 = f.capture.newUndo(.OffsetSelection)
    u1.newPosY = 7
    f.capture.pushUndo(u1, serial)

    @assert(a.x == 15)
    @assert(a.y == 17)
    @assert(b.x == 35)
    @assert(b.y == 37)
    @assert(f.capture.undoMgr.count() == 2)
    @assert(f.capture.undoMgr.next == 2)

    f.capture.undo()
    @assert(a.x == 10)
    @assert(a.y == 10)
    @assert(b.x == 30)
    @assert(b.y == 30)
    @assert(f.capture.undoMgr.next == 0)

    f.capture.redo()
    @assert(a.x == 15)
    @assert(a.y == 17)
    @assert(b.x == 35)
    @assert(b.y == 37)

    f.capture.undo()
    var u2 = f.capture.newUndo(.OffsetSelection)
    u2.newPosX = -2
    f.capture.pushUndo(u2)
    @assert(f.capture.undoMgr.count() == 1)
    @assert(a.x == 8)
    @assert(b.x == 28)

    f.shutdown()
}

// Create and delete selection undo records own form lifetime and selection state.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    let a = captmeTestAddShape(f.capture, 0, 0, 10, 10)
    discard captmeTestAddText(f.capture, 20, 0, 10, 10)
    f.capture.selection.add(0)

    f.capture.pushUndo(f.capture.newUndo(.DeleteSelection))
    @assert(f.capture.forms.count == 1)
    @assert(@dataof(f.capture.forms[0]) != a)
    @assert(f.capture.selection.count == 0)

    f.capture.undo()
    @assert(f.capture.forms.count == 2)
    @assert(@dataof(f.capture.forms[0]) == a)
    @assert(f.capture.selection.count == 1)
    @assert(f.capture.selection[0] == 0)

    f.capture.redo()
    @assert(f.capture.forms.count == 1)

    let undo = f.capture.newUndo(.CreateForm)
    let newText = Memory.new'FormText()
    newText.IForm.setup(f.capture)
    newText.IForm.setBaseForm(70, 80, 20, 25)
    undo.oldForms.add(cast(IForm) newText)
    f.capture.pushUndo(undo)
    @assert(f.capture.forms.count == 2)
    @assert(@kindof(f.capture.forms[1]) == FormText)

    f.capture.undo()
    @assert(f.capture.forms.count == 1)
    f.capture.redo()
    @assert(f.capture.forms.count == 2)

    f.shutdown()
}

// MoveBaseForm, MovePoint and MoveCapture undo records cover geometry edits beyond selection moves.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    let shape = captmeTestAddShape(f.capture, 10, 20, 30, 40)
    let line = captmeTestAddLine(f.capture, 100, 120, 150, 170)

    var moveBase = f.capture.newUndo(.MoveBaseForm)
    moveBase.baseForm = cast(IForm) shape
    moveBase.newPosX = 5
    moveBase.newPosY = 6
    moveBase.newSizeX = 7
    moveBase.newSizeY = 8
    f.capture.pushUndo(moveBase)
    Testing.assertRect(shape.IForm.boundRect(), 15, 26, 37, 48)
    f.capture.undo()
    Testing.assertRect(shape.IForm.boundRect(), 10, 20, 30, 40)

    var movePoint = f.capture.newUndo(.MovePoint)
    movePoint.baseForm = cast(IForm) line
    movePoint.pointIdx = 1
    movePoint.newPosX = -10
    movePoint.newPosY = 20
    f.capture.pushUndo(movePoint)
    @assert(line.xb == 140)
    @assert(line.yb == 190)
    f.capture.undo()
    @assert(line.xb == 150)
    @assert(line.yb == 170)

    var moveCapture = f.capture.newUndo(.MoveCapture)
    moveCapture.newPosX = 11
    moveCapture.newPosY = -9
    moveCapture.newSizeX = 5
    moveCapture.newSizeY = -6
    f.capture.pushUndo(moveCapture)
    @assert(f.capture.width == 405)
    @assert(f.capture.height == 294)
    @assert(f.capture.backImagePos.x == 11)
    @assert(f.capture.backImagePos.y == -9)
    @assert(shape.x == 21)
    @assert(line.xa == 111)

    f.capture.undo()
    @assert(f.capture.width == 400)
    @assert(f.capture.height == 300)
    @assert(f.capture.backImagePos.x == 0)
    @assert(f.capture.backImagePos.y == 0)
    @assert(shape.x == 10)
    @assert(line.xa == 100)

    f.shutdown()
}

// Text, font, rotation and style-model undo records restore user-editable form state.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    let text = captmeTestAddText(f.capture, 0, 0, 120, 60)
    text.text = "before"
    text.fontName = "font-a"
    text.fontStyle = .Regular
    text.rotate = 45

    let shape = captmeTestAddShape(f.capture, 150, 0, 50, 50)
    shape.borderSize = 3
    shape.rotate = 30

    f.capture.selection.add(0)
    var setText = f.capture.newUndo(.SetText)
    setText.text = "after"
    f.capture.pushUndo(setText)
    @assert(text.text == "after")
    f.capture.undo()
    @assert(text.text == "before")
    f.capture.redo()
    @assert(text.text == "after")

    var setFont = f.capture.newUndo(.SetFont)
    setFont.text = "font-b"
    setFont.fontStyle = .Bold
    f.capture.pushUndo(setFont)
    @assert(text.fontName == "font-b")
    @assert(text.fontStyle == .Bold)
    f.capture.undo()
    @assert(text.fontName == "font-a")
    @assert(text.fontStyle == .Regular)

    var setFontStyle = f.capture.newUndo(.SetFontStyle)
    setFontStyle.fontStyle = .Italic
    f.capture.pushUndo(setFontStyle)
    @assert(text.fontStyle == .Italic)
    f.capture.undo()
    @assert(text.fontStyle == .Regular)

    f.capture.selection.clear()
    f.capture.selection.add(0)
    f.capture.selection.add(1)
    f.capture.pushUndo(f.capture.newUndo(.ResetRotation))
    @assert(text.rotate == 0)
    @assert(shape.rotate == 0)
    f.capture.undo()
    @assert(text.rotate == 45)
    @assert(shape.rotate == 30)

    f.capture.selection.clear()
    f.capture.selection.add(1)
    let model = Memory.new'FormShape()
    model.subKind = .None
    model.borderSize = 12
    model.backColor = ColorBlue
    var style = f.capture.newUndo(.SetFormFromModel)
    style.mdlType = FormShape
    style.mdlValue = model
    f.capture.pushUndo(style)
    @assert(shape.borderSize == 12)
    @assert(shape.backColor == ColorBlue)
    f.capture.undo()
    @assert(shape.borderSize == 3)

    f.shutdown()
}

// Snap computes x/y offsets against capture bounds and neighboring form edges.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    discard captmeTestAddShape(f.capture, 20, 20, 40, 40)
    let moving = captmeTestAddShape(f.capture, 100, 100, 20, 20)
    f.capture.selection.add(1)
    f.main.snap = true

    var nx = -42
    var ny = -42
    f.capture.snap(&nx, &ny, false, false, editForm: cast(IForm) moving)
    @assert(nx == -40)
    @assert(ny == -40)
    @assert(f.capture.snapX == 60)
    @assert(f.capture.snapY == 60)

    nx = 280
    ny = 180
    f.capture.snap(&nx, &ny, true, true, editForm: cast(IForm) moving)
    @assert(nx == 280)
    @assert(ny == 180)
    @assert(f.capture.snapX == 400)
    @assert(f.capture.snapY == 300)

    f.main.snap = false
    nx = -42
    ny = -42
    f.capture.snap(&nx, &ny, false, false, editForm: cast(IForm) moving)
    @assert(nx == -42)
    @assert(ny == -42)

    f.shutdown()
}
