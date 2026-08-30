#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// accept() is generated from the newCmdId scope prefix (see acceptOwnCmdIds): an
// action must accept its own ids and reject those of every other action.
#test
{
    Swag.assert(Gui.Testing.actionAccept'ActionSelection(null, ActionSelection.SelectAll))
    Swag.assert(Gui.Testing.actionAccept'ActionSelection(null, ActionSelection.Freeze))
    Swag.assert(!Gui.Testing.actionAccept'ActionSelection(null, ActionCapture.Area))
    Swag.assert(!Gui.Testing.actionAccept'ActionSelection(null, ActionZoom.ZoomFit))
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
    Swag.assert(f.capture.selection.count == 2)

    f.main.sendCommandEvent(ActionSelection.DeSelectAll)
    Swag.assert(f.capture.selection.count == 0)

    f.main.sendCommandEvent(ActionSelection.DeleteSelection)
    Swag.assert(f.capture.forms.count == 2)
    Swag.assert(!f.capture.canUndo())

    f.capture.selection.add(0)
    f.main.sendCommandEvent(ActionSelection.DeleteSelection)
    Swag.assert(f.capture.forms.count == 1)
    Swag.assert(f.capture.selection.count == 0)
    Swag.assert(f.capture.canUndo())

    f.main.sendCommandEvent(ActionToolMode.Text)
    Swag.assert(f.main.editMode == .Text)

    f.main.sendCommandEvent(ActionView.Clip)
    Swag.assert(f.main.editorOptions.clipToSelection)

    f.main.sendCommandEvent(ActionSelection.Freeze)
    Swag.assert(f.main.freezeSel)
    Swag.assert(f.main.embInfoFreeze != null)
    f.main.sendCommandEvent(ActionSelection.Freeze)
    Swag.assert(!f.main.freezeSel)
    Swag.assert(f.main.embInfoFreeze == null)
}

// Tool-mode actions update checked state and switch every safe editor mode.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    f.main.sendCommandEvent(ActionToolMode.Shape)
    Swag.assert(f.main.editMode == .Shape)
    f.main.sendCommandEvent(ActionToolMode.Line)
    Swag.assert(f.main.editMode == .Line)
    f.main.sendCommandEvent(ActionToolMode.Arrow)
    Swag.assert(f.main.editMode == .Arrow)
    f.main.sendCommandEvent(ActionToolMode.Poly)
    Swag.assert(f.main.editMode == .Polygon)
    f.main.sendCommandEvent(ActionToolMode.Text)
    Swag.assert(f.main.editMode == .Text)
    f.main.sendCommandEvent(ActionToolMode.Draw)
    Swag.assert(f.main.editMode == .Draw)
    f.main.sendCommandEvent(ActionToolMode.Highlight)
    Swag.assert(f.main.editMode == .Highlight)
    f.main.sendCommandEvent(ActionToolMode.Step)
    Swag.assert(f.main.editMode == .Step)
    f.main.sendCommandEvent(ActionToolMode.Img)
    Swag.assert(f.main.editMode == .Image)
    f.main.sendCommandEvent(ActionToolMode.PixSel)
    Swag.assert(f.main.editMode == .PixSel)
    f.main.sendCommandEvent(ActionToolMode.Callout)
    Swag.assert(f.main.editMode == .Callout)
    f.main.sendCommandEvent(ActionToolMode.Favorites)
    Swag.assert(f.main.editMode == .Favorites)
    f.main.sendCommandEvent(ActionToolMode.Selection)
    Swag.assert(f.main.editMode == .Selection)

    var evt = Gui.Testing.commandState(ActionToolMode.Selection)
    Swag.assert(Gui.Testing.actionUpdate'ActionToolMode(f.main, ActionToolMode.Selection, &evt))
    Swag.assert(evt.updatedFields.has(CommandStateEvent.UpdatedFields.Checked))
    Swag.assert(evt.checked)

    evt = Gui.Testing.commandState(ActionToolMode.Text)
    Swag.assert(Gui.Testing.actionUpdate'ActionToolMode(f.main, ActionToolMode.Text, &evt))
    Swag.assert(!evt.checked)
}

// Capture delay, capture-option toggles and view clipping are pure state actions.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    f.main.sendCommandEvent(ActionCaptureDelay.Delay5)
    Swag.assert(f.main.captureOptions.delay == 5)
    var delayEvt = Gui.Testing.commandState(ActionCaptureDelay.Delay)
    Swag.assert(Gui.Testing.actionUpdate'ActionCaptureDelay(f.main, ActionCaptureDelay.Delay, &delayEvt))

    delayEvt = Gui.Testing.commandState(ActionCaptureDelay.Delay5)
    Swag.assert(Gui.Testing.actionUpdate'ActionCaptureDelay(f.main, ActionCaptureDelay.Delay5, &delayEvt))
    Swag.assert(delayEvt.checked)
    Swag.assert(delayEvt.renderingHint.has(CommandStateEvent.RenderingHint.ExclusiveGroup))

    f.main.sendCommandEvent(ActionCaptureDelay.Delay0)
    Swag.assert(f.main.captureOptions.delay == 0)
    f.main.sendCommandEvent(ActionCaptureDelay.Delay1)
    Swag.assert(f.main.captureOptions.delay == 1)
    f.main.sendCommandEvent(ActionCaptureDelay.Delay2)
    Swag.assert(f.main.captureOptions.delay == 2)
    f.main.sendCommandEvent(ActionCaptureDelay.Delay9)
    Swag.assert(f.main.captureOptions.delay == 9)
    delayEvt = Gui.Testing.commandState(ActionCaptureDelay.Delay9)
    Swag.assert(Gui.Testing.actionUpdate'ActionCaptureDelay(f.main, ActionCaptureDelay.Delay9, &delayEvt))
    Swag.assert(delayEvt.checked)

    let hideEditor = f.main.captureOptions.hideEditorBefore
    Swag.assert(Gui.Testing.actionExecute'ActionCapture(f.main, ActionCapture.HideEditor))
    Swag.assert(f.main.captureOptions.hideEditorBefore != hideEditor)

    let captureCursor = f.main.captureOptions.captureCursor
    Swag.assert(Gui.Testing.actionExecute'ActionCapture(f.main, ActionCapture.CaptureCursor))
    Swag.assert(f.main.captureOptions.captureCursor != captureCursor)

    let toInPlace = f.main.captureOptions.inPlaceEdit
    Swag.assert(Gui.Testing.actionExecute'ActionCapture(f.main, ActionCapture.ToInPlace))
    Swag.assert(f.main.captureOptions.inPlaceEdit != toInPlace)

    let toEditor = f.main.captureOptions.sendToEditor
    Swag.assert(Gui.Testing.actionExecute'ActionCapture(f.main, ActionCapture.ToEditor))
    Swag.assert(f.main.captureOptions.sendToEditor != toEditor)

    let toClipboard = f.main.captureOptions.sendToClipboard
    Swag.assert(Gui.Testing.actionExecute'ActionCapture(f.main, ActionCapture.ToClipboard))
    Swag.assert(f.main.captureOptions.sendToClipboard != toClipboard)

    var capEvt = Gui.Testing.commandState(ActionCapture.ToClipboard)
    Swag.assert(Gui.Testing.actionUpdate'ActionCapture(f.main, ActionCapture.ToClipboard, &capEvt))
    Swag.assert(capEvt.updatedFields.has(CommandStateEvent.UpdatedFields.Checked))
    Swag.assert(capEvt.checked == f.main.captureOptions.sendToClipboard)

    let clip = f.main.editorOptions.clipToSelection
    f.main.sendCommandEvent(ActionView.Clip)
    Swag.assert(f.main.editorOptions.clipToSelection != clip)

    var clipEvt = Gui.Testing.commandState(ActionView.Clip)
    Swag.assert(Gui.Testing.actionUpdate'ActionView(f.main, ActionView.Clip, &clipEvt))
    Swag.assert(clipEvt.checked == f.main.editorOptions.clipToSelection)
}

// Zoom actions expose disabled state at clamps and execute without paint.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    f.editView.setZoom(1)
    f.main.sendCommandEvent(ActionZoom.ZoomIn)
    Swag.assert(f.editView.zoom > 1)
    f.main.sendCommandEvent(ActionZoom.ZoomOut)
    Swag.assert(Math.abs(f.editView.zoom - 1) < 0.001)

    f.main.sendCommandEvent(ActionZoom.Zoom1)
    Swag.assert(Math.abs(f.editView.zoom - 1) < 0.001)

    f.main.sendCommandEvent(ActionZoom.ZoomFit)
    Swag.assert(f.editView.zoom > 1)
    f.main.sendCommandEvent(ActionZoom.Zoom1)
    Swag.assert(Math.abs(f.editView.zoom - 1) < 0.001)

    f.editView.setZoom(EditView.MaxZoom + 5)
    Swag.assert(Math.abs(f.editView.zoom - EditView.MaxZoom) < 0.001)
    Swag.assert(!f.editView.canZoomIn())
    var evt = Gui.Testing.commandState(ActionZoom.ZoomIn)
    Swag.assert(Gui.Testing.actionUpdate'ActionZoom(f.main, ActionZoom.ZoomIn, &evt))
    Swag.assert(evt.disabled)

    f.editView.setZoom(EditView.MinZoom - 5)
    Swag.assert(Math.abs(f.editView.zoom - EditView.MinZoom) < 0.001)
    Swag.assert(!f.editView.canZoomOut())
    evt = Gui.Testing.commandState(ActionZoom.ZoomOut)
    Swag.assert(Gui.Testing.actionUpdate'ActionZoom(f.main, ActionZoom.ZoomOut, &evt))
    Swag.assert(evt.disabled)

    evt = Gui.Testing.commandState(ActionZoom.Zoom1)
    Swag.assert(Gui.Testing.actionUpdate'ActionZoom(f.main, ActionZoom.Zoom1, &evt))
    Swag.assert(evt.updatedFields.has(.Icon) and evt.icon.isValid())
    evt = Gui.Testing.commandState(ActionZoom.ZoomFit)
    Swag.assert(Gui.Testing.actionUpdate'ActionZoom(f.main, ActionZoom.ZoomFit, &evt))
    Swag.assert(evt.updatedFields.has(.Icon) and evt.icon.isValid())
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
    Swag.assert(Gui.Testing.actionUpdate'ActionUndo(f.main, ActionUndo.DoUndo, &undoEvt))
    Swag.assert(undoEvt.disabled)

    var evt = Gui.Testing.commandState(ActionEdit.EditText)
    Swag.assert(Gui.Testing.actionUpdate'ActionEdit(f.main, ActionEdit.EditText, &evt))
    Swag.assert(evt.disabled)
    Swag.assert(evt.hidden)

    f.capture.selection.add(0)
    evt = Gui.Testing.commandState(ActionEdit.EditText)
    Swag.assert(Gui.Testing.actionUpdate'ActionEdit(f.main, ActionEdit.EditText, &evt))
    Swag.assert(!evt.disabled)
    Swag.assert(!evt.hidden)

    text.rotate = 25
    evt         = Gui.Testing.commandState(ActionEdit.ResetRotation)
    Swag.assert(Gui.Testing.actionUpdate'ActionEdit(f.main, ActionEdit.ResetRotation, &evt))
    Swag.assert(!evt.disabled)
    Swag.assert(!evt.hidden)
    f.main.sendCommandEvent(ActionEdit.ResetRotation)
    Swag.assert(text.rotate == 0)

    f.capture.selection.clear()
    f.capture.selection.add(1)
    evt = Gui.Testing.commandState(ActionEdit.ClearImageInside)
    Swag.assert(Gui.Testing.actionUpdate'ActionEdit(f.main, ActionEdit.ClearImageInside, &evt))
    Swag.assert(!evt.hidden)
    Swag.assert(evt.disabled)

    image.image = Image.create(2, 2, .BGRA8)
    evt         = Gui.Testing.commandState(ActionEdit.ClearImageInside)
    Swag.assert(Gui.Testing.actionUpdate'ActionEdit(f.main, ActionEdit.ClearImageInside, &evt))
    Swag.assert(!evt.disabled)
    f.main.sendCommandEvent(ActionEdit.ClearImageInside)
    Swag.assert(!image.image.isValid())

    f.capture.selection.clear()
    evt = Gui.Testing.commandState(ActionPixSel.Fill)
    Swag.assert(Gui.Testing.actionUpdate'ActionPixSel(f.main, ActionPixSel.Fill, &evt))
    Swag.assert(evt.disabled)
    Swag.assert(evt.hidden)

    f.capture.selection.add(2)
    evt = Gui.Testing.commandState(ActionPixSel.Fill)
    Swag.assert(Gui.Testing.actionUpdate'ActionPixSel(f.main, ActionPixSel.Fill, &evt))
    Swag.assert(!evt.disabled)
    Swag.assert(!evt.hidden)

    let undo = f.capture.newUndo(.OffsetSelection)
    undo.newPosX = 1
    f.capture.pushUndo(undo)
    evt = Gui.Testing.commandState(ActionUndo.DoUndo)
    Swag.assert(Gui.Testing.actionUpdate'ActionUndo(f.main, ActionUndo.DoUndo, &evt))
    Swag.assert(!evt.disabled)
    f.main.sendCommandEvent(ActionUndo.DoUndo)
    evt = Gui.Testing.commandState(ActionUndo.DoRedo)
    Swag.assert(Gui.Testing.actionUpdate'ActionUndo(f.main, ActionUndo.DoRedo, &evt))
    Swag.assert(!evt.disabled)

    evt = Gui.Testing.commandState(ActionImage.RestoreOrg)
    Swag.assert(Gui.Testing.actionUpdate'ActionImage(f.main, ActionImage.RestoreOrg, &evt))
    Swag.assert(evt.disabled)
    f.capture.backImgOriginal = Image.create(5, 5, .BGRA8)
    evt = Gui.Testing.commandState(ActionImage.RestoreOrg)
    Swag.assert(Gui.Testing.actionUpdate'ActionImage(f.main, ActionImage.RestoreOrg, &evt))
    Swag.assert(!evt.disabled)

    // Image commands stay present when disabled. Only descriptors that explicitly opt into
    // contextual hiding may set Hidden; an omitted aggregate field must never inherit garbage.
    for id in [ActionImage.ResizeImage, ActionImage.ExpandImage, ActionImage.ExpandCapture, ActionImage.TrimCapture, ActionImage.FlipImage, ActionImage.MirrorImage, ActionImage.RotateImageRight, ActionImage.RotateImageLeft]
    {
        evt = Gui.Testing.commandState(id)
        Swag.assert(Gui.Testing.actionUpdate'ActionImage(f.main, id, &evt))
        Swag.assert(!evt.updatedFields.has(.Hidden))
        Swag.assert(!evt.hidden)
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
    Swag.assert(Gui.Testing.actionUpdate'ActionMoveSel(f.main, ActionMoveSel.Right1, &evt))
    Swag.assert(evt.disabled)

    f.capture.selection.add(0)
    f.capture.selection.add(1)
    evt = Gui.Testing.commandState(ActionMoveSel.Right1)
    Swag.assert(Gui.Testing.actionUpdate'ActionMoveSel(f.main, ActionMoveSel.Right1, &evt))
    Swag.assert(!evt.disabled)

    f.main.sendCommandEvent(ActionMoveSel.Left1)
    Swag.assert(a.x == 9)
    Swag.assert(b.x == 49)
    f.main.sendCommandEvent(ActionMoveSel.Top1)
    Swag.assert(a.y == 9)
    Swag.assert(b.y == 39)
    f.main.sendCommandEvent(ActionMoveSel.Right1)
    Swag.assert(a.x == 10)
    Swag.assert(b.x == 50)
    f.main.sendCommandEvent(ActionMoveSel.Bottom1)
    Swag.assert(a.y == 10)
    Swag.assert(b.y == 40)
    f.main.sendCommandEvent(ActionMoveSel.Left)
    Swag.assert(a.x == 5)
    Swag.assert(b.x == 45)
    f.main.sendCommandEvent(ActionMoveSel.Top)
    Swag.assert(a.y == 5)
    Swag.assert(b.y == 35)
    f.main.sendCommandEvent(ActionMoveSel.Right)
    Swag.assert(a.x == 10)
    Swag.assert(b.x == 50)
    f.main.sendCommandEvent(ActionMoveSel.Bottom)
    Swag.assert(a.y == 10)
    Swag.assert(b.y == 40)

    f.capture.undo()
    Swag.assert(a.y == 5)
    Swag.assert(b.y == 35)

    f.capture.redo()
    Swag.assert(a.y == 10)
    Swag.assert(b.y == 40)

    evt = Gui.Testing.commandState(ActionAlign.AlignLeft)
    Swag.assert(Gui.Testing.actionUpdate'ActionAlign(f.main, ActionAlign.AlignLeft, &evt))
    Swag.assert(!evt.disabled)
    f.main.sendCommandEvent(ActionAlign.AlignLeft)
    Swag.assert(a.x == 10)
    Swag.assert(b.x == 10)
    f.capture.undo()
    Swag.assert(a.x == 10)
    Swag.assert(b.x == 50)

    evt = Gui.Testing.commandState(ActionAlign.AlignRight)
    Swag.assert(Gui.Testing.actionUpdate'ActionAlign(f.main, ActionAlign.AlignRight, &evt))
    Swag.assert(!evt.disabled)
    f.main.sendCommandEvent(ActionAlign.AlignRight)
    Swag.assert(a.x == 60)
    Swag.assert(b.x == 50)
    f.capture.undo()
    Swag.assert(a.x == 10)
    Swag.assert(b.x == 50)

    evt = Gui.Testing.commandState(ActionAlign.AlignCenter)
    Swag.assert(Gui.Testing.actionUpdate'ActionAlign(f.main, ActionAlign.AlignCenter, &evt))
    Swag.assert(!evt.disabled)
    f.main.sendCommandEvent(ActionAlign.AlignCenter)
    Swag.assert(a.x == 35)
    Swag.assert(b.x == 30)
    f.capture.undo()
    Swag.assert(a.x == 10)
    Swag.assert(b.x == 50)

    evt = Gui.Testing.commandState(ActionAlign.AlignTop)
    Swag.assert(Gui.Testing.actionUpdate'ActionAlign(f.main, ActionAlign.AlignTop, &evt))
    Swag.assert(!evt.disabled)
    f.main.sendCommandEvent(ActionAlign.AlignTop)
    Swag.assert(a.y == 10)
    Swag.assert(b.y == 10)

    f.capture.undo()
    Swag.assert(a.y == 10)
    Swag.assert(b.y == 40)

    evt = Gui.Testing.commandState(ActionAlign.AlignBottom)
    Swag.assert(Gui.Testing.actionUpdate'ActionAlign(f.main, ActionAlign.AlignBottom, &evt))
    Swag.assert(!evt.disabled)
    f.main.sendCommandEvent(ActionAlign.AlignBottom)
    Swag.assert(a.y == 50)
    Swag.assert(b.y == 40)
    f.capture.undo()
    Swag.assert(a.y == 10)
    Swag.assert(b.y == 40)

    evt = Gui.Testing.commandState(ActionAlign.AlignMiddle)
    Swag.assert(Gui.Testing.actionUpdate'ActionAlign(f.main, ActionAlign.AlignMiddle, &evt))
    Swag.assert(!evt.disabled)
    f.main.sendCommandEvent(ActionAlign.AlignMiddle)
    Swag.assert(a.y == 30)
    Swag.assert(b.y == 25)
    f.capture.undo()
    Swag.assert(a.y == 10)
    Swag.assert(b.y == 40)

    f.capture.selection.clear()
    f.capture.selection.add(1)
    evt = Gui.Testing.commandState(ActionAlign.AlignTop)
    Swag.assert(Gui.Testing.actionUpdate'ActionAlign(f.main, ActionAlign.AlignTop, &evt))
    Swag.assert(evt.disabled)
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
    Swag.assert(f.capture.forms[0].buffer == b)
    Swag.assert(f.capture.forms[1].buffer == a)
    Swag.assert(f.capture.forms[2].buffer == c)
    Swag.assert(f.capture.selection[0] == 1)
    f.capture.undo()

    f.capture.selection.clear()
    f.capture.selection.add(2)
    f.main.sendCommandEvent(ActionAlign.MoveBackward)
    Swag.assert(f.capture.forms[0].buffer == a)
    Swag.assert(f.capture.forms[1].buffer == c)
    Swag.assert(f.capture.forms[2].buffer == b)
    Swag.assert(f.capture.selection[0] == 1)
    f.capture.undo()

    f.capture.selection.clear()
    f.capture.selection.add(0)
    f.main.sendCommandEvent(ActionAlign.SendToFront)
    Swag.assert(f.capture.forms[0].buffer == b)
    Swag.assert(f.capture.forms[1].buffer == c)
    Swag.assert(f.capture.forms[2].buffer == a)
    Swag.assert(f.capture.selection[0] == 2)
    f.capture.undo()

    f.capture.selection.clear()
    f.capture.selection.add(2)
    f.main.sendCommandEvent(ActionAlign.SendToBack)
    Swag.assert(f.capture.forms[0].buffer == c)
    Swag.assert(f.capture.forms[1].buffer == a)
    Swag.assert(f.capture.forms[2].buffer == b)
    Swag.assert(f.capture.selection[0] == 0)
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
    Swag.assert(Gui.Testing.actionUpdate'ActionFile(f.main, ActionFile.SaveAsImage, &evt))
    Swag.assert(!evt.disabled)

    evt = Gui.Testing.commandState(ActionFile.CaptureFileLocation)
    Swag.assert(Gui.Testing.actionUpdate'ActionFile(f.main, ActionFile.CaptureFileLocation, &evt))
    Swag.assert(!evt.disabled)

    evt = Gui.Testing.commandState(ActionFile.UnlinkImage)
    Swag.assert(Gui.Testing.actionUpdate'ActionFile(f.main, ActionFile.UnlinkImage, &evt))
    Swag.assert(evt.disabled)

    f.capture.linkedImage = "linked.png"
    evt = Gui.Testing.commandState(ActionFile.UnlinkImage)
    Swag.assert(Gui.Testing.actionUpdate'ActionFile(f.main, ActionFile.UnlinkImage, &evt))
    Swag.assert(!evt.disabled)

    evt = Gui.Testing.commandState(ActionFile.LinkedFileLocation)
    Swag.assert(Gui.Testing.actionUpdate'ActionFile(f.main, ActionFile.LinkedFileLocation, &evt))
    Swag.assert(!evt.disabled)

    evt = Gui.Testing.commandState(ActionCopyPaste.Copy)
    Swag.assert(Gui.Testing.actionUpdate'ActionCopyPaste(f.main, ActionCopyPaste.Copy, &evt))
    Swag.assert(evt.disabled)

    let shape = testAddShape(f.capture, 10, 10, 20, 20)
    shape.kind = .Rectangle
    f.capture.selection.add(0)
    evt = Gui.Testing.commandState(ActionCopyPaste.Copy)
    Swag.assert(Gui.Testing.actionUpdate'ActionCopyPaste(f.main, ActionCopyPaste.Copy, &evt))
    Swag.assert(!evt.disabled)

    evt = Gui.Testing.commandState(ActionFlatten.Flatten)
    Swag.assert(Gui.Testing.actionUpdate'ActionFlatten(f.main, ActionFlatten.Flatten, &evt))
    Swag.assert(!evt.disabled)
    f.main.sendCommandEvent(ActionFlatten.Flatten)
    Swag.assert(f.capture.forms.count == 0)
    Swag.assert(f.capture.selection.count == 0)
    Swag.assert(f.capture.canUndo())
    f.capture.undo()
    Swag.assert(f.capture.forms.count == 1)

    f.capture.selection.clear()
    evt = Gui.Testing.commandState(ActionFlatten.Flatten)
    Swag.assert(Gui.Testing.actionUpdate'ActionFlatten(f.main, ActionFlatten.Flatten, &evt))
    Swag.assert(evt.disabled)

    evt = Gui.Testing.commandState(ActionFlatten.FlattenAll)
    Swag.assert(Gui.Testing.actionUpdate'ActionFlatten(f.main, ActionFlatten.FlattenAll, &evt))
    Swag.assert(!evt.disabled)

    f.capture.selection.add(0)
    let image = testAddImage(f.capture, 40, 10, 20, 20)
    image.kind = .Image
    f.capture.selection.clear()
    f.capture.selection.add(1)
    evt = Gui.Testing.commandState(ActionCopyPaste.PasteImageInside)
    Swag.assert(Gui.Testing.actionUpdate'ActionCopyPaste(f.main, ActionCopyPaste.PasteImageInside, &evt))
    Swag.assert(!evt.hidden)

    f.capture.selection.clear()
    let pixSel = testAddShape(f.capture, 70, 10, 20, 20, .PixSel)
    pixSel.kind = .Rectangle
    f.capture.selection.add(2)
    evt = Gui.Testing.commandState(ActionPixSel.SmartMove)
    Swag.assert(Gui.Testing.actionUpdate'ActionPixSel(f.main, ActionPixSel.SmartMove, &evt))
    Swag.assert(!evt.disabled)
    Swag.assert(!evt.hidden)

    evt = Gui.Testing.commandState(ActionOptions.Options)
    Swag.assert(Gui.Testing.actionUpdate'ActionOptions(f.main, ActionOptions.Options, &evt))
    Swag.assert(!evt.name.isEmpty())

    evt = Gui.Testing.commandState(ActionAbout.About)
    Swag.assert(Gui.Testing.actionUpdate'ActionAbout(f.main, ActionAbout.About, &evt))
    Swag.assert(!evt.name.isEmpty())

    evt = Gui.Testing.commandState(ActionQuickStyle.Reset)
    Swag.assert(Gui.Testing.actionUpdate'ActionQuickStyle(f.main, ActionQuickStyle.Reset, &evt))
    Swag.assert(!evt.name.isEmpty())

    discard shape
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
    Swag.assert(f.capture.forms.count == 0)
    Swag.assert(f.capture.selection.count == 0)
    Swag.assert(f.capture.canUndo())

    f.capture.undo()
    Swag.assert(f.capture.forms.count == 2)
}
