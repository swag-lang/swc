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
    captmeTestAssertRect(shape.IForm.boundRect(), 20, 30, 60, 40)
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
    captmeTestAssertRect(shape.IForm.boundRect(), 20, 30, 60, 60)

    f.shutdown()
}

// Moving a selected form through mouse capture pushes undo, and the registered
// keyboard shortcuts reach MainWnd through normal command bubbling.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    f.main.registerAction'ActionUndo()
    f.main.registerKeyShortcut(Input.KeyModifiers.Control, Input.Key.Z, ActionUndo.DoUndo)
    f.main.registerKeyShortcut(Input.KeyModifiers.Control, Input.Key.Y, ActionUndo.DoRedo)

    let shape = captmeTestAddShape(f.capture, 10, 10, 20, 20)
    shape.kind = .Rectangle

    f.gui.drag({15, 15}, {45, 35})

    captmeTestAssertRect(shape.IForm.boundRect(), 40, 30, 20, 20)
    @assert(f.capture.selection.count == 1)
    @assert(f.capture.selection[0] == 0)
    @assert(f.capture.canUndo())

    f.gui.shortcut(Input.Key.Z, Input.KeyModifiers.Control)
    captmeTestAssertRect(shape.IForm.boundRect(), 10, 10, 20, 20)
    @assert(f.capture.canRedo())

    f.gui.shortcut(Input.Key.Y, Input.KeyModifiers.Control)
    captmeTestAssertRect(shape.IForm.boundRect(), 40, 30, 20, 20)

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
