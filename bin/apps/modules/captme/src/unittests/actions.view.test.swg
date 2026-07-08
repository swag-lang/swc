#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// accept() is generated from the newCmdId scope prefix (see acceptOwnCmdIds): an
// action must accept its own ids and reject those of every other action.
#test
{
    let act = @mkinterface(null, #typeof(ActionSelection), IActionUI)
    @assert(act.accept({null, ActionSelection.SelectAll}))
    @assert(act.accept({null, ActionSelection.Freeze}))
    @assert(!act.accept({null, ActionCapture.Area}))
    @assert(!act.accept({null, ActionZoom.ZoomFit}))
}

// Tool-mode actions update checked state and switch every safe editor mode.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    @assert(captmeTestActionExecute'ActionToolMode(f.main, ActionToolMode.Shape))
    @assert(f.main.editMode == .Shape)
    @assert(captmeTestActionExecute'ActionToolMode(f.main, ActionToolMode.Line))
    @assert(f.main.editMode == .Line)
    @assert(captmeTestActionExecute'ActionToolMode(f.main, ActionToolMode.Arrow))
    @assert(f.main.editMode == .Arrow)
    @assert(captmeTestActionExecute'ActionToolMode(f.main, ActionToolMode.Poly))
    @assert(f.main.editMode == .Polygon)
    @assert(captmeTestActionExecute'ActionToolMode(f.main, ActionToolMode.Text))
    @assert(f.main.editMode == .Text)
    @assert(captmeTestActionExecute'ActionToolMode(f.main, ActionToolMode.Draw))
    @assert(f.main.editMode == .Draw)
    @assert(captmeTestActionExecute'ActionToolMode(f.main, ActionToolMode.Highlight))
    @assert(f.main.editMode == .Highlight)
    @assert(captmeTestActionExecute'ActionToolMode(f.main, ActionToolMode.Step))
    @assert(f.main.editMode == .Step)
    @assert(captmeTestActionExecute'ActionToolMode(f.main, ActionToolMode.Img))
    @assert(f.main.editMode == .Image)
    @assert(captmeTestActionExecute'ActionToolMode(f.main, ActionToolMode.PixSel))
    @assert(f.main.editMode == .PixSel)
    @assert(captmeTestActionExecute'ActionToolMode(f.main, ActionToolMode.Favorites))
    @assert(f.main.editMode == .Favorites)
    @assert(captmeTestActionExecute'ActionToolMode(f.main, ActionToolMode.Selection))
    @assert(f.main.editMode == .Selection)

    var evt = captmeTestState(ActionToolMode.Selection)
    @assert(captmeTestActionUpdate'ActionToolMode(f.main, ActionToolMode.Selection, &evt))
    @assert(evt.setFlags.has(CommandStateEvent.SetFlags.Checked))
    @assert(evt.checked)

    evt = captmeTestState(ActionToolMode.Text)
    @assert(captmeTestActionUpdate'ActionToolMode(f.main, ActionToolMode.Text, &evt))
    @assert(!evt.checked)

    f.shutdown()
}

// Capture delay, capture-option toggles and view clipping are pure state actions.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    @assert(captmeTestActionExecute'ActionCaptureDelay(f.main, ActionCaptureDelay.Delay5))
    @assert(f.main.captureOptions.delay == 5)
    var delayEvt = captmeTestState(ActionCaptureDelay.Delay)
    @assert(captmeTestActionUpdate'ActionCaptureDelay(f.main, ActionCaptureDelay.Delay, &delayEvt))
    @assert(delayEvt.name == "Delay Before Capture (5 seconds)")

    delayEvt = captmeTestState(ActionCaptureDelay.Delay5)
    @assert(captmeTestActionUpdate'ActionCaptureDelay(f.main, ActionCaptureDelay.Delay5, &delayEvt))
    @assert(delayEvt.checked)
    @assert(delayEvt.renderingHint.has(CommandStateEvent.RenderingHint.ExclusiveGroup))

    let hideEditor = f.main.captureOptions.hideEditorBefore
    @assert(captmeTestActionExecute'ActionCapture(f.main, ActionCapture.HideEditor))
    @assert(f.main.captureOptions.hideEditorBefore != hideEditor)

    let captureCursor = f.main.captureOptions.captureCursor
    @assert(captmeTestActionExecute'ActionCapture(f.main, ActionCapture.CaptureCursor))
    @assert(f.main.captureOptions.captureCursor != captureCursor)

    let toInPlace = f.main.captureOptions.inPlaceEdit
    @assert(captmeTestActionExecute'ActionCapture(f.main, ActionCapture.ToInPlace))
    @assert(f.main.captureOptions.inPlaceEdit != toInPlace)

    let toEditor = f.main.captureOptions.sendToEditor
    @assert(captmeTestActionExecute'ActionCapture(f.main, ActionCapture.ToEditor))
    @assert(f.main.captureOptions.sendToEditor != toEditor)

    let toClipboard = f.main.captureOptions.sendToClipboard
    @assert(captmeTestActionExecute'ActionCapture(f.main, ActionCapture.ToClipboard))
    @assert(f.main.captureOptions.sendToClipboard != toClipboard)

    var capEvt = captmeTestState(ActionCapture.ToClipboard)
    @assert(captmeTestActionUpdate'ActionCapture(f.main, ActionCapture.ToClipboard, &capEvt))
    @assert(capEvt.setFlags.has(CommandStateEvent.SetFlags.Checked))
    @assert(capEvt.checked == f.main.captureOptions.sendToClipboard)

    let clip = f.main.editorOptions.clipToSelection
    @assert(captmeTestActionExecute'ActionView(f.main, ActionView.Clip))
    @assert(f.main.editorOptions.clipToSelection != clip)

    var clipEvt = captmeTestState(ActionView.Clip)
    @assert(captmeTestActionUpdate'ActionView(f.main, ActionView.Clip, &clipEvt))
    @assert(clipEvt.checked == f.main.editorOptions.clipToSelection)

    f.shutdown()
}

// Zoom actions expose disabled state at clamps and execute without paint.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    f.editView.setZoom(1)
    @assert(captmeTestActionExecute'ActionZoom(f.main, ActionZoom.ZoomIn))
    @assert(f.editView.zoom > 1)
    @assert(captmeTestActionExecute'ActionZoom(f.main, ActionZoom.ZoomOut))
    @assert(Math.abs(f.editView.zoom - 1) < 0.001)

    @assert(captmeTestActionExecute'ActionZoom(f.main, ActionZoom.Zoom1))
    @assert(Math.abs(f.editView.zoom - 1) < 0.001)

    f.editView.setZoom(EditView.MaxZoom + 5)
    @assert(Math.abs(f.editView.zoom - EditView.MaxZoom) < 0.001)
    @assert(!f.editView.canZoomIn())
    var evt = captmeTestState(ActionZoom.ZoomIn)
    @assert(captmeTestActionUpdate'ActionZoom(f.main, ActionZoom.ZoomIn, &evt))
    @assert(evt.disabled)

    f.editView.setZoom(EditView.MinZoom - 5)
    @assert(Math.abs(f.editView.zoom - EditView.MinZoom) < 0.001)
    @assert(!f.editView.canZoomOut())
    evt = captmeTestState(ActionZoom.ZoomOut)
    @assert(captmeTestActionUpdate'ActionZoom(f.main, ActionZoom.ZoomOut, &evt))
    @assert(evt.disabled)

    f.shutdown()
}

// Edit, pixsel, image and undo actions report enabled/hidden state from current selection.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    let text = captmeTestAddText(f.capture, 0, 0, 40, 20)
    let image = captmeTestAddImage(f.capture, 50, 0, 20, 20)
    let pixSel = captmeTestAddShape(f.capture, 80, 0, 20, 20, .PixSel)
    pixSel.kind = .Rectangle

    var undoEvt = captmeTestState(ActionUndo.DoUndo)
    @assert(captmeTestActionUpdate'ActionUndo(f.main, ActionUndo.DoUndo, &undoEvt))
    @assert(undoEvt.disabled)

    var evt = captmeTestState(ActionEdit.EditText)
    @assert(captmeTestActionUpdate'ActionEdit(f.main, ActionEdit.EditText, &evt))
    @assert(evt.disabled)
    @assert(evt.hidden)

    f.capture.selection.add(0)
    evt = captmeTestState(ActionEdit.EditText)
    @assert(captmeTestActionUpdate'ActionEdit(f.main, ActionEdit.EditText, &evt))
    @assert(!evt.disabled)
    @assert(!evt.hidden)

    text.rotate = 25
    evt = captmeTestState(ActionEdit.ResetRotation)
    @assert(captmeTestActionUpdate'ActionEdit(f.main, ActionEdit.ResetRotation, &evt))
    @assert(!evt.disabled)
    @assert(!evt.hidden)
    @assert(captmeTestActionExecute'ActionEdit(f.main, ActionEdit.ResetRotation))
    @assert(text.rotate == 0)

    f.capture.selection.clear()
    f.capture.selection.add(1)
    evt = captmeTestState(ActionEdit.ClearImageInside)
    @assert(captmeTestActionUpdate'ActionEdit(f.main, ActionEdit.ClearImageInside, &evt))
    @assert(!evt.hidden)
    @assert(evt.disabled)

    image.image = Image.create(2, 2, .BGRA8)
    evt = captmeTestState(ActionEdit.ClearImageInside)
    @assert(captmeTestActionUpdate'ActionEdit(f.main, ActionEdit.ClearImageInside, &evt))
    @assert(!evt.disabled)

    f.capture.selection.clear()
    evt = captmeTestState(ActionPixSel.Fill)
    @assert(captmeTestActionUpdate'ActionPixSel(f.main, ActionPixSel.Fill, &evt))
    @assert(evt.disabled)
    @assert(evt.hidden)

    f.capture.selection.add(2)
    evt = captmeTestState(ActionPixSel.Fill)
    @assert(captmeTestActionUpdate'ActionPixSel(f.main, ActionPixSel.Fill, &evt))
    @assert(!evt.disabled)
    @assert(!evt.hidden)

    let undo = f.capture.newUndo(.OffsetSelection)
    undo.newPosX = 1
    f.capture.pushUndo(undo)
    evt = captmeTestState(ActionUndo.DoUndo)
    @assert(captmeTestActionUpdate'ActionUndo(f.main, ActionUndo.DoUndo, &evt))
    @assert(!evt.disabled)
    @assert(captmeTestActionExecute'ActionUndo(f.main, ActionUndo.DoUndo))
    evt = captmeTestState(ActionUndo.DoRedo)
    @assert(captmeTestActionUpdate'ActionUndo(f.main, ActionUndo.DoRedo, &evt))
    @assert(!evt.disabled)

    evt = captmeTestState(ActionImage.RestoreOrg)
    @assert(captmeTestActionUpdate'ActionImage(f.main, ActionImage.RestoreOrg, &evt))
    @assert(evt.disabled)
    f.capture.backImgOriginal = Image.create(5, 5, .BGRA8)
    evt = captmeTestState(ActionImage.RestoreOrg)
    @assert(captmeTestActionUpdate'ActionImage(f.main, ActionImage.RestoreOrg, &evt))
    @assert(!evt.disabled)

    f.shutdown()
}

// Nudge and move-selection command actions integrate with undo and command-state disabling.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    let a = captmeTestAddShape(f.capture, 10, 10, 10, 10)
    let b = captmeTestAddShape(f.capture, 50, 40, 20, 20)

    var evt = captmeTestState(ActionMoveSel.Right1)
    @assert(captmeTestActionUpdate'ActionMoveSel(f.main, ActionMoveSel.Right1, &evt))
    @assert(evt.disabled)

    f.capture.selection.add(0)
    f.capture.selection.add(1)
    evt = captmeTestState(ActionMoveSel.Right1)
    @assert(captmeTestActionUpdate'ActionMoveSel(f.main, ActionMoveSel.Right1, &evt))
    @assert(!evt.disabled)
    @assert(captmeTestActionExecute'ActionMoveSel(f.main, ActionMoveSel.Right1))
    @assert(a.x == 11)
    @assert(b.x == 51)

    evt = captmeTestState(ActionAlign.AlignTop)
    @assert(captmeTestActionUpdate'ActionAlign(f.main, ActionAlign.AlignTop, &evt))
    @assert(!evt.disabled)
    @assert(captmeTestActionExecute'ActionAlign(f.main, ActionAlign.AlignTop))
    @assert(a.y == 10)
    @assert(b.y == 10)

    f.capture.undo()
    @assert(a.y == 10)
    @assert(b.y == 40)

    f.capture.selection.clear()
    f.capture.selection.add(1)
    evt = captmeTestState(ActionAlign.AlignTop)
    @assert(captmeTestActionUpdate'ActionAlign(f.main, ActionAlign.AlignTop, &evt))
    @assert(evt.disabled)

    f.shutdown()
}

// File, copy/paste, flatten and small dialog actions expose stable command state
// without executing OS, clipboard or dialog branches.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    var evt = captmeTestState(ActionFile.SaveAsImage)
    @assert(captmeTestActionUpdate'ActionFile(f.main, ActionFile.SaveAsImage, &evt))
    @assert(!evt.disabled)

    evt = captmeTestState(ActionFile.UnlinkImage)
    @assert(captmeTestActionUpdate'ActionFile(f.main, ActionFile.UnlinkImage, &evt))
    @assert(evt.disabled)

    f.capture.linkedImage = "linked.png"
    evt = captmeTestState(ActionFile.UnlinkImage)
    @assert(captmeTestActionUpdate'ActionFile(f.main, ActionFile.UnlinkImage, &evt))
    @assert(!evt.disabled)

    evt = captmeTestState(ActionFile.LinkedFileLocation)
    @assert(captmeTestActionUpdate'ActionFile(f.main, ActionFile.LinkedFileLocation, &evt))
    @assert(!evt.disabled)

    evt = captmeTestState(ActionCopyPaste.Copy)
    @assert(captmeTestActionUpdate'ActionCopyPaste(f.main, ActionCopyPaste.Copy, &evt))
    @assert(evt.disabled)

    let shape = captmeTestAddShape(f.capture, 10, 10, 20, 20)
    f.capture.selection.add(0)
    evt = captmeTestState(ActionCopyPaste.Copy)
    @assert(captmeTestActionUpdate'ActionCopyPaste(f.main, ActionCopyPaste.Copy, &evt))
    @assert(!evt.disabled)

    evt = captmeTestState(ActionFlatten.Flatten)
    @assert(captmeTestActionUpdate'ActionFlatten(f.main, ActionFlatten.Flatten, &evt))
    @assert(!evt.disabled)

    f.capture.selection.clear()
    evt = captmeTestState(ActionFlatten.Flatten)
    @assert(captmeTestActionUpdate'ActionFlatten(f.main, ActionFlatten.Flatten, &evt))
    @assert(evt.disabled)

    evt = captmeTestState(ActionFlatten.FlattenAll)
    @assert(captmeTestActionUpdate'ActionFlatten(f.main, ActionFlatten.FlattenAll, &evt))
    @assert(!evt.disabled)

    f.capture.selection.add(0)
    let image = captmeTestAddImage(f.capture, 40, 10, 20, 20)
    image.kind = .Image
    f.capture.selection.clear()
    f.capture.selection.add(1)
    evt = captmeTestState(ActionCopyPaste.PasteImageInside)
    @assert(captmeTestActionUpdate'ActionCopyPaste(f.main, ActionCopyPaste.PasteImageInside, &evt))
    @assert(!evt.hidden)

    f.capture.selection.clear()
    let pixSel = captmeTestAddShape(f.capture, 70, 10, 20, 20, .PixSel)
    pixSel.kind = .Rectangle
    f.capture.selection.add(2)
    evt = captmeTestState(ActionPixSel.SmartMove)
    @assert(captmeTestActionUpdate'ActionPixSel(f.main, ActionPixSel.SmartMove, &evt))
    @assert(!evt.disabled)
    @assert(!evt.hidden)

    evt = captmeTestState(ActionOptions.Options)
    @assert(captmeTestActionUpdate'ActionOptions(f.main, ActionOptions.Options, &evt))
    @assert(evt.name == "Options...")

    evt = captmeTestState(ActionAbout.About)
    @assert(captmeTestActionUpdate'ActionAbout(f.main, ActionAbout.About, &evt))
    @assert(evt.name == "About...")

    evt = captmeTestState(ActionQuickStyle.Reset)
    @assert(captmeTestActionUpdate'ActionQuickStyle(f.main, ActionQuickStyle.Reset, &evt))
    @assert(evt.name == "Restore Default Styles")

    discard shape
    f.shutdown()
}

// Library actions can be exercised against an empty headless library window:
// sorting/filtering and command states do not require scanning the user's files.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup()

    f.main.libWnd = Wnd.create'LibraryWnd(f.main, {0, 0, 500, 400})
    f.main.libWnd.main = f.main
    f.main.libWnd.view = Wnd.create'LibraryView(f.main.libWnd, {0, 0, 500, 400})
    f.main.libWnd.view.libWnd = f.main.libWnd
    f.main.libWnd.view.mainWnd = f.main
    let libWnd = cast(*Wnd) f.main.libWnd

    var evt = captmeTestState(ActionLibSort.Recent)
    @assert(captmeTestActionUpdateWnd'ActionLibSort(libWnd, ActionLibSort.Recent, &evt))
    @assert(evt.checked)

    @assert(captmeTestActionExecuteWnd'ActionLibSort(libWnd, ActionLibSort.FileSize))
    @assert(f.main.libWnd.sortMethod == .FileSize)

    evt = captmeTestState(ActionLibSort.Invert)
    @assert(captmeTestActionUpdateWnd'ActionLibSort(libWnd, ActionLibSort.Invert, &evt))
    @assert(evt.name == "Smaller First")
    @assert(!evt.disabled)

    @assert(captmeTestActionExecuteWnd'ActionLibSort(libWnd, ActionLibSort.Invert))
    @assert(f.main.libWnd.invertSort)

    @assert(captmeTestActionExecuteWnd'ActionLibSort(libWnd, ActionLibSort.Similar))
    evt = captmeTestState(ActionLibSort.Invert)
    @assert(captmeTestActionUpdateWnd'ActionLibSort(libWnd, ActionLibSort.Invert, &evt))
    @assert(evt.disabled)

    evt = captmeTestState(ActionLibFilter.LinkedImage)
    @assert(captmeTestActionUpdateWnd'ActionLibFilter(libWnd, ActionLibFilter.LinkedImage, &evt))
    @assert(evt.checked)
    @assert(captmeTestActionExecuteWnd'ActionLibFilter(libWnd, ActionLibFilter.LinkedImage))
    @assert(!f.main.libWnd.showLinkedImage)

    evt = captmeTestState(ActionLibSel.Right)
    @assert(captmeTestActionUpdateWnd'ActionLibSel(libWnd, ActionLibSel.Right, &evt))
    @assert(evt.disabled)

    f.main.libWnd.view.focusItem = 0
    evt = captmeTestState(ActionLibSel.Right)
    @assert(captmeTestActionUpdateWnd'ActionLibSel(libWnd, ActionLibSel.Right, &evt))
    @assert(!evt.disabled)

    f.shutdown()
}

// Gizmo rotation math stays stable without painting.
#test
{
    var g: GizmoRect
    g.rect = {10, 20, 100, 50}

    @assert(Math.abs(g.computeRotate({60, -10}) - 0) < 0.001)
    @assert(Math.abs(g.computeRotate({110, 45}) - 90) < 0.001)
    @assert(Math.abs(g.computeRotate({60, 100}) - 180) < 0.001)
    @assert(Math.abs(g.computeRotate({10, 45}) - 270) < 0.001)

    @assert(g.toLocal({110, 45}) == Math.Point{110, 45})

    g.rotateEnabled = true
    g.rotateValue = 90
    let local = g.toLocal({110, 45})
    @assert(Math.abs(local.x - 60) < 0.001)
    @assert(Math.abs(local.y + 5) < 0.001)

    let rotated = GizmoRect.rotateVec({10, 0}, Math.toRadians(90.0'f32))
    @assert(Math.abs(rotated.x) < 0.001)
    @assert(Math.abs(rotated.y - 10) < 0.001)
}
