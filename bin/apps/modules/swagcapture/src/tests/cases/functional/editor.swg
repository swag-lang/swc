#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Wheel zoom preserves the image point under the pointer while the centred origin moves.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    f.capture.width  = 2000
    f.capture.height = 1200
    f.editView.setZoom(1)
    f.editView.scroll.setScrollPos(200, 150)
    let pointer = Math.Point{600, 450}
    f.gui.moveMouse(f.editView.localToSurface(pointer))
    let before = f.editView.getCaptureRect()
    let point  = (pointer + f.editView.scrollPos - Math.Point{before.x, before.y}) / f.editView.zoom

    for zoom in [2.0, 1.5, 1.0]
    {
        f.editView.setZoom(zoom, mouseCenter: true)
        let after  = f.editView.getCaptureRect()
        let actual = (pointer + f.editView.scrollPos - Math.Point{after.x, after.y}) / f.editView.zoom
        Swag.require(Math.abs(actual.x - point.x) < 1 and Math.abs(actual.y - point.y) < 1)
    }
}

// Editor drags should create forms through the real EditView/Capture mouse path.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    f.main.editMode = .Shape
    f.dragImage({20, 30}, {80, 70})

    Swag.require(f.capture.forms.count == 1)
    Swag.require(f.capture.selection.count == 1)
    Swag.require(f.capture.selection[0] == 0)
    Swag.require(f.capture.mouseMode == .None)
    Swag.require(f.gui.app.mouseCapture() == null)

    let shape = assume cast(*FormShape, f.capture.forms[0])
    Gui.Testing.assertRect(shape.IForm.boundRect(), 20, 30, 60, 40)
    Swag.require(shape.timeStart == 0 and shape.timeEnd == 0)
    Swag.require(f.capture.canUndo())
}

// The headless host mirrors modifier keys into event state, so Shift-constrained
// creation follows the same path as an interactive square/ellipse drag.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    f.main.editMode = .Shape
    f.dragImage({20, 30}, {80, 70}, modifiers: Input.KeyModifiers.Shift)

    Swag.require(f.capture.forms.count == 1)

    let shape = assume cast(*FormShape, f.capture.forms[0])
    Gui.Testing.assertRect(shape.IForm.boundRect(), 20, 30, 60, 60)
}

// Moving a selected form through mouse capture pushes undo, and the registered
// keyboard shortcuts reach MainWnd through normal command bubbling.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    let shape = testAddShape(f.capture, 10, 10, 20, 20)
    shape.kind = .Rectangle

    f.dragImage({15, 15}, {45, 35})

    Gui.Testing.assertRect(shape.IForm.boundRect(), 40, 30, 20, 20)
    Swag.require(f.capture.selection.count == 1)
    Swag.require(f.capture.selection[0] == 0)
    Swag.require(f.capture.canUndo())

    f.gui.shortcut(Input.Key.Z, Input.KeyModifiers.Control)
    Gui.Testing.assertRect(shape.IForm.boundRect(), 10, 10, 20, 20)
    Swag.require(f.capture.canRedo())

    f.gui.shortcut(Input.Key.Y, Input.KeyModifiers.Control)
    Gui.Testing.assertRect(shape.IForm.boundRect(), 40, 30, 20, 20)
}

// Selection mode lasso is an app-level interaction: mouse capture, repeated move
// events and final updateState all need to cooperate.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    discard testAddShape(f.capture, 10, 10, 20, 20)
    discard testAddShape(f.capture, 70, 70, 20, 20)
    discard testAddShape(f.capture, 180, 180, 20, 20)

    f.main.editMode = .Selection
    f.dragImage({0, 0}, {120, 120})

    Swag.require(f.capture.selection.count == 2)
    Swag.require(f.capture.selection.contains(0))
    Swag.require(f.capture.selection.contains(1))
    Swag.require(not f.capture.selection.contains(2))
    Swag.require(not f.capture.drawSelRect)
    Swag.require(f.capture.mouseMode == .None)
}

// Every editor tool that can be tested without OS integration creates the
// expected concrete form through the real mouse path.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    f.main.editMode = .Line
    f.dragImage({10, 10}, {70, 30})
    Swag.require(Swag.kindOf(f.capture.forms[0]) == FormLine)
    let line = assume cast(*FormLine, f.capture.forms[0])
    Swag.require(line.xa == 10 and line.ya == 10)
    Swag.require(line.xb == 70 and line.yb == 30)

    f.main.editMode = .Arrow
    f.dragImage({90, 10}, {150, 40})
    Swag.require(Swag.kindOf(f.capture.forms[1]) == FormArrow)

    f.main.editMode = .Text
    f.dragImage({10, 60}, {90, 95})
    Swag.require(Swag.kindOf(f.capture.forms[2]) == FormText)
    Gui.Testing.assertRect(f.capture.forms[2].boundRect(), 10, 60, 80, 35)

    f.main.editMode = .Image
    f.dragImage({110, 60}, {160, 105})
    Swag.require(Swag.kindOf(f.capture.forms[3]) == FormImage)
    Swag.require(assume cast(*FormImage, f.capture.forms[3]).isReadyToCapture)

    f.main.editMode = .Draw
    f.dragImage({10, 130}, {50, 150})
    Swag.require(Swag.kindOf(f.capture.forms[4]) == FormDraw)
    Swag.require(assume cast(*FormDraw, f.capture.forms[4]).points.count >= 2)

    f.main.mdlFormShape.subKind = .Highlight
    f.main.mdlHighlight         = &f.main.mdlFormShape
    f.main.editMode             = .Highlight
    f.dragImage({120, 130}, {170, 170})
    Swag.require(Swag.kindOf(f.capture.forms[5]) == FormShape)
    Swag.require(f.capture.forms[5].subKind == .Highlight)

    f.main.mdlFormShape.subKind = .None
    f.main.mdlPixSel = &f.main.mdlFormShape
    f.main.editMode  = .PixSel
    f.dragImage({200, 130}, {250, 170})
    Swag.require(Swag.kindOf(f.capture.forms[6]) == FormShape)
    Swag.require(f.capture.forms[6].subKind == .PixSel)

    f.main.editMode = .Step
    f.dragImage({310, 90}, {310, 90})
    Swag.require(Swag.kindOf(f.capture.forms[7]) == FormStep)
    let step = assume cast(*FormStep, f.capture.forms[7])
    Gui.Testing.assertRect(step.IForm.boundRect(), 286, 66, 48, 48)
    Swag.require(step.index == 1)
    Swag.require(f.capture.nextStepIndex == 2)
}

// Polygon creation remains captured across clicks and finishes on double-click.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    f.main.editMode = .Polygon
    f.dragImage({30, 30}, {100, 30})
    Swag.require(f.capture.mouseMode == .Creating)
    Swag.require(f.gui.app.mouseCapture() == f.editView)

    f.clickImage({100, 95})
    Swag.require(f.capture.mouseMode == .Creating)

    f.doubleClickImage({30, 95})
    Swag.require(f.capture.mouseMode == .None)
    Swag.require(f.gui.app.mouseCapture() == null)
    Swag.require(f.capture.forms.count == 1)
    Swag.require(Swag.kindOf(f.capture.forms[0]) == FormPolygon)
    Swag.require(assume cast(*FormPolygon, f.capture.forms[0]).points.count == 3)
    Swag.require(f.capture.selection.count == 1)
    Swag.require(f.capture.canUndo())
}

// Ctrl-click extends selection, a plain click replaces it, and holding O forces
// creation even over an existing form.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    discard testAddShape(f.capture, 10, 10, 40, 40)
    discard testAddShape(f.capture, 80, 10, 40, 40)
    discard testAddShape(f.capture, 150, 10, 40, 40)

    f.clickImage({30, 30})
    Swag.require(f.capture.selection.count == 1)
    Swag.require(f.capture.selection[0] == 0)

    f.clickImage({100, 30}, modifiers: Input.KeyModifiers.Control)
    Swag.require(f.capture.selection.count == 2)
    Swag.require(f.capture.selection.contains(0))
    Swag.require(f.capture.selection.contains(1))

    f.clickImage({170, 30})
    Swag.require(f.capture.selection.count == 1)
    Swag.require(f.capture.selection[0] == 2)

    f.gui.setKeyState(Input.Key.O, true)
    f.main.editMode = .Text
    f.dragImage({160, 20}, {220, 60})
    f.gui.setKeyState(Input.Key.O, false)

    Swag.require(f.capture.forms.count == 4)
    Swag.require(Swag.kindOf(f.capture.forms[3]) == FormText)
    Swag.require(f.capture.selection.count == 1)
    Swag.require(f.capture.selection[0] == 3)
}

// The edit view context menu posts real commands back to MainWnd through the
// popup/menu dispatch path.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    let shape = testAddShape(f.capture, 10, 10, 20, 20)
    discard testAddText(f.capture, 50, 10, 20, 20)
    f.capture.selection.add(0)

    f.gui.clickPopupMenuItemWhenShown(ActionSelection.DeleteSelection)

    f.clickImage({200, 200}, Input.MouseButton.Right)
    f.gui.pump()

    Swag.require(f.gui.autoHandled)
    Swag.require(f.capture.forms.count == 1)
    Swag.require(f.capture.forms[0].buffer != shape)
    Swag.require(f.capture.selection.count == 0)
    Swag.require(f.capture.canUndo())
}

// Context menu submenus are driven through real hover/timer popup behavior.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    let a = testAddShape(f.capture, 10, 30, 20, 20)
    let b = testAddShape(f.capture, 50, 70, 20, 20)
    f.capture.selection.add(0)
    f.capture.selection.add(1)

    f.gui.openPopupSubMenuWhenShown("Align")
    f.gui.thenClickPopupMenuItem(ActionAlign.AlignTop)

    f.clickImage({200, 200}, Input.MouseButton.Right)
    f.gui.pump()

    Swag.require(f.gui.autoHandled)
    Swag.require(a.y == 30)
    Swag.require(b.y == 30)
    Swag.require(f.capture.canUndo())
}

// The Arrange submenu follows the same popup path and updates z-order/selection.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    let a = testAddShape(f.capture, 10, 10, 20, 20)
    let b = testAddShape(f.capture, 50, 10, 20, 20)
    let c = testAddText(f.capture, 90, 10, 20, 20)
    f.capture.selection.add(0)

    f.gui.openPopupSubMenuWhenShown("Arrange")
    f.gui.thenClickPopupMenuItem(ActionAlign.SendToFront)

    f.clickImage({200, 200}, Input.MouseButton.Right)
    f.gui.pump()

    Swag.require(f.gui.autoHandled)
    Swag.require(f.capture.forms[0].buffer == b)
    Swag.require(f.capture.forms[1].buffer == c)
    Swag.require(f.capture.forms[2].buffer == a)
    Swag.require(f.capture.selection.count == 1)
    Swag.require(f.capture.selection[0] == 2)
    Swag.require(f.capture.canUndo())
}

// Local editor shortcuts dispatch through the focused window and command
// bubbling, without registering global hotkeys.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    testRegisterLocalEditorShortcuts(f.main)
    f.gui.focus(f.editView)

    let a = testAddShape(f.capture, 10, 10, 20, 20)
    discard testAddText(f.capture, 50, 10, 20, 20)
    discard testAddShape(f.capture, 90, 10, 20, 20)

    f.gui.shortcut(Input.Key.A, Input.KeyModifiers.Control)
    Swag.require(f.capture.selection.count == 3)

    f.gui.shortcut(Input.Key.Escape, Input.KeyModifiers.None)
    Swag.require(f.capture.selection.count == 0)

    f.capture.selection.add(0)
    f.gui.shortcut(Input.Key.Right, Input.KeyModifiers.None)
    Swag.require(a.x == 11)
    Swag.require(f.capture.canUndo())

    f.gui.shortcut(Input.Key.Z, Input.KeyModifiers.Control)
    Swag.require(a.x == 10)
    f.gui.shortcut(Input.Key.Y, Input.KeyModifiers.Control)
    Swag.require(a.x == 11)

    f.gui.shortcut(Input.Key.Delete, Input.KeyModifiers.None)
    Swag.require(f.capture.forms.count == 2)
    f.gui.shortcut(Input.Key.Z, Input.KeyModifiers.Control)
    Swag.require(f.capture.forms.count == 3)

    testRegisterIoActions(f.main)
    f.capture.selection.clear()
    f.capture.selection.add(0)
    f.gui.shortcut(Input.Key.D, Input.KeyModifiers.Control)
    Swag.require(f.capture.forms.count == 4)
}

// Registered headless shortcuts travel through the focused window and global
// command lookup, not only through direct command ids.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    f.gui.focus(f.editView)

    let a = testAddShape(f.capture, 10, 10, 20, 20)
    discard testAddText(f.capture, 50, 10, 20, 20)
    f.capture.selection.add(0)

    f.gui.shortcut(Input.Key.Left, Input.KeyModifiers.None)
    Swag.require(a.x == 9)

    f.gui.shortcut(Input.Key.Down, Input.KeyModifiers.Shift)
    Swag.require(a.y == 10 + NudgeFar)

    f.gui.shortcut(Input.Key.PageUp, Input.KeyModifiers.None)
    Swag.require(f.capture.forms[1].buffer == a)
    Swag.require(f.capture.selection.count == 1)
    Swag.require(f.capture.selection[0] == 1)

    f.gui.shortcut(Input.Key.Space, Input.KeyModifiers.Control)
    Swag.require(f.main.lens.isOpen() and not f.main.freezeSel)
    f.main.lens.close()

    f.editView.setZoom(1)
    f.gui.shortcut(Input.Key.Add, Input.KeyModifiers.Control)
    Swag.require(f.editView.zoom > 1)
}

// Box-form gizmos resize and rotate through real headless mouse events.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let shape = testAddShape(f.capture, 20, 30, 40, 30)
    shape.kind = .Rectangle
    f.capture.selection.add(0)
    testPrimeGizmo(shape)

    f.dragImage({60, 60}, {85, 80})
    Gui.Testing.assertRect(shape.IForm.boundRect(), 20, 30, 65, 50)
    Swag.require(f.capture.canUndo())

    f.capture.undo()
    Gui.Testing.assertRect(shape.IForm.boundRect(), 20, 30, 40, 30)

    testPrimeGizmo(shape)
    f.dragImage({40, 4}, {95, 45}, modifiers: Input.KeyModifiers.Shift)
    Swag.require(Math.abs(shape.rotate - 90) < 0.001)
    f.capture.undo()
    Swag.require(Math.abs(shape.rotate) < 0.001)
}

// A free image can be switched into inside-edit mode by double-clicking, then
// its inner placement rectangle is resized through the same gizmo event path.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let image = testAddImage(f.capture, 40, 50, 80, 60)
    image.kind    = .Image
    image.place   = .Free
    image.image   = Image.create(20, 20, .BGRA8)
    image.freePos = {5, 6, 20, 16}
    f.capture.selection.add(0)

    Swag.require(image.IForm.canRotate())
    f.doubleClickImage({60, 70})
    Swag.require(image.editInside)
    Swag.require(not image.IForm.canRotate())

    testPrimeGizmo(image)
    f.dragImage({65, 72}, {75, 82})

    Gui.Testing.assertRect(image.freePos, 5, 6, 30, 26)
    Swag.require(f.capture.canUndo())

    f.capture.undo()
    Gui.Testing.assertRect(image.freePos, 5, 6, 20, 16)

    f.doubleClickImage({60, 70})
    Swag.require(not image.editInside)
}

// Point-form gizmos move line endpoints through Capture.mouse and create a
// normal undo record.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let line = testAddLine(f.capture, 20, 30, 70, 45)
    f.capture.selection.add(0)
    testPrimeGizmo(line)

    f.dragImage({70, 45}, {95, 80})
    Swag.require(line.xb == 95)
    Swag.require(line.yb == 80)
    Swag.require(f.capture.canUndo())

    f.capture.undo()
    Swag.require(line.xb == 70)
    Swag.require(line.yb == 45)
}

// The capture bounding gizmo resizes the canvas itself without needing a real
// paint pass or OS capture.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    testPrimeCaptureGizmo(f.capture)
    f.dragImage({400, 300}, {430, 320})

    Swag.require(f.capture.width == 430)
    Swag.require(f.capture.height == 320)
    Swag.require(f.capture.canUndo())

    f.capture.undo()
    Swag.require(f.capture.width == 400)
    Swag.require(f.capture.height == 300)
}

// The swatch of the mini-bar stands for the colour a form is seen by: the fill of a filled
// shape, the outline of an outlined one.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    let shape = testAddShape(f.capture, 20, 20, 80, 60)
    shape.backColor   = Argb.Zero
    shape.borderColor = Argb.Red
    f.capture.selection.add(0)
    Swag.require(f.main.miniBarColorField().name == #nameof(BaseForm.borderColor))
    Swag.require(f.main.miniBarColor() == Argb.Red)

    shape.backColor = Argb.Blue
    Swag.require(f.main.miniBarColorField().name == #nameof(BaseForm.backColor))
    Swag.require(f.main.miniBarColor() == Argb.Blue)
}

// The handles that resize the picture come out only near its edges, inside or out, and leave
// the picture alone elsewhere: at rest the only handles on screen are those of the selection.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    f.editView.setZoom(1)
    Swag.require(not f.editView.showsCaptureHandles())

    func moveTo(f: *HeadlessFixture, scrolled: Math.Point)
    {
        f.gui.moveMouse(f.editView.localToSurface(scrolled - f.editView.scrollPos))
    }

    let picture = f.editView.getCaptureRect()
    moveTo(&f, Math.Point{picture.horzCenter(), picture.vertCenter()})
    Swag.require(not f.editView.showsCaptureHandles())

    // Just inside the right edge, and just outside the bottom one.
    moveTo(&f, Math.Point{picture.right() - 6, picture.vertCenter()})
    Swag.require(f.editView.showsCaptureHandles())
    moveTo(&f, Math.Point{picture.horzCenter(), picture.bottom() + 10})
    Swag.require(f.editView.showsCaptureHandles())

    // Back in its middle, they go again.
    moveTo(&f, Math.Point{picture.horzCenter(), picture.vertCenter()})
    Swag.require(not f.editView.showsCaptureHandles())
}
