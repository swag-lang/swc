#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func testSetClipboardImage(width, height: s32)
{
    Clipboard.addImage(Gui.Testing.indexedImage(width, height))
    Swag.assert(Clipboard.hasImage())
}

func testResetClipboardToImage()
{
    var img = Image.create(1, 1, .BGRA8)
    img.clear()
    Clipboard.addImage(img)
}

// Copy and Cut go through the clipboard typed-value format (the process-local fake
// under the headless host), then keep the capture undoable after the selected form
// is removed.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)
    testResetClipboardToImage()

    let shape = testAddShape(f.capture, 10, 20, 30, 40)
    shape.kind = .Rectangle
    f.capture.selection.add(0)
    Swag.assert(Swag.kindOf(f.capture.forms[0]) == FormShape)

    f.main.sendCommandEvent(ActionCopyPaste.Copy)

    var copiedPayload: CaptureClipboardForms
    Swag.assert(Clipboard.getTypedValue(&copiedPayload, #typeof(CaptureClipboardForms)))
    Swag.assert(copiedPayload.forms.count == 1)
    Swag.assert(copiedPayload.forms[0].kind == .Shape)
    Swag.assert(copiedPayload.forms[0].shape.kind == .Rectangle)
    Swag.assert(copiedPayload.forms[0].shape.x == 10)
    Swag.assert(copiedPayload.forms[0].shape.y == 20)
    Swag.assert(copiedPayload.forms[0].shape.w == 30)
    Swag.assert(copiedPayload.forms[0].shape.h == 40)

    f.main.sendCommandEvent(ActionCopyPaste.Cut)
    Swag.assert(f.capture.forms.count == 0)
    Swag.assert(f.capture.selection.count == 0)
    Swag.assert(f.capture.canUndo())

    var cutPayload: CaptureClipboardForms
    Swag.assert(Clipboard.getTypedValue(&cutPayload, #typeof(CaptureClipboardForms)))
    Swag.assert(cutPayload.forms.count == 1)
    Swag.assert(cutPayload.forms[0].kind == .Shape)

    f.capture.undo()
    Swag.assert(f.capture.forms.count == 1)
    Swag.assert(f.capture.selection.count == 1)
    Swag.assert(f.capture.selection[0] == 0)
}

// Paste consumes typed sSnapForge forms from the clipboard and owns them through
// the normal CreateForm undo command.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)
    testResetClipboardToImage()

    let shape = testAddShape(f.capture, 12, 14, 20, 18)
    shape.kind = .RoundRectangle
    f.capture.selection.add(0)
    f.main.sendCommandEvent(ActionCopyPaste.Copy)

    f.capture.paintRect = {0, 0, f.capture.width, f.capture.height}
    f.capture.selection.clear()
    f.main.sendCommandEvent(ActionCopyPaste.Paste)

    Swag.assert(f.capture.forms.count == 2)
    Swag.assert(f.capture.selection.count == 1)
    Swag.assert(f.capture.selection[0] == 1)
    Swag.assert(Swag.kindOf(f.capture.forms[1]) == FormShape)
    Swag.assert((cast(*FormShape) f.capture.forms[1].buffer).kind == .RoundRectangle)

    f.capture.undo()
    Swag.assert(f.capture.forms.count == 1)

    f.capture.redo()
    Swag.assert(f.capture.forms.count == 2)
}

// Image clipboard paths are covered both as a whole-capture copy and as paste
// targets: a new image form, then replacing the inside image of an existing one.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)
    testResetClipboardToImage()

    f.capture.width   = 40
    f.capture.height  = 24
    f.capture.backImg = Gui.Testing.indexedImage(40, 24)
    f.main.sendCommandEvent(ActionCopyPaste.CopyAsImage)

    let copiedImage = Clipboard.getImage()
    Swag.assert(copiedImage.isValid())
    Swag.assert(copiedImage.width == 40)
    Swag.assert(copiedImage.height == 24)

    testSetClipboardImage(11, 7)
    f.capture.paintRect = {0, 0, f.capture.width, f.capture.height}
    f.main.sendCommandEvent(ActionCopyPaste.Paste)

    Swag.assert(f.capture.forms.count == 1)
    Swag.assert(Swag.kindOf(f.capture.forms[0]) == FormImage)
    let pastedImage = cast(*FormImage) f.capture.forms[0].buffer
    Swag.assert(pastedImage.kind == .Image)
    Swag.assert(pastedImage.image.isValid())
    Swag.assert(pastedImage.image.width == 11)
    Swag.assert(pastedImage.image.height == 7)

    f.capture.undo()
    Swag.assert(f.capture.forms.count == 0)

    let target = testAddImage(f.capture, 3, 4, 12, 10)
    target.kind  = .Image
    target.image = Gui.Testing.indexedImage(2, 2)
    f.capture.selection.add(0)

    testSetClipboardImage(6, 5)
    f.main.sendCommandEvent(ActionCopyPaste.PasteImageInside)
    Swag.assert(target.image.width == 6)
    Swag.assert(target.image.height == 5)
    Swag.assert(f.capture.canUndo())

    f.capture.undo()
    Swag.assert(target.image.width == 2)
    Swag.assert(target.image.height == 2)
}
