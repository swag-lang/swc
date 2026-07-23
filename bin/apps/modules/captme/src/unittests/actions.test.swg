#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// accept() is generated from the newCmdId scope prefix (see acceptOwnCmdIds): an
// action must accept its own ids and reject those of every other action.
#test
{
    @assert(Testing.actionAccept'ActionSelection(null, ActionSelection.SelectAll))
    @assert(Testing.actionAccept'ActionSelection(null, ActionSelection.Freeze))
    @assert(!Testing.actionAccept'ActionSelection(null, ActionCapture.Area))
    @assert(!Testing.actionAccept'ActionSelection(null, ActionZoom.ZoomFit))
}

// The headless fixture can register safe commands and drive them through the
// same command dispatch path as menus, buttons and shortcuts.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)

    discard testAddShape(f.capture, 10, 10, 20, 20)
    discard testAddText(f.capture, 50, 10, 20, 20)

    f.main.sendCommandEvent(ActionSelection.SelectAll)
    @assert(f.capture.selection.count == 2)

    f.main.sendCommandEvent(ActionSelection.DeSelectAll)
    @assert(f.capture.selection.count == 0)

    f.main.sendCommandEvent(ActionSelection.DeleteSelection)
    @assert(f.capture.forms.count == 2)
    @assert(!f.capture.canUndo())

    f.capture.selection.add(0)
    f.main.sendCommandEvent(ActionSelection.DeleteSelection)
    @assert(f.capture.forms.count == 1)
    @assert(f.capture.selection.count == 0)
    @assert(f.capture.canUndo())

    f.main.sendCommandEvent(ActionToolMode.Text)
    @assert(f.main.editMode == .Text)

    f.main.sendCommandEvent(ActionView.Clip)
    @assert(f.main.editorOptions.clipToSelection)

    f.main.sendCommandEvent(ActionSelection.Freeze)
    @assert(f.main.freezeSel)
    @assert(f.main.embInfoFreeze != null)
    f.main.sendCommandEvent(ActionSelection.Freeze)
    @assert(!f.main.freezeSel)
    @assert(f.main.embInfoFreeze == null)

    f.shutdown()
}

// Tool-mode actions update checked state and switch every safe editor mode.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)

    f.main.sendCommandEvent(ActionToolMode.Shape)
    @assert(f.main.editMode == .Shape)
    f.main.sendCommandEvent(ActionToolMode.Line)
    @assert(f.main.editMode == .Line)
    f.main.sendCommandEvent(ActionToolMode.Arrow)
    @assert(f.main.editMode == .Arrow)
    f.main.sendCommandEvent(ActionToolMode.Poly)
    @assert(f.main.editMode == .Polygon)
    f.main.sendCommandEvent(ActionToolMode.Text)
    @assert(f.main.editMode == .Text)
    f.main.sendCommandEvent(ActionToolMode.Draw)
    @assert(f.main.editMode == .Draw)
    f.main.sendCommandEvent(ActionToolMode.Highlight)
    @assert(f.main.editMode == .Highlight)
    f.main.sendCommandEvent(ActionToolMode.Step)
    @assert(f.main.editMode == .Step)
    f.main.sendCommandEvent(ActionToolMode.Img)
    @assert(f.main.editMode == .Image)
    f.main.sendCommandEvent(ActionToolMode.PixSel)
    @assert(f.main.editMode == .PixSel)
    f.main.sendCommandEvent(ActionToolMode.Callout)
    @assert(f.main.editMode == .Callout)
    f.main.sendCommandEvent(ActionToolMode.Favorites)
    @assert(f.main.editMode == .Favorites)
    f.main.sendCommandEvent(ActionToolMode.Selection)
    @assert(f.main.editMode == .Selection)

    var evt = Testing.commandState(ActionToolMode.Selection)
    @assert(Testing.actionUpdate'ActionToolMode(f.main, ActionToolMode.Selection, &evt))
    @assert(evt.setFlags.has(CommandStateEvent.SetFlags.Checked))
    @assert(evt.checked)

    evt = Testing.commandState(ActionToolMode.Text)
    @assert(Testing.actionUpdate'ActionToolMode(f.main, ActionToolMode.Text, &evt))
    @assert(!evt.checked)

    f.shutdown()
}

// Capture delay, capture-option toggles and view clipping are pure state actions.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)

    f.main.sendCommandEvent(ActionCaptureDelay.Delay5)
    @assert(f.main.captureOptions.delay == 5)
    var delayEvt = Testing.commandState(ActionCaptureDelay.Delay)
    @assert(Testing.actionUpdate'ActionCaptureDelay(f.main, ActionCaptureDelay.Delay, &delayEvt))

    delayEvt = Testing.commandState(ActionCaptureDelay.Delay5)
    @assert(Testing.actionUpdate'ActionCaptureDelay(f.main, ActionCaptureDelay.Delay5, &delayEvt))
    @assert(delayEvt.checked)
    @assert(delayEvt.renderingHint.has(CommandStateEvent.RenderingHint.ExclusiveGroup))

    f.main.sendCommandEvent(ActionCaptureDelay.Delay0)
    @assert(f.main.captureOptions.delay == 0)
    f.main.sendCommandEvent(ActionCaptureDelay.Delay1)
    @assert(f.main.captureOptions.delay == 1)
    f.main.sendCommandEvent(ActionCaptureDelay.Delay2)
    @assert(f.main.captureOptions.delay == 2)
    f.main.sendCommandEvent(ActionCaptureDelay.Delay9)
    @assert(f.main.captureOptions.delay == 9)
    delayEvt = Testing.commandState(ActionCaptureDelay.Delay9)
    @assert(Testing.actionUpdate'ActionCaptureDelay(f.main, ActionCaptureDelay.Delay9, &delayEvt))
    @assert(delayEvt.checked)

    let hideEditor = f.main.captureOptions.hideEditorBefore
    @assert(Testing.actionExecute'ActionCapture(f.main, ActionCapture.HideEditor))
    @assert(f.main.captureOptions.hideEditorBefore != hideEditor)

    let captureCursor = f.main.captureOptions.captureCursor
    @assert(Testing.actionExecute'ActionCapture(f.main, ActionCapture.CaptureCursor))
    @assert(f.main.captureOptions.captureCursor != captureCursor)

    let toInPlace = f.main.captureOptions.inPlaceEdit
    @assert(Testing.actionExecute'ActionCapture(f.main, ActionCapture.ToInPlace))
    @assert(f.main.captureOptions.inPlaceEdit != toInPlace)

    let toEditor = f.main.captureOptions.sendToEditor
    @assert(Testing.actionExecute'ActionCapture(f.main, ActionCapture.ToEditor))
    @assert(f.main.captureOptions.sendToEditor != toEditor)

    let toClipboard = f.main.captureOptions.sendToClipboard
    @assert(Testing.actionExecute'ActionCapture(f.main, ActionCapture.ToClipboard))
    @assert(f.main.captureOptions.sendToClipboard != toClipboard)

    var capEvt = Testing.commandState(ActionCapture.ToClipboard)
    @assert(Testing.actionUpdate'ActionCapture(f.main, ActionCapture.ToClipboard, &capEvt))
    @assert(capEvt.setFlags.has(CommandStateEvent.SetFlags.Checked))
    @assert(capEvt.checked == f.main.captureOptions.sendToClipboard)

    let clip = f.main.editorOptions.clipToSelection
    f.main.sendCommandEvent(ActionView.Clip)
    @assert(f.main.editorOptions.clipToSelection != clip)

    var clipEvt = Testing.commandState(ActionView.Clip)
    @assert(Testing.actionUpdate'ActionView(f.main, ActionView.Clip, &clipEvt))
    @assert(clipEvt.checked == f.main.editorOptions.clipToSelection)

    f.shutdown()
}

// Zoom actions expose disabled state at clamps and execute without paint.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)

    f.editView.setZoom(1)
    f.main.sendCommandEvent(ActionZoom.ZoomIn)
    @assert(f.editView.zoom > 1)
    f.main.sendCommandEvent(ActionZoom.ZoomOut)
    @assert(Math.abs(f.editView.zoom - 1) < 0.001)

    f.main.sendCommandEvent(ActionZoom.Zoom1)
    @assert(Math.abs(f.editView.zoom - 1) < 0.001)

    f.main.sendCommandEvent(ActionZoom.ZoomFit)
    @assert(f.editView.zoom > 1)
    f.main.sendCommandEvent(ActionZoom.Zoom1)
    @assert(Math.abs(f.editView.zoom - 1) < 0.001)

    f.editView.setZoom(EditView.MaxZoom + 5)
    @assert(Math.abs(f.editView.zoom - EditView.MaxZoom) < 0.001)
    @assert(!f.editView.canZoomIn())
    var evt = Testing.commandState(ActionZoom.ZoomIn)
    @assert(Testing.actionUpdate'ActionZoom(f.main, ActionZoom.ZoomIn, &evt))
    @assert(evt.disabled)

    f.editView.setZoom(EditView.MinZoom - 5)
    @assert(Math.abs(f.editView.zoom - EditView.MinZoom) < 0.001)
    @assert(!f.editView.canZoomOut())
    evt = Testing.commandState(ActionZoom.ZoomOut)
    @assert(Testing.actionUpdate'ActionZoom(f.main, ActionZoom.ZoomOut, &evt))
    @assert(evt.disabled)

    f.shutdown()
}

// Edit, pixsel, image and undo actions report enabled/hidden state from current selection.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)

    let text = testAddText(f.capture, 0, 0, 40, 20)
    let image = testAddImage(f.capture, 50, 0, 20, 20)
    let pixSel = testAddShape(f.capture, 80, 0, 20, 20, .PixSel)
    pixSel.kind = .Rectangle

    var undoEvt = Testing.commandState(ActionUndo.DoUndo)
    @assert(Testing.actionUpdate'ActionUndo(f.main, ActionUndo.DoUndo, &undoEvt))
    @assert(undoEvt.disabled)

    var evt = Testing.commandState(ActionEdit.EditText)
    @assert(Testing.actionUpdate'ActionEdit(f.main, ActionEdit.EditText, &evt))
    @assert(evt.disabled)
    @assert(evt.hidden)

    f.capture.selection.add(0)
    evt = Testing.commandState(ActionEdit.EditText)
    @assert(Testing.actionUpdate'ActionEdit(f.main, ActionEdit.EditText, &evt))
    @assert(!evt.disabled)
    @assert(!evt.hidden)

    text.rotate = 25
    evt         = Testing.commandState(ActionEdit.ResetRotation)
    @assert(Testing.actionUpdate'ActionEdit(f.main, ActionEdit.ResetRotation, &evt))
    @assert(!evt.disabled)
    @assert(!evt.hidden)
    f.main.sendCommandEvent(ActionEdit.ResetRotation)
    @assert(text.rotate == 0)

    f.capture.selection.clear()
    f.capture.selection.add(1)
    evt = Testing.commandState(ActionEdit.ClearImageInside)
    @assert(Testing.actionUpdate'ActionEdit(f.main, ActionEdit.ClearImageInside, &evt))
    @assert(!evt.hidden)
    @assert(evt.disabled)

    image.image = Image.create(2, 2, .BGRA8)
    evt         = Testing.commandState(ActionEdit.ClearImageInside)
    @assert(Testing.actionUpdate'ActionEdit(f.main, ActionEdit.ClearImageInside, &evt))
    @assert(!evt.disabled)
    f.main.sendCommandEvent(ActionEdit.ClearImageInside)
    @assert(!image.image.isValid())

    f.capture.selection.clear()
    evt = Testing.commandState(ActionPixSel.Fill)
    @assert(Testing.actionUpdate'ActionPixSel(f.main, ActionPixSel.Fill, &evt))
    @assert(evt.disabled)
    @assert(evt.hidden)

    f.capture.selection.add(2)
    evt = Testing.commandState(ActionPixSel.Fill)
    @assert(Testing.actionUpdate'ActionPixSel(f.main, ActionPixSel.Fill, &evt))
    @assert(!evt.disabled)
    @assert(!evt.hidden)

    let undo = f.capture.newUndo(.OffsetSelection)
    undo.newPosX = 1
    f.capture.pushUndo(undo)
    evt = Testing.commandState(ActionUndo.DoUndo)
    @assert(Testing.actionUpdate'ActionUndo(f.main, ActionUndo.DoUndo, &evt))
    @assert(!evt.disabled)
    f.main.sendCommandEvent(ActionUndo.DoUndo)
    evt = Testing.commandState(ActionUndo.DoRedo)
    @assert(Testing.actionUpdate'ActionUndo(f.main, ActionUndo.DoRedo, &evt))
    @assert(!evt.disabled)

    evt = Testing.commandState(ActionImage.RestoreOrg)
    @assert(Testing.actionUpdate'ActionImage(f.main, ActionImage.RestoreOrg, &evt))
    @assert(evt.disabled)
    f.capture.backImgOriginal = Image.create(5, 5, .BGRA8)
    evt                       = Testing.commandState(ActionImage.RestoreOrg)
    @assert(Testing.actionUpdate'ActionImage(f.main, ActionImage.RestoreOrg, &evt))
    @assert(!evt.disabled)

    f.shutdown()
}

// Nudge, align and arrange command actions integrate with undo and command-state disabling.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)

    let a = testAddShape(f.capture, 10, 10, 10, 10)
    let b = testAddShape(f.capture, 50, 40, 20, 20)

    var evt = Testing.commandState(ActionMoveSel.Right1)
    @assert(Testing.actionUpdate'ActionMoveSel(f.main, ActionMoveSel.Right1, &evt))
    @assert(evt.disabled)

    f.capture.selection.add(0)
    f.capture.selection.add(1)
    evt = Testing.commandState(ActionMoveSel.Right1)
    @assert(Testing.actionUpdate'ActionMoveSel(f.main, ActionMoveSel.Right1, &evt))
    @assert(!evt.disabled)

    f.main.sendCommandEvent(ActionMoveSel.Left1)
    @assert(a.x == 9)
    @assert(b.x == 49)
    f.main.sendCommandEvent(ActionMoveSel.Top1)
    @assert(a.y == 9)
    @assert(b.y == 39)
    f.main.sendCommandEvent(ActionMoveSel.Right1)
    @assert(a.x == 10)
    @assert(b.x == 50)
    f.main.sendCommandEvent(ActionMoveSel.Bottom1)
    @assert(a.y == 10)
    @assert(b.y == 40)
    f.main.sendCommandEvent(ActionMoveSel.Left)
    @assert(a.x == 5)
    @assert(b.x == 45)
    f.main.sendCommandEvent(ActionMoveSel.Top)
    @assert(a.y == 5)
    @assert(b.y == 35)
    f.main.sendCommandEvent(ActionMoveSel.Right)
    @assert(a.x == 10)
    @assert(b.x == 50)
    f.main.sendCommandEvent(ActionMoveSel.Bottom)
    @assert(a.y == 10)
    @assert(b.y == 40)

    f.capture.undo()
    @assert(a.y == 5)
    @assert(b.y == 35)

    f.capture.redo()
    @assert(a.y == 10)
    @assert(b.y == 40)

    evt = Testing.commandState(ActionAlign.AlignLeft)
    @assert(Testing.actionUpdate'ActionAlign(f.main, ActionAlign.AlignLeft, &evt))
    @assert(!evt.disabled)
    f.main.sendCommandEvent(ActionAlign.AlignLeft)
    @assert(a.x == 10)
    @assert(b.x == 10)
    f.capture.undo()
    @assert(a.x == 10)
    @assert(b.x == 50)

    evt = Testing.commandState(ActionAlign.AlignRight)
    @assert(Testing.actionUpdate'ActionAlign(f.main, ActionAlign.AlignRight, &evt))
    @assert(!evt.disabled)
    f.main.sendCommandEvent(ActionAlign.AlignRight)
    @assert(a.x == 60)
    @assert(b.x == 50)
    f.capture.undo()
    @assert(a.x == 10)
    @assert(b.x == 50)

    evt = Testing.commandState(ActionAlign.AlignCenter)
    @assert(Testing.actionUpdate'ActionAlign(f.main, ActionAlign.AlignCenter, &evt))
    @assert(!evt.disabled)
    f.main.sendCommandEvent(ActionAlign.AlignCenter)
    @assert(a.x == 35)
    @assert(b.x == 30)
    f.capture.undo()
    @assert(a.x == 10)
    @assert(b.x == 50)

    evt = Testing.commandState(ActionAlign.AlignTop)
    @assert(Testing.actionUpdate'ActionAlign(f.main, ActionAlign.AlignTop, &evt))
    @assert(!evt.disabled)
    f.main.sendCommandEvent(ActionAlign.AlignTop)
    @assert(a.y == 10)
    @assert(b.y == 10)

    f.capture.undo()
    @assert(a.y == 10)
    @assert(b.y == 40)

    evt = Testing.commandState(ActionAlign.AlignBottom)
    @assert(Testing.actionUpdate'ActionAlign(f.main, ActionAlign.AlignBottom, &evt))
    @assert(!evt.disabled)
    f.main.sendCommandEvent(ActionAlign.AlignBottom)
    @assert(a.y == 50)
    @assert(b.y == 40)
    f.capture.undo()
    @assert(a.y == 10)
    @assert(b.y == 40)

    evt = Testing.commandState(ActionAlign.AlignMiddle)
    @assert(Testing.actionUpdate'ActionAlign(f.main, ActionAlign.AlignMiddle, &evt))
    @assert(!evt.disabled)
    f.main.sendCommandEvent(ActionAlign.AlignMiddle)
    @assert(a.y == 30)
    @assert(b.y == 25)
    f.capture.undo()
    @assert(a.y == 10)
    @assert(b.y == 40)

    f.capture.selection.clear()
    f.capture.selection.add(1)
    evt = Testing.commandState(ActionAlign.AlignTop)
    @assert(Testing.actionUpdate'ActionAlign(f.main, ActionAlign.AlignTop, &evt))
    @assert(evt.disabled)

    f.shutdown()
}

// Arrange command variants reorder forms through the command dispatcher, not
// only through direct Undo construction.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)

    let a = testAddShape(f.capture, 0, 0, 10, 10)
    let b = testAddShape(f.capture, 20, 0, 10, 10)
    let c = testAddText(f.capture, 40, 0, 10, 10)

    f.capture.selection.add(0)
    f.main.sendCommandEvent(ActionAlign.MoveForward)
    @assert(@dataof(f.capture.forms[0]) == b)
    @assert(@dataof(f.capture.forms[1]) == a)
    @assert(@dataof(f.capture.forms[2]) == c)
    @assert(f.capture.selection[0] == 1)
    f.capture.undo()

    f.capture.selection.clear()
    f.capture.selection.add(2)
    f.main.sendCommandEvent(ActionAlign.MoveBackward)
    @assert(@dataof(f.capture.forms[0]) == a)
    @assert(@dataof(f.capture.forms[1]) == c)
    @assert(@dataof(f.capture.forms[2]) == b)
    @assert(f.capture.selection[0] == 1)
    f.capture.undo()

    f.capture.selection.clear()
    f.capture.selection.add(0)
    f.main.sendCommandEvent(ActionAlign.SendToFront)
    @assert(@dataof(f.capture.forms[0]) == b)
    @assert(@dataof(f.capture.forms[1]) == c)
    @assert(@dataof(f.capture.forms[2]) == a)
    @assert(f.capture.selection[0] == 2)
    f.capture.undo()

    f.capture.selection.clear()
    f.capture.selection.add(2)
    f.main.sendCommandEvent(ActionAlign.SendToBack)
    @assert(@dataof(f.capture.forms[0]) == c)
    @assert(@dataof(f.capture.forms[1]) == a)
    @assert(@dataof(f.capture.forms[2]) == b)
    @assert(f.capture.selection[0] == 0)
    f.capture.undo()

    f.shutdown()
}

// File, copy/paste, flatten and small dialog actions expose stable command state
// without executing OS, clipboard or dialog branches.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)

    var evt = Testing.commandState(ActionFile.SaveAsImage)
    @assert(Testing.actionUpdate'ActionFile(f.main, ActionFile.SaveAsImage, &evt))
    @assert(!evt.disabled)

    evt = Testing.commandState(ActionFile.CaptureFileLocation)
    @assert(Testing.actionUpdate'ActionFile(f.main, ActionFile.CaptureFileLocation, &evt))
    @assert(!evt.disabled)

    evt = Testing.commandState(ActionFile.UnlinkImage)
    @assert(Testing.actionUpdate'ActionFile(f.main, ActionFile.UnlinkImage, &evt))
    @assert(evt.disabled)

    f.capture.linkedImage = "linked.png"
    evt                   = Testing.commandState(ActionFile.UnlinkImage)
    @assert(Testing.actionUpdate'ActionFile(f.main, ActionFile.UnlinkImage, &evt))
    @assert(!evt.disabled)

    evt = Testing.commandState(ActionFile.LinkedFileLocation)
    @assert(Testing.actionUpdate'ActionFile(f.main, ActionFile.LinkedFileLocation, &evt))
    @assert(!evt.disabled)

    evt = Testing.commandState(ActionCopyPaste.Copy)
    @assert(Testing.actionUpdate'ActionCopyPaste(f.main, ActionCopyPaste.Copy, &evt))
    @assert(evt.disabled)

    let shape = testAddShape(f.capture, 10, 10, 20, 20)
    shape.kind = .Rectangle
    f.capture.selection.add(0)
    evt = Testing.commandState(ActionCopyPaste.Copy)
    @assert(Testing.actionUpdate'ActionCopyPaste(f.main, ActionCopyPaste.Copy, &evt))
    @assert(!evt.disabled)

    evt = Testing.commandState(ActionFlatten.Flatten)
    @assert(Testing.actionUpdate'ActionFlatten(f.main, ActionFlatten.Flatten, &evt))
    @assert(!evt.disabled)
    f.main.sendCommandEvent(ActionFlatten.Flatten)
    @assert(f.capture.forms.count == 0)
    @assert(f.capture.selection.count == 0)
    @assert(f.capture.canUndo())
    f.capture.undo()
    @assert(f.capture.forms.count == 1)

    f.capture.selection.clear()
    evt = Testing.commandState(ActionFlatten.Flatten)
    @assert(Testing.actionUpdate'ActionFlatten(f.main, ActionFlatten.Flatten, &evt))
    @assert(evt.disabled)

    evt = Testing.commandState(ActionFlatten.FlattenAll)
    @assert(Testing.actionUpdate'ActionFlatten(f.main, ActionFlatten.FlattenAll, &evt))
    @assert(!evt.disabled)

    f.capture.selection.add(0)
    let image = testAddImage(f.capture, 40, 10, 20, 20)
    image.kind = .Image
    f.capture.selection.clear()
    f.capture.selection.add(1)
    evt = Testing.commandState(ActionCopyPaste.PasteImageInside)
    @assert(Testing.actionUpdate'ActionCopyPaste(f.main, ActionCopyPaste.PasteImageInside, &evt))
    @assert(!evt.hidden)

    f.capture.selection.clear()
    let pixSel = testAddShape(f.capture, 70, 10, 20, 20, .PixSel)
    pixSel.kind = .Rectangle
    f.capture.selection.add(2)
    evt = Testing.commandState(ActionPixSel.SmartMove)
    @assert(Testing.actionUpdate'ActionPixSel(f.main, ActionPixSel.SmartMove, &evt))
    @assert(!evt.disabled)
    @assert(!evt.hidden)

    evt = Testing.commandState(ActionOptions.Options)
    @assert(Testing.actionUpdate'ActionOptions(f.main, ActionOptions.Options, &evt))
    @assert(!evt.name.isEmpty())

    evt = Testing.commandState(ActionAbout.About)
    @assert(Testing.actionUpdate'ActionAbout(f.main, ActionAbout.About, &evt))
    @assert(!evt.name.isEmpty())

    evt = Testing.commandState(ActionQuickStyle.Reset)
    @assert(Testing.actionUpdate'ActionQuickStyle(f.main, ActionQuickStyle.Reset, &evt))
    @assert(!evt.name.isEmpty())

    discard shape
    f.shutdown()
}

// FlattenAll command execution is renderer-backed but stays fully in memory.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)

    let shape = testAddShape(f.capture, 10, 10, 20, 20)
    shape.kind = .Rectangle
    discard testAddText(f.capture, 40, 10, 20, 20)

    f.main.sendCommandEvent(ActionFlatten.FlattenAll)
    @assert(f.capture.forms.count == 0)
    @assert(f.capture.selection.count == 0)
    @assert(f.capture.canUndo())

    f.capture.undo()
    @assert(f.capture.forms.count == 2)

    f.shutdown()
}
