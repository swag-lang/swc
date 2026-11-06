#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// accept() is generated from the newCmdId scope prefix (see acceptOwnCmdIds): an
// action must accept its own ids and reject those of every other action.
#test
{
    Swag.require(Gui.Testing.actionAccept'ActionSelection(null, ActionSelection.SelectAll))
    Swag.require(Gui.Testing.actionAccept'ActionSelection(null, ActionSelection.Freeze))
    Swag.require(not Gui.Testing.actionAccept'ActionSelection(null, ActionCapture.Area))
    Swag.require(not Gui.Testing.actionAccept'ActionSelection(null, ActionZoom.ZoomFit))
}

// The headless fixture can register safe commands and drive them through the
// same command dispatch path as menus, buttons and shortcuts.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    discard testAddShape(f.capture, 10, 10, 20, 20)
    discard testAddText(f.capture, 50, 10, 20, 20)

    f.main.sendCommandEvent(ActionSelection.SelectAll)
    Swag.require(f.capture.selection.count == 2)

    f.main.sendCommandEvent(ActionSelection.DeSelectAll)
    Swag.require(f.capture.selection.count == 0)

    f.main.sendCommandEvent(ActionSelection.DeleteSelection)
    Swag.require(f.capture.forms.count == 2)
    Swag.require(not f.capture.canUndo())

    f.capture.selection.add(0)
    f.main.sendCommandEvent(ActionSelection.DeleteSelection)
    Swag.require(f.capture.forms.count == 1)
    Swag.require(f.capture.selection.count == 0)
    Swag.require(f.capture.canUndo())

    f.main.sendCommandEvent(ActionToolMode.Text)
    Swag.require(f.main.editMode == .Text)

    f.main.sendCommandEvent(ActionView.Clip)
    Swag.require(f.main.editorOptions.clipToSelection)

    f.main.sendCommandEvent(ActionSelection.Freeze)
    Swag.require(f.main.freezeSel)
    Swag.require(f.main.embInfoFreeze != null)
    f.main.sendCommandEvent(ActionSelection.Freeze)
    Swag.require(not f.main.freezeSel)
    Swag.require(f.main.embInfoFreeze == null)
}

// Tool-mode actions update checked state and switch every safe editor mode.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    f.main.sendCommandEvent(ActionToolMode.Shape)
    Swag.require(f.main.editMode == .Shape)
    f.main.sendCommandEvent(ActionToolMode.Line)
    Swag.require(f.main.editMode == .Line)
    f.main.sendCommandEvent(ActionToolMode.Arrow)
    Swag.require(f.main.editMode == .Arrow)
    f.main.sendCommandEvent(ActionToolMode.Poly)
    Swag.require(f.main.editMode == .Polygon)
    f.main.sendCommandEvent(ActionToolMode.Text)
    Swag.require(f.main.editMode == .Text)
    f.main.sendCommandEvent(ActionToolMode.Draw)
    Swag.require(f.main.editMode == .Draw)
    f.main.sendCommandEvent(ActionToolMode.Highlight)
    Swag.require(f.main.editMode == .Highlight)
    f.main.sendCommandEvent(ActionToolMode.Step)
    Swag.require(f.main.editMode == .Step)
    f.main.sendCommandEvent(ActionToolMode.Img)
    Swag.require(f.main.editMode == .Image)
    f.main.sendCommandEvent(ActionToolMode.PixSel)
    Swag.require(f.main.editMode == .PixSel)
    f.main.sendCommandEvent(ActionToolMode.Callout)
    Swag.require(f.main.editMode == .Callout)
    f.main.sendCommandEvent(ActionToolMode.Favorites)
    Swag.require(f.main.editMode == .Favorites)
    f.main.sendCommandEvent(ActionToolMode.Selection)
    Swag.require(f.main.editMode == .Selection)

    var evt = Gui.Testing.commandState(ActionToolMode.Selection)
    Swag.require(Gui.Testing.actionUpdate'ActionToolMode(f.main, ActionToolMode.Selection, &evt))
    Swag.require(evt.updatedFields.has(CommandStateEvent.UpdatedFields.Checked))
    Swag.require(evt.checked)

    evt = Gui.Testing.commandState(ActionToolMode.Text)
    Swag.require(Gui.Testing.actionUpdate'ActionToolMode(f.main, ActionToolMode.Text, &evt))
    Swag.require(not evt.checked)
}

// Capture delay, capture-option toggles and view clipping are pure state actions.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    f.main.sendCommandEvent(ActionCaptureDelay.Delay5)
    Swag.require(f.main.captureOptions.delay == 5)
    var delayEvt = Gui.Testing.commandState(ActionCaptureDelay.Delay)
    Swag.require(Gui.Testing.actionUpdate'ActionCaptureDelay(f.main, ActionCaptureDelay.Delay, &delayEvt))

    delayEvt = Gui.Testing.commandState(ActionCaptureDelay.Delay5)
    Swag.require(Gui.Testing.actionUpdate'ActionCaptureDelay(f.main, ActionCaptureDelay.Delay5, &delayEvt))
    Swag.require(delayEvt.checked)
    Swag.require(delayEvt.renderingHint.has(CommandStateEvent.RenderingHint.ExclusiveGroup))

    f.main.sendCommandEvent(ActionCaptureDelay.Delay0)
    Swag.require(f.main.captureOptions.delay == 0)
    f.main.sendCommandEvent(ActionCaptureDelay.Delay3)
    Swag.require(f.main.captureOptions.delay == 3)
    f.main.sendCommandEvent(ActionCaptureDelay.Delay10)
    Swag.require(f.main.captureOptions.delay == 10)
    delayEvt = Gui.Testing.commandState(ActionCaptureDelay.Delay10)
    Swag.require(Gui.Testing.actionUpdate'ActionCaptureDelay(f.main, ActionCaptureDelay.Delay10, &delayEvt))
    Swag.require(delayEvt.checked)
    Swag.require(delayEvt.name == "10 Seconds")

    // A wait set in the options that the menu does not offer is still named by the menu entry.
    f.main.captureOptions.delay = 7
    delayEvt = Gui.Testing.commandState(ActionCaptureDelay.Delay)
    Swag.require(Gui.Testing.actionUpdate'ActionCaptureDelay(f.main, ActionCaptureDelay.Delay, &delayEvt))
    Swag.require(delayEvt.name == "Delay Before Capture (7 Seconds)")

    let hideEditor     = f.main.captureOptions.hideEditorBefore
    var actionExecuted = Gui.Testing.actionExecute'ActionCapture(f.main, ActionCapture.HideEditor)
    Swag.require(actionExecuted)
    Swag.require(f.main.captureOptions.hideEditorBefore != hideEditor)

    let captureCursor = f.main.captureOptions.captureCursor
    actionExecuted = Gui.Testing.actionExecute'ActionCapture(f.main, ActionCapture.CaptureCursor)
    Swag.require(actionExecuted)
    Swag.require(f.main.captureOptions.captureCursor != captureCursor)

    let toInPlace = f.main.captureOptions.inPlaceEdit
    actionExecuted = Gui.Testing.actionExecute'ActionCapture(f.main, ActionCapture.ToInPlace)
    Swag.require(actionExecuted)
    Swag.require(f.main.captureOptions.inPlaceEdit != toInPlace)

    let toEditor = f.main.captureOptions.sendToEditor
    actionExecuted = Gui.Testing.actionExecute'ActionCapture(f.main, ActionCapture.ToEditor)
    Swag.require(actionExecuted)
    Swag.require(f.main.captureOptions.sendToEditor != toEditor)

    let toClipboard = f.main.captureOptions.sendToClipboard
    actionExecuted = Gui.Testing.actionExecute'ActionCapture(f.main, ActionCapture.ToClipboard)
    Swag.require(actionExecuted)
    Swag.require(f.main.captureOptions.sendToClipboard != toClipboard)

    var capEvt = Gui.Testing.commandState(ActionCapture.ToClipboard)
    Swag.require(Gui.Testing.actionUpdate'ActionCapture(f.main, ActionCapture.ToClipboard, &capEvt))
    Swag.require(capEvt.updatedFields.has(CommandStateEvent.UpdatedFields.Checked))
    Swag.require(capEvt.checked == f.main.captureOptions.sendToClipboard)

    let clip = f.main.editorOptions.clipToSelection
    f.main.sendCommandEvent(ActionView.Clip)
    Swag.require(f.main.editorOptions.clipToSelection != clip)

    var clipEvt = Gui.Testing.commandState(ActionView.Clip)
    Swag.require(Gui.Testing.actionUpdate'ActionView(f.main, ActionView.Clip, &clipEvt))
    Swag.require(clipEvt.checked == f.main.editorOptions.clipToSelection)
}

// Zoom actions expose disabled state at clamps and execute without paint.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    f.editView.setZoom(1)
    f.main.sendCommandEvent(ActionZoom.ZoomIn)
    Swag.require(f.editView.zoom > 1)
    f.main.sendCommandEvent(ActionZoom.ZoomOut)
    Swag.require(Math.abs(f.editView.zoom - 1) < 0.001)

    f.main.sendCommandEvent(ActionZoom.Zoom1)
    Swag.require(Math.abs(f.editView.zoom - 1) < 0.001)

    f.main.sendCommandEvent(ActionZoom.ZoomFit)
    Swag.require(f.editView.zoom > 1)
    f.main.sendCommandEvent(ActionZoom.Zoom1)
    Swag.require(Math.abs(f.editView.zoom - 1) < 0.001)

    f.editView.setZoom(EditView.MaxZoom + 5)
    Swag.require(Math.abs(f.editView.zoom - EditView.MaxZoom) < 0.001)
    Swag.require(not f.editView.canZoomIn())
    var evt = Gui.Testing.commandState(ActionZoom.ZoomIn)
    Swag.require(Gui.Testing.actionUpdate'ActionZoom(f.main, ActionZoom.ZoomIn, &evt))
    Swag.require(evt.disabled)

    f.editView.setZoom(EditView.MinZoom - 5)
    Swag.require(Math.abs(f.editView.zoom - EditView.MinZoom) < 0.001)
    Swag.require(not f.editView.canZoomOut())
    evt = Gui.Testing.commandState(ActionZoom.ZoomOut)
    Swag.require(Gui.Testing.actionUpdate'ActionZoom(f.main, ActionZoom.ZoomOut, &evt))
    Swag.require(evt.disabled)

    evt = Gui.Testing.commandState(ActionZoom.Zoom1)
    Swag.require(Gui.Testing.actionUpdate'ActionZoom(f.main, ActionZoom.Zoom1, &evt))
    Swag.require(evt.updatedFields.has(.Icon) and evt.icon.isValid())
    evt = Gui.Testing.commandState(ActionZoom.ZoomFit)
    Swag.require(Gui.Testing.actionUpdate'ActionZoom(f.main, ActionZoom.ZoomFit, &evt))
    Swag.require(evt.updatedFields.has(.Icon) and evt.icon.isValid())
}

// Edit, pixsel, image and undo actions report enabled/hidden state from current selection.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    let text   = testAddText(f.capture, 0, 0, 40, 20)
    let image  = testAddImage(f.capture, 50, 0, 20, 20)
    let pixSel = testAddShape(f.capture, 80, 0, 20, 20, .PixSel)
    pixSel.kind = .Rectangle

    var undoEvt = Gui.Testing.commandState(ActionUndo.DoUndo)
    Swag.require(Gui.Testing.actionUpdate'ActionUndo(f.main, ActionUndo.DoUndo, &undoEvt))
    Swag.require(undoEvt.disabled)

    var evt = Gui.Testing.commandState(ActionEdit.EditText)
    Swag.require(Gui.Testing.actionUpdate'ActionEdit(f.main, ActionEdit.EditText, &evt))
    Swag.require(evt.disabled)
    Swag.require(evt.hidden)

    f.capture.selection.add(0)
    evt = Gui.Testing.commandState(ActionEdit.EditText)
    Swag.require(Gui.Testing.actionUpdate'ActionEdit(f.main, ActionEdit.EditText, &evt))
    Swag.require(not evt.disabled)
    Swag.require(not evt.hidden)

    text.rotate = 25
    evt         = Gui.Testing.commandState(ActionEdit.ResetRotation)
    Swag.require(Gui.Testing.actionUpdate'ActionEdit(f.main, ActionEdit.ResetRotation, &evt))
    Swag.require(not evt.disabled)
    Swag.require(not evt.hidden)
    f.main.sendCommandEvent(ActionEdit.ResetRotation)
    Swag.require(text.rotate == 0)

    f.capture.selection.clear()
    f.capture.selection.add(1)
    evt = Gui.Testing.commandState(ActionEdit.ClearImageInside)
    Swag.require(Gui.Testing.actionUpdate'ActionEdit(f.main, ActionEdit.ClearImageInside, &evt))
    Swag.require(not evt.hidden)
    Swag.require(evt.disabled)

    image.image = Image.create(2, 2, .BGRA8)
    evt         = Gui.Testing.commandState(ActionEdit.ClearImageInside)
    Swag.require(Gui.Testing.actionUpdate'ActionEdit(f.main, ActionEdit.ClearImageInside, &evt))
    Swag.require(not evt.disabled)
    f.main.sendCommandEvent(ActionEdit.ClearImageInside)
    Swag.require(not image.image.isValid())

    f.capture.selection.clear()
    evt = Gui.Testing.commandState(ActionPixSel.Fill)
    Swag.require(Gui.Testing.actionUpdate'ActionPixSel(f.main, ActionPixSel.Fill, &evt))
    Swag.require(evt.disabled)
    Swag.require(evt.hidden)

    f.capture.selection.add(2)
    evt = Gui.Testing.commandState(ActionPixSel.Fill)
    Swag.require(Gui.Testing.actionUpdate'ActionPixSel(f.main, ActionPixSel.Fill, &evt))
    Swag.require(not evt.disabled)
    Swag.require(not evt.hidden)

    let undo = f.capture.newUndo(.OffsetSelection)
    undo.newPosX = 1
    f.capture.pushUndo(undo)
    evt = Gui.Testing.commandState(ActionUndo.DoUndo)
    Swag.require(Gui.Testing.actionUpdate'ActionUndo(f.main, ActionUndo.DoUndo, &evt))
    Swag.require(not evt.disabled)
    f.main.sendCommandEvent(ActionUndo.DoUndo)
    evt = Gui.Testing.commandState(ActionUndo.DoRedo)
    Swag.require(Gui.Testing.actionUpdate'ActionUndo(f.main, ActionUndo.DoRedo, &evt))
    Swag.require(not evt.disabled)

    evt = Gui.Testing.commandState(ActionImage.RestoreOrg)
    Swag.require(Gui.Testing.actionUpdate'ActionImage(f.main, ActionImage.RestoreOrg, &evt))
    Swag.require(evt.disabled)
    f.capture.backImgOriginal = Image.create(5, 5, .BGRA8)
    evt = Gui.Testing.commandState(ActionImage.RestoreOrg)
    Swag.require(Gui.Testing.actionUpdate'ActionImage(f.main, ActionImage.RestoreOrg, &evt))
    Swag.require(not evt.disabled)

    // Image commands stay present when disabled. Only descriptors that explicitly opt into
    // contextual hiding may set Hidden.
    Memory.delete(f.editView.capture)
    f.editView.capture = null
    for id in [ActionImage.ResizeImage, ActionImage.ExpandImage, ActionImage.ExpandCapture, ActionImage.TrimCapture, ActionImage.FlipImage, ActionImage.MirrorImage, ActionImage.RotateImageRight, ActionImage.RotateImageLeft]
    {
        evt = Gui.Testing.commandState(id)
        Swag.require(Gui.Testing.actionUpdate'ActionImage(f.main, id, &evt))
        Swag.require(not evt.updatedFields.has(.Hidden))
        Swag.require(not evt.hidden)
    }
}

// Nudge, align and arrange command actions integrate with undo and command-state disabling.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    let a = testAddShape(f.capture, 10, 10, 10, 10)
    let b = testAddShape(f.capture, 50, 40, 20, 20)

    var evt = Gui.Testing.commandState(ActionMoveSel.Right1)
    Swag.require(Gui.Testing.actionUpdate'ActionMoveSel(f.main, ActionMoveSel.Right1, &evt))
    Swag.require(evt.disabled)

    f.capture.selection.add(0)
    f.capture.selection.add(1)
    evt = Gui.Testing.commandState(ActionMoveSel.Right1)
    Swag.require(Gui.Testing.actionUpdate'ActionMoveSel(f.main, ActionMoveSel.Right1, &evt))
    Swag.require(not evt.disabled)

    f.main.sendCommandEvent(ActionMoveSel.Left1)
    Swag.require(a.x == 9)
    Swag.require(b.x == 49)
    f.main.sendCommandEvent(ActionMoveSel.Top1)
    Swag.require(a.y == 9)
    Swag.require(b.y == 39)
    f.main.sendCommandEvent(ActionMoveSel.Right1)
    Swag.require(a.x == 10)
    Swag.require(b.x == 50)
    f.main.sendCommandEvent(ActionMoveSel.Bottom1)
    Swag.require(a.y == 10)
    Swag.require(b.y == 40)
    f.main.sendCommandEvent(ActionMoveSel.Left)
    Swag.require(a.x == 10 - NudgeFar)
    Swag.require(b.x == 50 - NudgeFar)
    f.main.sendCommandEvent(ActionMoveSel.Top)
    Swag.require(a.y == 10 - NudgeFar)
    Swag.require(b.y == 40 - NudgeFar)
    f.main.sendCommandEvent(ActionMoveSel.Right)
    Swag.require(a.x == 10)
    Swag.require(b.x == 50)
    f.main.sendCommandEvent(ActionMoveSel.Bottom)
    Swag.require(a.y == 10)
    Swag.require(b.y == 40)

    f.capture.undo()
    Swag.require(a.y == 10 - NudgeFar)
    Swag.require(b.y == 40 - NudgeFar)

    f.capture.redo()
    Swag.require(a.y == 10)
    Swag.require(b.y == 40)

    evt = Gui.Testing.commandState(ActionAlign.AlignLeft)
    Swag.require(Gui.Testing.actionUpdate'ActionAlign(f.main, ActionAlign.AlignLeft, &evt))
    Swag.require(not evt.disabled)
    f.main.sendCommandEvent(ActionAlign.AlignLeft)
    Swag.require(a.x == 10)
    Swag.require(b.x == 10)
    f.capture.undo()
    Swag.require(a.x == 10)
    Swag.require(b.x == 50)

    evt = Gui.Testing.commandState(ActionAlign.AlignRight)
    Swag.require(Gui.Testing.actionUpdate'ActionAlign(f.main, ActionAlign.AlignRight, &evt))
    Swag.require(not evt.disabled)
    f.main.sendCommandEvent(ActionAlign.AlignRight)
    Swag.require(a.x == 60)
    Swag.require(b.x == 50)
    f.capture.undo()
    Swag.require(a.x == 10)
    Swag.require(b.x == 50)

    evt = Gui.Testing.commandState(ActionAlign.AlignCenter)
    Swag.require(Gui.Testing.actionUpdate'ActionAlign(f.main, ActionAlign.AlignCenter, &evt))
    Swag.require(not evt.disabled)
    f.main.sendCommandEvent(ActionAlign.AlignCenter)
    Swag.require(a.x == 35)
    Swag.require(b.x == 30)
    f.capture.undo()
    Swag.require(a.x == 10)
    Swag.require(b.x == 50)

    evt = Gui.Testing.commandState(ActionAlign.AlignTop)
    Swag.require(Gui.Testing.actionUpdate'ActionAlign(f.main, ActionAlign.AlignTop, &evt))
    Swag.require(not evt.disabled)
    f.main.sendCommandEvent(ActionAlign.AlignTop)
    Swag.require(a.y == 10)
    Swag.require(b.y == 10)

    f.capture.undo()
    Swag.require(a.y == 10)
    Swag.require(b.y == 40)

    evt = Gui.Testing.commandState(ActionAlign.AlignBottom)
    Swag.require(Gui.Testing.actionUpdate'ActionAlign(f.main, ActionAlign.AlignBottom, &evt))
    Swag.require(not evt.disabled)
    f.main.sendCommandEvent(ActionAlign.AlignBottom)
    Swag.require(a.y == 50)
    Swag.require(b.y == 40)
    f.capture.undo()
    Swag.require(a.y == 10)
    Swag.require(b.y == 40)

    evt = Gui.Testing.commandState(ActionAlign.AlignMiddle)
    Swag.require(Gui.Testing.actionUpdate'ActionAlign(f.main, ActionAlign.AlignMiddle, &evt))
    Swag.require(not evt.disabled)
    f.main.sendCommandEvent(ActionAlign.AlignMiddle)
    Swag.require(a.y == 30)
    Swag.require(b.y == 25)
    f.capture.undo()
    Swag.require(a.y == 10)
    Swag.require(b.y == 40)

    f.capture.selection.clear()
    f.capture.selection.add(1)
    evt = Gui.Testing.commandState(ActionAlign.AlignTop)
    Swag.require(Gui.Testing.actionUpdate'ActionAlign(f.main, ActionAlign.AlignTop, &evt))
    Swag.require(evt.disabled)
}

// Arrange command variants reorder forms through the command dispatcher, not
// only through direct Undo construction.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    let a = testAddShape(f.capture, 0, 0, 10, 10)
    let b = testAddShape(f.capture, 20, 0, 10, 10)
    let c = testAddText(f.capture, 40, 0, 10, 10)

    f.capture.selection.add(0)
    f.main.sendCommandEvent(ActionAlign.MoveForward)
    Swag.require(f.capture.forms[0].buffer == b)
    Swag.require(f.capture.forms[1].buffer == a)
    Swag.require(f.capture.forms[2].buffer == c)
    Swag.require(f.capture.selection[0] == 1)
    f.capture.undo()

    f.capture.selection.clear()
    f.capture.selection.add(2)
    f.main.sendCommandEvent(ActionAlign.MoveBackward)
    Swag.require(f.capture.forms[0].buffer == a)
    Swag.require(f.capture.forms[1].buffer == c)
    Swag.require(f.capture.forms[2].buffer == b)
    Swag.require(f.capture.selection[0] == 1)
    f.capture.undo()

    f.capture.selection.clear()
    f.capture.selection.add(0)
    f.main.sendCommandEvent(ActionAlign.SendToFront)
    Swag.require(f.capture.forms[0].buffer == b)
    Swag.require(f.capture.forms[1].buffer == c)
    Swag.require(f.capture.forms[2].buffer == a)
    Swag.require(f.capture.selection[0] == 2)
    f.capture.undo()

    f.capture.selection.clear()
    f.capture.selection.add(2)
    f.main.sendCommandEvent(ActionAlign.SendToBack)
    Swag.require(f.capture.forms[0].buffer == c)
    Swag.require(f.capture.forms[1].buffer == a)
    Swag.require(f.capture.forms[2].buffer == b)
    Swag.require(f.capture.selection[0] == 0)
    f.capture.undo()
}

// File, copy/paste, flatten and small dialog actions expose stable command state
// without executing OS, clipboard or dialog branches.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    var evt = Gui.Testing.commandState(ActionFile.SaveAsImage)
    Swag.require(Gui.Testing.actionUpdate'ActionFile(f.main, ActionFile.SaveAsImage, &evt))
    Swag.require(not evt.disabled)

    evt = Gui.Testing.commandState(ActionFile.CaptureFileLocation)
    Swag.require(Gui.Testing.actionUpdate'ActionFile(f.main, ActionFile.CaptureFileLocation, &evt))
    Swag.require(not evt.disabled)

    evt = Gui.Testing.commandState(ActionFile.UnlinkImage)
    Swag.require(Gui.Testing.actionUpdate'ActionFile(f.main, ActionFile.UnlinkImage, &evt))
    Swag.require(evt.disabled)

    f.capture.linkedImage = "linked.png"
    evt = Gui.Testing.commandState(ActionFile.UnlinkImage)
    Swag.require(Gui.Testing.actionUpdate'ActionFile(f.main, ActionFile.UnlinkImage, &evt))
    Swag.require(not evt.disabled)

    evt = Gui.Testing.commandState(ActionFile.LinkedFileLocation)
    Swag.require(Gui.Testing.actionUpdate'ActionFile(f.main, ActionFile.LinkedFileLocation, &evt))
    Swag.require(not evt.disabled)

    evt = Gui.Testing.commandState(ActionCopyPaste.Copy)
    Swag.require(Gui.Testing.actionUpdate'ActionCopyPaste(f.main, ActionCopyPaste.Copy, &evt))
    Swag.require(evt.disabled)

    let shape = testAddShape(f.capture, 10, 10, 20, 20)
    shape.kind = .Rectangle
    f.capture.selection.add(0)
    evt = Gui.Testing.commandState(ActionCopyPaste.Copy)
    Swag.require(Gui.Testing.actionUpdate'ActionCopyPaste(f.main, ActionCopyPaste.Copy, &evt))
    Swag.require(not evt.disabled)

    evt = Gui.Testing.commandState(ActionFlatten.Flatten)
    Swag.require(Gui.Testing.actionUpdate'ActionFlatten(f.main, ActionFlatten.Flatten, &evt))
    Swag.require(not evt.disabled)
    f.main.sendCommandEvent(ActionFlatten.Flatten)
    Swag.require(f.capture.forms.count == 0)
    Swag.require(f.capture.selection.count == 0)
    Swag.require(f.capture.canUndo())
    f.capture.undo()
    Swag.require(f.capture.forms.count == 1)

    f.capture.selection.clear()
    evt = Gui.Testing.commandState(ActionFlatten.Flatten)
    Swag.require(Gui.Testing.actionUpdate'ActionFlatten(f.main, ActionFlatten.Flatten, &evt))
    Swag.require(evt.disabled)

    evt = Gui.Testing.commandState(ActionFlatten.FlattenAll)
    Swag.require(Gui.Testing.actionUpdate'ActionFlatten(f.main, ActionFlatten.FlattenAll, &evt))
    Swag.require(not evt.disabled)

    f.capture.selection.add(0)
    let image = testAddImage(f.capture, 40, 10, 20, 20)
    image.kind = .Image
    f.capture.selection.clear()
    f.capture.selection.add(1)
    evt = Gui.Testing.commandState(ActionCopyPaste.PasteImageInside)
    Swag.require(Gui.Testing.actionUpdate'ActionCopyPaste(f.main, ActionCopyPaste.PasteImageInside, &evt))
    Swag.require(not evt.hidden)

    f.capture.selection.clear()
    let pixSel = testAddShape(f.capture, 70, 10, 20, 20, .PixSel)
    pixSel.kind = .Rectangle
    f.capture.selection.add(2)
    evt = Gui.Testing.commandState(ActionPixSel.SmartMove)
    Swag.require(Gui.Testing.actionUpdate'ActionPixSel(f.main, ActionPixSel.SmartMove, &evt))
    Swag.require(not evt.disabled)
    Swag.require(not evt.hidden)

    evt = Gui.Testing.commandState(ActionOptions.Options)
    Swag.require(Gui.Testing.actionUpdate'ActionOptions(f.main, ActionOptions.Options, &evt))
    Swag.require(not evt.name.isEmpty())

    evt = Gui.Testing.commandState(ActionAbout.About)
    Swag.require(Gui.Testing.actionUpdate'ActionAbout(f.main, ActionAbout.About, &evt))
    Swag.require(not evt.name.isEmpty())

    evt = Gui.Testing.commandState(ActionQuickStyle.Reset)
    Swag.require(Gui.Testing.actionUpdate'ActionQuickStyle(f.main, ActionQuickStyle.Reset, &evt))
    Swag.require(not evt.name.isEmpty())
}

// FlattenAll command execution is renderer-backed but stays fully in memory.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    let shape = testAddShape(f.capture, 10, 10, 20, 20)
    shape.kind = .Rectangle
    discard testAddText(f.capture, 40, 10, 20, 20)

    f.main.sendCommandEvent(ActionFlatten.FlattenAll)
    Swag.require(f.capture.forms.count == 0)
    Swag.require(f.capture.selection.count == 0)
    Swag.require(f.capture.canUndo())

    f.capture.undo()
    Swag.require(f.capture.forms.count == 2)
}
