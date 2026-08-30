#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Selection commands cover all, same type, invert and deselect behavior.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    discard testAddShape(f.capture, 10, 10, 10, 10)
    discard testAddText(f.capture, 30, 10, 10, 10)
    discard testAddShape(f.capture, 50, 10, 10, 10)

    f.main.sendCommandEvent(ActionSelection.SelectAll)
    Swag.assert(f.capture.selection.count == 3)

    f.capture.selection.clear()
    f.capture.selection.add(0)
    f.main.sendCommandEvent(ActionSelection.SelectSameAll)
    Swag.assert(f.capture.selection.count == 2)
    Swag.assert(f.capture.selection.contains(0))
    Swag.assert(f.capture.selection.contains(2))

    f.main.sendCommandEvent(ActionSelection.InvertSelection)
    Swag.assert(f.capture.selection.count == 1)
    Swag.assert(f.capture.selection[0] == 1)

    f.main.sendCommandEvent(ActionSelection.DeSelectAll)
    Swag.assert(f.capture.selection.count == 0)

    let snap = f.main.snap
    f.main.sendCommandEvent(ActionSelection.Snap)
    Swag.assert(f.main.snap != snap)
}

// Alignment undo stores the correct axis for every horizontal and vertical variant.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let a = testAddShape(f.capture, 20, 50, 20, 20)
    let b = testAddShape(f.capture, 80, 10, 40, 60)
    f.capture.selection.add(0)
    f.capture.selection.add(1)

    f.capture.pushUndo(f.capture.newUndo(.AlignLeft))
    Swag.assert(a.x == 20)
    Swag.assert(b.x == 20)
    f.capture.undo()
    Swag.assert(a.x == 20)
    Swag.assert(b.x == 80)

    f.capture.pushUndo(f.capture.newUndo(.AlignRight))
    Swag.assert(a.x == 100)
    Swag.assert(b.x == 80)
    f.capture.undo()
    Swag.assert(a.x == 20)
    Swag.assert(b.x == 80)

    f.capture.pushUndo(f.capture.newUndo(.AlignCenter))
    Swag.assert(a.x == 60)
    Swag.assert(b.x == 50)
    f.capture.undo()
    Swag.assert(a.x == 20)
    Swag.assert(b.x == 80)

    f.capture.pushUndo(f.capture.newUndo(.AlignTop))
    Swag.assert(a.y == 10)
    Swag.assert(b.y == 10)
    f.capture.undo()
    Swag.assert(a.y == 50)
    Swag.assert(b.y == 10)

    f.capture.pushUndo(f.capture.newUndo(.AlignBottom))
    Swag.assert(a.y == 50)
    Swag.assert(b.y == 10)
    f.capture.undo()
    Swag.assert(a.y == 50)
    Swag.assert(b.y == 10)

    f.capture.pushUndo(f.capture.newUndo(.AlignMiddle))
    Swag.assert(a.y == 30)
    Swag.assert(b.y == 10)
    f.capture.undo()
    Swag.assert(a.y == 50)
    Swag.assert(b.y == 10)
}

// Arrange commands reorder forms and restore both order and selection on undo.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let a = testAddShape(f.capture, 0, 0, 10, 10)
    let b = testAddShape(f.capture, 20, 0, 10, 10)
    let c = testAddText(f.capture, 40, 0, 10, 10)

    f.capture.selection.add(0)
    f.capture.pushUndo(f.capture.newUndo(.MoveToFront))
    Swag.assert(f.capture.forms[2].buffer == a)
    Swag.assert(f.capture.selection.contains(2))
    f.capture.undo()
    Swag.assert(f.capture.forms[0].buffer == a)
    Swag.assert(f.capture.forms[1].buffer == b)
    Swag.assert(f.capture.forms[2].buffer == c)
    Swag.assert(f.capture.selection.contains(0))

    f.capture.selection.clear()
    f.capture.selection.add(2)
    f.capture.pushUndo(f.capture.newUndo(.MoveToBack))
    Swag.assert(f.capture.forms[0].buffer == c)
    Swag.assert(f.capture.selection.contains(0))
    f.capture.undo()
    Swag.assert(f.capture.forms[0].buffer == a)
    Swag.assert(f.capture.forms[1].buffer == b)
    Swag.assert(f.capture.forms[2].buffer == c)

    f.capture.selection.clear()
    f.capture.selection.add(0)
    f.capture.pushUndo(f.capture.newUndo(.MoveForward))
    Swag.assert(f.capture.forms[1].buffer == a)
    Swag.assert(f.capture.selection.contains(1))
    f.capture.undo()
    Swag.assert(f.capture.forms[0].buffer == a)

    f.capture.selection.clear()
    f.capture.selection.add(2)
    f.capture.pushUndo(f.capture.newUndo(.MoveBackward))
    Swag.assert(f.capture.forms[1].buffer == c)
    Swag.assert(f.capture.selection.contains(1))
    f.capture.undo()
    Swag.assert(f.capture.forms[2].buffer == c)
}

// Offset commands group by serial, undo/redo together and truncate redo after a new edit.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let a = testAddShape(f.capture, 10, 10, 10, 10)
    let b = testAddShape(f.capture, 30, 30, 10, 10)
    f.capture.selection.add(0)
    f.capture.selection.add(1)

    let serial = f.capture.undoMgr.newSerial()

    var u0 = f.capture.newUndo(.OffsetSelection)
    u0.newPosX = 5
    f.capture.pushUndo(u0, serial)

    var u1 = f.capture.newUndo(.OffsetSelection)
    u1.newPosY = 7
    f.capture.pushUndo(u1, serial)

    Swag.assert(a.x == 15)
    Swag.assert(a.y == 17)
    Swag.assert(b.x == 35)
    Swag.assert(b.y == 37)
    Swag.assert(f.capture.undoMgr.count() == 2)
    Swag.assert(f.capture.undoMgr.appliedCount() == 2)

    f.capture.undo()
    Swag.assert(a.x == 10)
    Swag.assert(a.y == 10)
    Swag.assert(b.x == 30)
    Swag.assert(b.y == 30)
    Swag.assert(f.capture.undoMgr.appliedCount() == 0)

    f.capture.redo()
    Swag.assert(a.x == 15)
    Swag.assert(a.y == 17)
    Swag.assert(b.x == 35)
    Swag.assert(b.y == 37)

    f.capture.undo()
    var u2 = f.capture.newUndo(.OffsetSelection)
    u2.newPosX = -2
    f.capture.pushUndo(u2)
    Swag.assert(f.capture.undoMgr.count() == 1)
    Swag.assert(a.x == 8)
    Swag.assert(b.x == 28)
}

// Create and delete selection undo records own form lifetime and selection state.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let a = testAddShape(f.capture, 0, 0, 10, 10)
    discard testAddText(f.capture, 20, 0, 10, 10)
    f.capture.selection.add(0)

    f.capture.pushUndo(f.capture.newUndo(.DeleteSelection))
    Swag.assert(f.capture.forms.count == 1)
    Swag.assert(f.capture.forms[0].buffer != a)
    Swag.assert(f.capture.selection.count == 0)

    f.capture.undo()
    Swag.assert(f.capture.forms.count == 2)
    Swag.assert(f.capture.forms[0].buffer == a)
    Swag.assert(f.capture.selection.count == 1)
    Swag.assert(f.capture.selection[0] == 0)

    f.capture.redo()
    Swag.assert(f.capture.forms.count == 1)

    let undo    = f.capture.newUndo(.CreateForm)
    let newText = Memory.new'FormText()
    newText.IForm.setup(f.capture)
    newText.IForm.setBaseForm(70, 80, 20, 25)
    undo.oldForms.add(newText)
    f.capture.pushUndo(undo)
    Swag.assert(f.capture.forms.count == 2)
    Swag.assert(Swag.kindOf(f.capture.forms[1]) == FormText)

    f.capture.undo()
    Swag.assert(f.capture.forms.count == 1)
    f.capture.redo()
    Swag.assert(f.capture.forms.count == 2)
}

// MoveBaseForm, MovePoint and MoveCapture undo records cover geometry edits beyond selection moves.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let shape = testAddShape(f.capture, 10, 20, 30, 40)
    let line  = testAddLine(f.capture, 100, 120, 150, 170)

    var moveBase = f.capture.newUndo(.MoveBaseForm)
    moveBase.baseForm = shape
    moveBase.newPosX  = 5
    moveBase.newPosY  = 6
    moveBase.newSizeX = 7
    moveBase.newSizeY = 8
    f.capture.pushUndo(moveBase)
    Gui.Testing.assertRect(shape.IForm.boundRect(), 15, 26, 37, 48)
    f.capture.undo()
    Gui.Testing.assertRect(shape.IForm.boundRect(), 10, 20, 30, 40)

    var movePoint = f.capture.newUndo(.MovePoint)
    movePoint.baseForm = line
    movePoint.pointIdx = 1
    movePoint.newPosX  = -10
    movePoint.newPosY  = 20
    f.capture.pushUndo(movePoint)
    Swag.assert(line.xb == 140)
    Swag.assert(line.yb == 190)
    f.capture.undo()
    Swag.assert(line.xb == 150)
    Swag.assert(line.yb == 170)

    var moveCapture = f.capture.newUndo(.MoveCapture)
    moveCapture.newPosX  = 11
    moveCapture.newPosY  = -9
    moveCapture.newSizeX = 5
    moveCapture.newSizeY = -6
    f.capture.pushUndo(moveCapture)
    Swag.assert(f.capture.width == 405)
    Swag.assert(f.capture.height == 294)
    Swag.assert(f.capture.backImagePos.x == 11)
    Swag.assert(f.capture.backImagePos.y == -9)
    Swag.assert(shape.x == 21)
    Swag.assert(line.xa == 111)

    f.capture.undo()
    Swag.assert(f.capture.width == 400)
    Swag.assert(f.capture.height == 300)
    Swag.assert(f.capture.backImagePos.x == 0)
    Swag.assert(f.capture.backImagePos.y == 0)
    Swag.assert(shape.x == 10)
    Swag.assert(line.xa == 100)
}

// A capture wider than Capture.MaxSize survives a trim and its undo intact. That size is
// an input bound of the resize and expand dialogs, not a property of a capture: two
// 2560-wide monitors produce a full-screen grab past it, and clamping the undo replay
// used to truncate it permanently.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    const Wide = Capture.MaxSize + 1024
    f.capture.width  = Wide
    f.capture.height = Capture.MaxSize + 512

    var trim = f.capture.newUndo(.MoveCapture)
    trim.newSizeX = -100
    trim.newSizeY = -50
    f.capture.pushUndo(trim)
    Swag.assert(f.capture.width == Wide - 100)
    Swag.assert(f.capture.height == Capture.MaxSize + 462)

    f.capture.undo()
    Swag.assert(f.capture.width == Wide)
    Swag.assert(f.capture.height == Capture.MaxSize + 512)

    f.capture.redo()
    Swag.assert(f.capture.width == Wide - 100)
    Swag.assert(f.capture.height == Capture.MaxSize + 462)
}

// Text, font, rotation and style-model undo records restore user-editable form state.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let text = testAddText(f.capture, 0, 0, 120, 60)
    text.text      = "before"
    text.fontName  = "font-a"
    text.fontStyle = .Regular
    text.rotate    = 45

    let shape = testAddShape(f.capture, 150, 0, 50, 50)
    shape.borderSize = 3
    shape.rotate     = 30

    f.capture.selection.add(0)
    var setText = f.capture.newUndo(.SetText)
    setText.text = "after"
    f.capture.pushUndo(setText)
    Swag.assert(text.text == "after")
    f.capture.undo()
    Swag.assert(text.text == "before")
    f.capture.redo()
    Swag.assert(text.text == "after")

    var setFont = f.capture.newUndo(.SetFont)
    setFont.text      = "font-b"
    setFont.fontStyle = .Bold
    f.capture.pushUndo(setFont)
    Swag.assert(text.fontName == "font-b")
    Swag.assert(text.fontStyle == .Bold)
    f.capture.undo()
    Swag.assert(text.fontName == "font-a")
    Swag.assert(text.fontStyle == .Regular)

    var setFontStyle = f.capture.newUndo(.SetFontStyle)
    setFontStyle.fontStyle = .Italic
    f.capture.pushUndo(setFontStyle)
    Swag.assert(text.fontStyle == .Italic)
    f.capture.undo()
    Swag.assert(text.fontStyle == .Regular)

    f.capture.selection.clear()
    f.capture.selection.add(0)
    f.capture.selection.add(1)
    f.capture.pushUndo(f.capture.newUndo(.ResetRotation))
    Swag.assert(text.rotate == 0)
    Swag.assert(shape.rotate == 0)
    f.capture.undo()
    Swag.assert(text.rotate == 45)
    Swag.assert(shape.rotate == 30)

    f.capture.selection.clear()
    f.capture.selection.add(1)
    let model = Memory.new'FormShape()
    model.subKind    = .None
    model.borderSize = 12
    model.backColor  = ColorBlue
    var style = f.capture.newUndo(.SetFormFromModel)
    style.mdlType  = FormShape
    style.mdlValue = model
    f.capture.pushUndo(style)
    Swag.assert(shape.borderSize == 12)
    Swag.assert(shape.backColor == ColorBlue)
    f.capture.undo()
    Swag.assert(shape.borderSize == 3)
}

// Freeze is available with a capture and toggles the frozen state, but is disabled
// and a safe no-op without one (regression: it used to assume a capture and fault).
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    let shape = testAddShape(f.capture, 10, 10, 20, 20)
    f.capture.selection.add(0)

    var evt = Gui.Testing.commandState(ActionSelection.Freeze)
    Swag.assert(Gui.Testing.actionUpdate'ActionSelection(f.main, ActionSelection.Freeze, &evt))
    Swag.assert(!evt.disabled)

    f.main.sendCommandEvent(ActionSelection.Freeze)
    Swag.assert(f.main.freezeSel)
    Swag.assert(shape.freeze)

    // Unfreeze cleanly, then drop the capture entirely.
    f.main.freezeSelection(false)
    Swag.assert(!f.main.freezeSel)

    let old = f.main.editWnd.editView.capture
    f.main.editWnd.editView.capture = null
    Memory.delete(old)

    // Without a capture the command is disabled and freezing does nothing.
    evt = Gui.Testing.commandState(ActionSelection.Freeze)
    Swag.assert(Gui.Testing.actionUpdate'ActionSelection(f.main, ActionSelection.Freeze, &evt))
    Swag.assert(evt.disabled)

    f.main.freezeSelection(true)
    Swag.assert(!f.main.freezeSel)
    Swag.assert(f.main.embInfoFreeze == null)
}

// Snap computes x/y offsets against capture bounds and neighboring form edges.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    discard testAddShape(f.capture, 20, 20, 40, 40)
    let moving = testAddShape(f.capture, 100, 100, 20, 20)
    f.capture.selection.add(1)
    f.main.snap = true

    var nx = -42
    var ny = -42
    f.capture.snap(&nx, &ny, false, false, editForm: moving)
    Swag.assert(nx == -40)
    Swag.assert(ny == -40)
    Swag.assert(f.capture.snapX == 60)
    Swag.assert(f.capture.snapY == 60)

    nx = 280
    ny = 180
    f.capture.snap(&nx, &ny, true, true, editForm: moving)
    Swag.assert(nx == 280)
    Swag.assert(ny == 180)
    Swag.assert(f.capture.snapX == 400)
    Swag.assert(f.capture.snapY == 300)

    f.main.snap = false
    nx          = -42
    ny          = -42
    f.capture.snap(&nx, &ny, false, false, editForm: moving)
    Swag.assert(nx == -42)
    Swag.assert(ny == -42)
}
