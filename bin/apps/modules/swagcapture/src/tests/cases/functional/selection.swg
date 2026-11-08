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
    Swag.require(f.capture.selection.count == 3)

    f.capture.selection.clear()
    f.capture.selection.add(0)
    f.main.sendCommandEvent(ActionSelection.SelectSameAll)
    Swag.require(f.capture.selection.count == 2)
    Swag.require(f.capture.selection.contains(0))
    Swag.require(f.capture.selection.contains(2))

    f.main.sendCommandEvent(ActionSelection.InvertSelection)
    Swag.require(f.capture.selection.count == 1)
    Swag.require(f.capture.selection[0] == 1)

    f.main.sendCommandEvent(ActionSelection.DeSelectAll)
    Swag.require(f.capture.selection.count == 0)

    let snap = f.main.snap
    f.main.sendCommandEvent(ActionSelection.Snap)
    Swag.require(f.main.snap != snap)
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
    Swag.require(a.x == 20)
    Swag.require(b.x == 20)
    f.capture.undo()
    Swag.require(a.x == 20)
    Swag.require(b.x == 80)

    f.capture.pushUndo(f.capture.newUndo(.AlignRight))
    Swag.require(a.x == 100)
    Swag.require(b.x == 80)
    f.capture.undo()
    Swag.require(a.x == 20)
    Swag.require(b.x == 80)

    f.capture.pushUndo(f.capture.newUndo(.AlignCenter))
    Swag.require(a.x == 60)
    Swag.require(b.x == 50)
    f.capture.undo()
    Swag.require(a.x == 20)
    Swag.require(b.x == 80)

    f.capture.pushUndo(f.capture.newUndo(.AlignTop))
    Swag.require(a.y == 10)
    Swag.require(b.y == 10)
    f.capture.undo()
    Swag.require(a.y == 50)
    Swag.require(b.y == 10)

    f.capture.pushUndo(f.capture.newUndo(.AlignBottom))
    Swag.require(a.y == 50)
    Swag.require(b.y == 10)
    f.capture.undo()
    Swag.require(a.y == 50)
    Swag.require(b.y == 10)

    f.capture.pushUndo(f.capture.newUndo(.AlignMiddle))
    Swag.require(a.y == 30)
    Swag.require(b.y == 10)
    f.capture.undo()
    Swag.require(a.y == 50)
    Swag.require(b.y == 10)
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
    Swag.require(f.capture.forms[2].buffer == a)
    Swag.require(f.capture.selection.contains(2))
    f.capture.undo()
    Swag.require(f.capture.forms[0].buffer == a)
    Swag.require(f.capture.forms[1].buffer == b)
    Swag.require(f.capture.forms[2].buffer == c)
    Swag.require(f.capture.selection.contains(0))

    f.capture.selection.clear()
    f.capture.selection.add(2)
    f.capture.pushUndo(f.capture.newUndo(.MoveToBack))
    Swag.require(f.capture.forms[0].buffer == c)
    Swag.require(f.capture.selection.contains(0))
    f.capture.undo()
    Swag.require(f.capture.forms[0].buffer == a)
    Swag.require(f.capture.forms[1].buffer == b)
    Swag.require(f.capture.forms[2].buffer == c)

    f.capture.selection.clear()
    f.capture.selection.add(0)
    f.capture.pushUndo(f.capture.newUndo(.MoveForward))
    Swag.require(f.capture.forms[1].buffer == a)
    Swag.require(f.capture.selection.contains(1))
    f.capture.undo()
    Swag.require(f.capture.forms[0].buffer == a)

    f.capture.selection.clear()
    f.capture.selection.add(2)
    f.capture.pushUndo(f.capture.newUndo(.MoveBackward))
    Swag.require(f.capture.forms[1].buffer == c)
    Swag.require(f.capture.selection.contains(1))
    f.capture.undo()
    Swag.require(f.capture.forms[2].buffer == c)
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

    Swag.require(a.x == 15)
    Swag.require(a.y == 17)
    Swag.require(b.x == 35)
    Swag.require(b.y == 37)
    Swag.require(f.capture.undoMgr.count() == 2)
    Swag.require(f.capture.undoMgr.appliedCount() == 2)

    f.capture.undo()
    Swag.require(a.x == 10)
    Swag.require(a.y == 10)
    Swag.require(b.x == 30)
    Swag.require(b.y == 30)
    Swag.require(f.capture.undoMgr.appliedCount() == 0)

    f.capture.redo()
    Swag.require(a.x == 15)
    Swag.require(a.y == 17)
    Swag.require(b.x == 35)
    Swag.require(b.y == 37)

    f.capture.undo()
    var u2 = f.capture.newUndo(.OffsetSelection)
    u2.newPosX = -2
    f.capture.pushUndo(u2)
    Swag.require(f.capture.undoMgr.count() == 1)
    Swag.require(a.x == 8)
    Swag.require(b.x == 28)
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
    Swag.require(f.capture.forms.count == 1)
    Swag.require(f.capture.forms[0].buffer != a)
    Swag.require(f.capture.selection.count == 0)

    f.capture.undo()
    Swag.require(f.capture.forms.count == 2)
    Swag.require(f.capture.forms[0].buffer == a)
    Swag.require(f.capture.selection.count == 1)
    Swag.require(f.capture.selection[0] == 0)

    f.capture.redo()
    Swag.require(f.capture.forms.count == 1)

    let undo = f.capture.newUndo(.CreateForm)

    with let newText = Memory.new'FormText()
    {
        .IForm.setup(f.capture)
        .IForm.setBaseForm(70, 80, 20, 25)
    }

    undo.oldForms.add(newText)
    f.capture.pushUndo(undo)
    Swag.require(f.capture.forms.count == 2)
    Swag.require(Swag.kindOf(f.capture.forms[1]) == FormText)

    f.capture.undo()
    Swag.require(f.capture.forms.count == 1)
    f.capture.redo()
    Swag.require(f.capture.forms.count == 2)
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
    Swag.require(line.xb == 140)
    Swag.require(line.yb == 190)
    f.capture.undo()
    Swag.require(line.xb == 150)
    Swag.require(line.yb == 170)

    var moveCapture = f.capture.newUndo(.MoveCapture)
    moveCapture.newPosX  = 11
    moveCapture.newPosY  = -9
    moveCapture.newSizeX = 5
    moveCapture.newSizeY = -6
    f.capture.pushUndo(moveCapture)
    Swag.require(f.capture.width == 405)
    Swag.require(f.capture.height == 294)
    Swag.require(f.capture.backImagePos.x == 11)
    Swag.require(f.capture.backImagePos.y == -9)
    Swag.require(shape.x == 21)
    Swag.require(line.xa == 111)

    f.capture.undo()
    Swag.require(f.capture.width == 400)
    Swag.require(f.capture.height == 300)
    Swag.require(f.capture.backImagePos.x == 0)
    Swag.require(f.capture.backImagePos.y == 0)
    Swag.require(shape.x == 10)
    Swag.require(line.xa == 100)
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
    Swag.require(f.capture.width == Wide - 100)
    Swag.require(f.capture.height == Capture.MaxSize + 462)

    f.capture.undo()
    Swag.require(f.capture.width == Wide)
    Swag.require(f.capture.height == Capture.MaxSize + 512)

    f.capture.redo()
    Swag.require(f.capture.width == Wide - 100)
    Swag.require(f.capture.height == Capture.MaxSize + 462)
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

    with let shape = testAddShape(f.capture, 150, 0, 50, 50)
    {
        .borderSize = 3
        .rotate     = 30
    }

    f.capture.selection.add(0)
    var setText = f.capture.newUndo(.SetText)
    setText.text = "after"
    f.capture.pushUndo(setText)
    Swag.require(text.text == "after")
    f.capture.undo()
    Swag.require(text.text == "before")
    f.capture.redo()
    Swag.require(text.text == "after")

    var setFont = f.capture.newUndo(.SetFont)
    setFont.text      = "font-b"
    setFont.fontStyle = .Bold
    f.capture.pushUndo(setFont)
    Swag.require(text.fontName == "font-b")
    Swag.require(text.fontStyle == .Bold)
    f.capture.undo()
    Swag.require(text.fontName == "font-a")
    Swag.require(text.fontStyle == .Regular)

    var setFontStyle = f.capture.newUndo(.SetFontStyle)
    setFontStyle.fontStyle = .Italic
    f.capture.pushUndo(setFontStyle)
    Swag.require(text.fontStyle == .Italic)
    f.capture.undo()
    Swag.require(text.fontStyle == .Regular)

    f.capture.selection.clear()
    f.capture.selection.add(0)
    f.capture.selection.add(1)
    f.capture.pushUndo(f.capture.newUndo(.ResetRotation))
    Swag.require(text.rotate == 0)
    Swag.require(shape.rotate == 0)
    f.capture.undo()
    Swag.require(text.rotate == 45)
    Swag.require(shape.rotate == 30)

    f.capture.selection.clear()
    f.capture.selection.add(1)
    with let model = Memory.new'FormShape()
    {
        .subKind    = .None
        .borderSize = 12
        .backColor  = ColorBlue
    }

    var style = f.capture.newUndo(.SetFormFromModel)
    style.mdlType  = FormShape
    style.mdlValue = model
    f.capture.pushUndo(style)
    Swag.require(shape.borderSize == 12)
    Swag.require(shape.backColor == ColorBlue)
    f.capture.undo()
    Swag.require(shape.borderSize == 3)
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
    Swag.require(Gui.Testing.actionUpdate'ActionSelection(f.main, ActionSelection.Freeze, &evt))
    Swag.require(not evt.disabled)

    f.main.sendCommandEvent(ActionSelection.Freeze)
    Swag.require(f.main.freezeSel)
    Swag.require(shape.freeze)

    // Unfreeze cleanly, then drop the capture entirely.
    f.main.freezeSelection(false)
    Swag.require(not f.main.freezeSel)

    let old = f.main.editWnd.editView.capture
    f.main.editWnd.editView.capture = null
    Memory.delete(old)

    // Without a capture the command is disabled and freezing does nothing.
    evt = Gui.Testing.commandState(ActionSelection.Freeze)
    Swag.require(Gui.Testing.actionUpdate'ActionSelection(f.main, ActionSelection.Freeze, &evt))
    Swag.require(evt.disabled)

    f.main.freezeSelection(true)
    Swag.require(not f.main.freezeSel)
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
    Swag.require(nx == -40)
    Swag.require(ny == -40)
    Swag.require(f.capture.snapX == 60)
    Swag.require(f.capture.snapY == 60)

    nx = 280
    ny = 180
    f.capture.snap(&nx, &ny, true, true, editForm: moving)
    Swag.require(nx == 280)
    Swag.require(ny == 180)
    Swag.require(f.capture.snapX == 400)
    Swag.require(f.capture.snapY == 300)

    f.main.snap = false
    nx = -42
    ny = -42
    f.capture.snap(&nx, &ny, false, false, editForm: moving)
    Swag.require(nx == -42)
    Swag.require(ny == -42)
}
