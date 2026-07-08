#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Editor drags should create forms through the real EditView/Capture mouse path.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    f.main.editMode = .Shape
    f.gui.drag({20, 30}, {80, 70})

    @assert(f.capture.forms.count == 1)
    @assert(f.capture.selection.count == 1)
    @assert(f.capture.selection[0] == 0)
    @assert(f.capture.mouseMode == .None)
    @assert(f.gui.app.mouseCaptureWnd == null)

    let shape = cast(*FormShape) @dataof(f.capture.forms[0])
    Testing.assertRect(shape.IForm.boundRect(), 20, 30, 60, 40)
    @assert(f.capture.canUndo())

    f.shutdown()
}

// The headless host mirrors modifier keys into event state, so Shift-constrained
// creation follows the same path as an interactive square/ellipse drag.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    f.main.editMode = .Shape
    f.gui.drag({20, 30}, {80, 70}, modifiers: Input.KeyModifiers.Shift)

    @assert(f.capture.forms.count == 1)

    let shape = cast(*FormShape) @dataof(f.capture.forms[0])
    Testing.assertRect(shape.IForm.boundRect(), 20, 30, 60, 60)

    f.shutdown()
}

// Moving a selected form through mouse capture pushes undo, and the registered
// keyboard shortcuts reach MainWnd through normal command bubbling.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup(registerHeadlessCommands: true)

    let shape = captmeTestAddShape(f.capture, 10, 10, 20, 20)
    shape.kind = .Rectangle

    f.gui.drag({15, 15}, {45, 35})

    Testing.assertRect(shape.IForm.boundRect(), 40, 30, 20, 20)
    @assert(f.capture.selection.count == 1)
    @assert(f.capture.selection[0] == 0)
    @assert(f.capture.canUndo())

    f.gui.shortcut(Input.Key.Z, Input.KeyModifiers.Control)
    Testing.assertRect(shape.IForm.boundRect(), 10, 10, 20, 20)
    @assert(f.capture.canRedo())

    f.gui.shortcut(Input.Key.Y, Input.KeyModifiers.Control)
    Testing.assertRect(shape.IForm.boundRect(), 40, 30, 20, 20)

    f.shutdown()
}

// Selection mode lasso is an app-level interaction: mouse capture, repeated move
// events and final updateState all need to cooperate.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    discard captmeTestAddShape(f.capture, 10, 10, 20, 20)
    discard captmeTestAddShape(f.capture, 70, 70, 20, 20)
    discard captmeTestAddShape(f.capture, 180, 180, 20, 20)

    f.main.editMode = .Selection
    f.gui.drag({0, 0}, {120, 120})

    @assert(f.capture.selection.count == 2)
    @assert(f.capture.selection.contains(0))
    @assert(f.capture.selection.contains(1))
    @assert(!f.capture.selection.contains(2))
    @assert(!f.capture.drawSelRect)
    @assert(f.capture.mouseMode == .None)

    f.shutdown()
}

// Every editor tool that can be tested without OS integration creates the
// expected concrete form through the real mouse path.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    f.main.editMode = .Line
    f.gui.drag({10, 10}, {70, 30})
    @assert(@kindof(f.capture.forms[0]) == FormLine)
    let line = cast(*FormLine) @dataof(f.capture.forms[0])
    @assert(line.xa == 10 and line.ya == 10)
    @assert(line.xb == 70 and line.yb == 30)

    f.main.editMode = .Arrow
    f.gui.drag({90, 10}, {150, 40})
    @assert(@kindof(f.capture.forms[1]) == FormArrow)

    f.main.editMode = .Text
    f.gui.drag({10, 60}, {90, 95})
    @assert(@kindof(f.capture.forms[2]) == FormText)
    Testing.assertRect(f.capture.forms[2].boundRect(), 10, 60, 80, 35)

    f.main.editMode = .Image
    f.gui.drag({110, 60}, {160, 105})
    @assert(@kindof(f.capture.forms[3]) == FormImage)
    @assert((cast(*FormImage) @dataof(f.capture.forms[3])).isReadyToCapture)

    f.main.editMode = .Draw
    f.gui.drag({10, 130}, {50, 150})
    @assert(@kindof(f.capture.forms[4]) == FormDraw)
    @assert((cast(*FormDraw) @dataof(f.capture.forms[4])).points.count >= 2)

    f.main.mdlFormShape.subKind = .Highlight
    f.main.mdlHighlight = &f.main.mdlFormShape
    f.main.editMode = .Highlight
    f.gui.drag({120, 130}, {170, 170})
    @assert(@kindof(f.capture.forms[5]) == FormShape)
    @assert((cast(*BaseForm) @dataof(f.capture.forms[5])).subKind == .Highlight)

    f.main.mdlFormShape.subKind = .None
    f.main.mdlPixSel = &f.main.mdlFormShape
    f.main.editMode = .PixSel
    f.gui.drag({200, 130}, {250, 170})
    @assert(@kindof(f.capture.forms[6]) == FormShape)
    @assert((cast(*BaseForm) @dataof(f.capture.forms[6])).subKind == .PixSel)

    f.main.editMode = .Step
    f.gui.drag({310, 90}, {310, 90})
    @assert(@kindof(f.capture.forms[7]) == FormStep)
    let step = cast(*FormStep) @dataof(f.capture.forms[7])
    Testing.assertRect(step.IForm.boundRect(), 286, 66, 48, 48)
    @assert(step.index == 1)
    @assert(f.capture.nextStepIndex == 2)

    f.shutdown()
}

// Polygon creation remains captured across clicks and finishes on double-click.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    f.main.editMode = .Polygon
    f.gui.drag({30, 30}, {100, 30})
    @assert(f.capture.mouseMode == .Creating)
    @assert(f.gui.app.mouseCaptureWnd == f.editView)

    f.gui.click({100, 95})
    @assert(f.capture.mouseMode == .Creating)

    f.gui.doubleClick({30, 95})
    @assert(f.capture.mouseMode == .None)
    @assert(f.gui.app.mouseCaptureWnd == null)
    @assert(f.capture.forms.count == 1)
    @assert(@kindof(f.capture.forms[0]) == FormPolygon)
    @assert((cast(*FormPolygon) @dataof(f.capture.forms[0])).points.count == 3)
    @assert(f.capture.selection.count == 1)
    @assert(f.capture.canUndo())

    f.shutdown()
}

// Ctrl-click extends selection, a plain click replaces it, and holding O forces
// creation even over an existing form.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    discard captmeTestAddShape(f.capture, 10, 10, 40, 40)
    discard captmeTestAddShape(f.capture, 80, 10, 40, 40)
    discard captmeTestAddShape(f.capture, 150, 10, 40, 40)

    f.gui.click({30, 30})
    @assert(f.capture.selection.count == 1)
    @assert(f.capture.selection[0] == 0)

    f.gui.click({100, 30}, modifiers: Input.KeyModifiers.Control)
    @assert(f.capture.selection.count == 2)
    @assert(f.capture.selection.contains(0))
    @assert(f.capture.selection.contains(1))

    f.gui.click({170, 30})
    @assert(f.capture.selection.count == 1)
    @assert(f.capture.selection[0] == 2)

    f.gui.setKeyState(Input.Key.O, true)
    f.main.editMode = .Text
    f.gui.drag({160, 20}, {220, 60})
    f.gui.setKeyState(Input.Key.O, false)

    @assert(f.capture.forms.count == 4)
    @assert(@kindof(f.capture.forms[3]) == FormText)
    @assert(f.capture.selection.count == 1)
    @assert(f.capture.selection[0] == 3)

    f.shutdown()
}

// The edit view context menu posts real commands back to MainWnd through the
// popup/menu dispatch path.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup(registerHeadlessCommands: true)

    let shape = captmeTestAddShape(f.capture, 10, 10, 20, 20)
    discard captmeTestAddText(f.capture, 50, 10, 20, 20)
    f.capture.selection.add(0)

    f.gui.clickPopupMenuItemWhenShown(ActionSelection.DeleteSelection)

    f.gui.click({200, 200}, Input.MouseButton.Right)
    f.gui.pump()

    @assert(f.gui.autoHandled)
    @assert(f.capture.forms.count == 1)
    @assert(@dataof(f.capture.forms[0]) != shape)
    @assert(f.capture.selection.count == 0)
    @assert(f.capture.canUndo())

    f.shutdown()
}

// Context menu submenus are driven through real hover/timer popup behavior.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup(registerHeadlessCommands: true)

    let a = captmeTestAddShape(f.capture, 10, 30, 20, 20)
    let b = captmeTestAddShape(f.capture, 50, 70, 20, 20)
    f.capture.selection.add(0)
    f.capture.selection.add(1)

    f.gui.openPopupSubMenuWhenShown("Align")
    f.gui.thenClickPopupMenuItem(ActionAlign.AlignTop)

    f.gui.click({200, 200}, Input.MouseButton.Right)
    f.gui.pump()

    @assert(f.gui.autoHandled)
    @assert(a.y == 30)
    @assert(b.y == 30)
    @assert(f.capture.canUndo())

    f.shutdown()
}

// The Arrange submenu follows the same popup path and updates z-order/selection.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup(registerHeadlessCommands: true)

    let a = captmeTestAddShape(f.capture, 10, 10, 20, 20)
    let b = captmeTestAddShape(f.capture, 50, 10, 20, 20)
    let c = captmeTestAddText(f.capture, 90, 10, 20, 20)
    f.capture.selection.add(0)

    f.gui.openPopupSubMenuWhenShown("Arrange")
    f.gui.thenClickPopupMenuItem(ActionAlign.SendToFront)

    f.gui.click({200, 200}, Input.MouseButton.Right)
    f.gui.pump()

    @assert(f.gui.autoHandled)
    @assert(@dataof(f.capture.forms[0]) == b)
    @assert(@dataof(f.capture.forms[1]) == c)
    @assert(@dataof(f.capture.forms[2]) == a)
    @assert(f.capture.selection.count == 1)
    @assert(f.capture.selection[0] == 2)
    @assert(f.capture.canUndo())

    f.shutdown()
}

// Local editor shortcuts dispatch through the focused window and command
// bubbling, without registering global hotkeys.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()
    captmeTestRegisterLocalEditorShortcuts(f.main)
    f.gui.focus(f.editView)

    let a = captmeTestAddShape(f.capture, 10, 10, 20, 20)
    discard captmeTestAddText(f.capture, 50, 10, 20, 20)
    discard captmeTestAddShape(f.capture, 90, 10, 20, 20)

    f.gui.shortcut(Input.Key.A, Input.KeyModifiers.Control)
    @assert(f.capture.selection.count == 3)

    f.gui.shortcut(Input.Key.D, Input.KeyModifiers.Control)
    @assert(f.capture.selection.count == 0)

    f.capture.selection.add(0)
    f.gui.shortcut(Input.Key.Right, Input.KeyModifiers.Shift)
    @assert(a.x == 11)
    @assert(f.capture.canUndo())

    f.gui.shortcut(Input.Key.Z, Input.KeyModifiers.Control)
    @assert(a.x == 10)
    f.gui.shortcut(Input.Key.Y, Input.KeyModifiers.Control)
    @assert(a.x == 11)

    f.gui.shortcut(Input.Key.Delete, Input.KeyModifiers.Zero)
    @assert(f.capture.forms.count == 2)
    f.gui.shortcut(Input.Key.Z, Input.KeyModifiers.Control)
    @assert(f.capture.forms.count == 3)

    f.shutdown()
}

// Registered headless shortcuts travel through the focused window and global
// command lookup, not only through direct command ids.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup(registerHeadlessCommands: true)
    f.gui.focus(f.editView)

    let a = captmeTestAddShape(f.capture, 10, 10, 20, 20)
    discard captmeTestAddText(f.capture, 50, 10, 20, 20)
    f.capture.selection.add(0)

    f.gui.shortcut(Input.Key.Left, Input.KeyModifiers.Zero)
    @assert(a.x == 5)

    f.gui.shortcut(Input.Key.Down, Input.KeyModifiers.Shift)
    @assert(a.y == 11)

    f.gui.shortcut(Input.Key.PageUp, Input.KeyModifiers.Zero)
    @assert(@dataof(f.capture.forms[1]) == a)
    @assert(f.capture.selection.count == 1)
    @assert(f.capture.selection[0] == 1)

    f.gui.shortcut(Input.Key.Space, Input.KeyModifiers.Control)
    @assert(f.main.freezeSel)

    f.editView.setZoom(1)
    f.gui.shortcut(Input.Key.Add, Input.KeyModifiers.Control)
    @assert(f.editView.zoom > 1)

    f.shutdown()
}

// Box-form gizmos resize and rotate through real headless mouse events.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    let shape = captmeTestAddShape(f.capture, 20, 30, 40, 30)
    shape.kind = .Rectangle
    f.capture.selection.add(0)
    captmeTestPrimeGizmo(cast(IForm) shape)

    f.gui.drag({60, 60}, {85, 80})
    Testing.assertRect(shape.IForm.boundRect(), 20, 30, 65, 50)
    @assert(f.capture.canUndo())

    f.capture.undo()
    Testing.assertRect(shape.IForm.boundRect(), 20, 30, 40, 30)

    captmeTestPrimeGizmo(cast(IForm) shape)
    f.gui.drag({40, 4}, {95, 45}, modifiers: Input.KeyModifiers.Shift)
    @assert(Math.abs(shape.rotate - 90) < 0.001)
    f.capture.undo()
    @assert(Math.abs(shape.rotate) < 0.001)

    f.shutdown()
}

// A free image can be switched into inside-edit mode by double-clicking, then
// its inner placement rectangle is resized through the same gizmo event path.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    let image = captmeTestAddImage(f.capture, 40, 50, 80, 60)
    image.kind = .Image
    image.place = .Free
    image.image = Image.create(20, 20, .BGRA8)
    image.freePos = {5, 6, 20, 16}
    f.capture.selection.add(0)

    @assert(image.IForm.canRotate())
    f.gui.doubleClick({60, 70})
    @assert(image.editInside)
    @assert(!image.IForm.canRotate())

    captmeTestPrimeGizmo(cast(IForm) image)
    f.gui.drag({65, 72}, {75, 82})

    Testing.assertRect(image.freePos, 5, 6, 30, 26)
    @assert(f.capture.canUndo())

    f.capture.undo()
    Testing.assertRect(image.freePos, 5, 6, 20, 16)

    f.gui.doubleClick({60, 70})
    @assert(!image.editInside)

    f.shutdown()
}

// Point-form gizmos move line endpoints through Capture.mouse and create a
// normal undo record.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    let line = captmeTestAddLine(f.capture, 20, 30, 70, 45)
    f.capture.selection.add(0)
    captmeTestPrimeGizmo(cast(IForm) line)

    f.gui.drag({70, 45}, {95, 80})
    @assert(line.xb == 95)
    @assert(line.yb == 80)
    @assert(f.capture.canUndo())

    f.capture.undo()
    @assert(line.xb == 70)
    @assert(line.yb == 45)

    f.shutdown()
}

// The capture bounding gizmo resizes the canvas itself without needing a real
// paint pass or OS capture.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    captmeTestPrimeCaptureGizmo(f.capture)
    f.gui.drag({400, 300}, {430, 320})

    @assert(f.capture.width == 430)
    @assert(f.capture.height == 320)
    @assert(f.capture.canUndo())

    f.capture.undo()
    @assert(f.capture.width == 400)
    @assert(f.capture.height == 300)

    f.shutdown()
}
