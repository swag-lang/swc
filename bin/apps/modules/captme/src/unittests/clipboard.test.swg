#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func captmeTestResetClipboardToImage()
{
    var img = Image.create(1, 1, .BGRA8)
    img.clear()
    Clipboard.addImage(img)
}

// Copy and Cut go through the real Windows clipboard typed-value format, then
// keep the capture undoable after the selected form is removed.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup(registerHeadlessCommands: true)
    captmeTestRegisterIoActions(f.main)
    captmeTestResetClipboardToImage()

    let shape = captmeTestAddShape(f.capture, 10, 20, 30, 40)
    shape.kind = .Rectangle
    f.capture.selection.add(0)
    @assert(@kindof(f.capture.forms[0]) == FormShape)

    f.main.sendCommandEvent(ActionCopyPaste.Copy)

    var copiedPayload: CaptureClipboardForms
    @assert(Clipboard.getTypedValue(&copiedPayload, #typeof(CaptureClipboardForms)))
    @assert(copiedPayload.forms.count == 1)
    @assert(copiedPayload.forms[0].kind == .Shape)
    @assert(copiedPayload.forms[0].shape.kind == .Rectangle)
    @assert(copiedPayload.forms[0].shape.x == 10)
    @assert(copiedPayload.forms[0].shape.y == 20)
    @assert(copiedPayload.forms[0].shape.w == 30)
    @assert(copiedPayload.forms[0].shape.h == 40)

    f.main.sendCommandEvent(ActionCopyPaste.Cut)
    @assert(f.capture.forms.count == 0)
    @assert(f.capture.selection.count == 0)
    @assert(f.capture.canUndo())

    var cutPayload: CaptureClipboardForms
    @assert(Clipboard.getTypedValue(&cutPayload, #typeof(CaptureClipboardForms)))
    @assert(cutPayload.forms.count == 1)
    @assert(cutPayload.forms[0].kind == .Shape)

    f.capture.undo()
    @assert(f.capture.forms.count == 1)
    @assert(f.capture.selection.count == 1)
    @assert(f.capture.selection[0] == 0)

    f.shutdown()
}

// Paste consumes typed Captme forms from the real clipboard and owns them through
// the normal CreateForm undo command.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup(registerHeadlessCommands: true)
    captmeTestRegisterIoActions(f.main)
    captmeTestResetClipboardToImage()

    let shape = captmeTestAddShape(f.capture, 12, 14, 20, 18)
    shape.kind = .RoundRectangle
    f.capture.selection.add(0)
    f.main.sendCommandEvent(ActionCopyPaste.Copy)

    f.capture.paintRect = {0, 0, f.capture.width, f.capture.height}
    f.capture.selection.clear()
    f.main.sendCommandEvent(ActionCopyPaste.Paste)

    @assert(f.capture.forms.count == 2)
    @assert(f.capture.selection.count == 1)
    @assert(f.capture.selection[0] == 1)
    @assert(@kindof(f.capture.forms[1]) == FormShape)
    @assert((cast(*FormShape) @dataof(f.capture.forms[1])).kind == .RoundRectangle)

    f.capture.undo()
    @assert(f.capture.forms.count == 1)

    f.capture.redo()
    @assert(f.capture.forms.count == 2)

    f.shutdown()
}

// Image clipboard paths are covered both as a whole-capture copy and as paste
// targets: a new image form, then replacing the inside image of an existing one.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup(registerHeadlessCommands: true)
    captmeTestRegisterIoActions(f.main)

    f.capture.width = 40
    f.capture.height = 24
    f.capture.backImg = captmeTestIndexedImage(40, 24)
    f.main.sendCommandEvent(ActionCopyPaste.CopyAsImage)

    let copiedImage = Clipboard.getImage()
    @assert(copiedImage.isValid())
    @assert(copiedImage.width == 40)
    @assert(copiedImage.height == 24)

    Clipboard.addImage(captmeTestIndexedImage(11, 7))
    f.capture.paintRect = {0, 0, f.capture.width, f.capture.height}
    f.main.sendCommandEvent(ActionCopyPaste.Paste)

    @assert(f.capture.forms.count == 1)
    @assert(@kindof(f.capture.forms[0]) == FormImage)
    let pastedImage = cast(*FormImage) @dataof(f.capture.forms[0])
    @assert(pastedImage.kind == .Image)
    @assert(pastedImage.image.isValid())
    @assert(pastedImage.image.width == 11)
    @assert(pastedImage.image.height == 7)

    f.capture.undo()
    @assert(f.capture.forms.count == 0)

    let target = captmeTestAddImage(f.capture, 3, 4, 12, 10)
    target.kind = .Image
    target.image = captmeTestIndexedImage(2, 2)
    f.capture.selection.add(0)

    Clipboard.addImage(captmeTestIndexedImage(6, 5))
    f.main.sendCommandEvent(ActionCopyPaste.PasteImageInside)
    @assert(target.image.width == 6)
    @assert(target.image.height == 5)
    @assert(f.capture.canUndo())

    f.capture.undo()
    @assert(target.image.width == 2)
    @assert(target.image.height == 2)

    f.shutdown()
}

