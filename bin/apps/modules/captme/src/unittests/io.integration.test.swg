#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, File

func captmeTestResetClipboardToImage()
{
    var img = Image.create(1, 1, .BGRA8)
    img.clear()
    Clipboard.addImage(img)
}

func captmeTestRegisterIoActions(main: *MainWnd)
{
    main.registerAction'ActionCopyPaste()
    main.registerAction'ActionFile()
    main.registerAction'ActionCapture()
}

func captmeTestPrepareSavedCapture(capture: *Capture)->String
{
    let path = captmeTestTempCapturePath()
    capture.file    = path
    capture.changed = true

    catch capture.save()
    @assert(@err == null)
    @assert(File.exists(path))
    return path
}

func captmeTestHasCaptmeFileMetadata(img: Image, captureFile: string)->bool
{
    foreach md in img.metaDatas
    {
        if md.isTag("Captme.File")
        {
            var value = String.from(cast(string) md.toSlice())
            var expected = String.from(captureFile)
            Path.normalize(&value)
            Path.normalize(&expected)
            if Path.equals(value.toString(), expected.toString()) do
                return true
        }
    }

    return false
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

// Save As Image writes a real PNG that can be loaded back with Captme metadata.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup(registerHeadlessCommands: true)
    captmeTestRegisterIoActions(f.main)

    f.capture.width = 32
    f.capture.height = 20
    f.capture.backImg = captmeTestIndexedImage(32, 20)

    let capturePath = captmeTestPrepareSavedCapture(f.capture)
    defer { discard catch File.delete(capturePath) }

    let pngPath = captmeTestTempFilePath(".png")
    defer { discard catch File.delete(pngPath) }

    f.main.doSaveAsImage(pngPath)
    f.gui.pump()

    @assert(File.exists(pngPath))

    let saved = catch Image.load(pngPath)
    @assert(@err == null)
    @assert(saved.isValid())
    @assert(saved.width == 32)
    @assert(saved.height == 20)
    @assert(saved.metaDatas.count > 0)
    @assert(captmeTestHasCaptmeFileMetadata(saved, capturePath))

    f.shutdown()
}

// Save As Linked Image persists the linked file association into the capture file.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup(registerHeadlessCommands: true)
    captmeTestRegisterIoActions(f.main)

    f.capture.width = 28
    f.capture.height = 18
    f.capture.backImg = captmeTestIndexedImage(28, 18)

    let capturePath = captmeTestPrepareSavedCapture(f.capture)
    defer { discard catch File.delete(capturePath) }

    let linkedPath = captmeTestTempFilePath(".png")
    defer { discard catch File.delete(linkedPath) }

    f.main.doSaveAsImage(linkedPath, linked: true)
    f.gui.pump()

    @assert(File.exists(linkedPath))
    @assert(f.capture.linkedImage == linkedPath)
    @assert(f.capture.linkedUpToDate)

    let loaded = catch Capture.load(capturePath)
    @assert(@err == null)
    defer { Memory.delete(loaded) }

    @assert(loaded.linkedImage == linkedPath)
    @assert(loaded.linkedUpToDate)

    f.shutdown()
}

// Updating an existing linked image avoids the file dialog and still exercises
// real PNG output plus capture-file persistence.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup(registerHeadlessCommands: true)
    captmeTestRegisterIoActions(f.main)

    f.capture.width = 26
    f.capture.height = 16
    f.capture.backImg = captmeTestIndexedImage(26, 16)

    let capturePath = captmeTestPrepareSavedCapture(f.capture)
    defer { discard catch File.delete(capturePath) }

    let linkedPath = captmeTestTempFilePath(".png")
    defer { discard catch File.delete(linkedPath) }

    f.capture.linkedImage = linkedPath
    f.capture.linkedUpToDate = false
    f.main.editorOptions.confirmLinkedOverwrite = false

    f.main.sendCommandEvent(ActionFile.UpdateLinkedImage)
    f.gui.pump()

    @assert(File.exists(linkedPath))
    @assert(f.capture.linkedUpToDate)

    let linked = catch Image.load(linkedPath)
    @assert(@err == null)
    @assert(linked.isValid())
    @assert(linked.width == 26)
    @assert(linked.height == 16)
    @assert(captmeTestHasCaptmeFileMetadata(linked, capturePath))

    let loaded = catch Capture.load(capturePath)
    @assert(@err == null)
    defer { Memory.delete(loaded) }

    @assert(loaded.linkedImage == linkedPath)
    @assert(loaded.linkedUpToDate)

    f.shutdown()
}

// File Details opens a real modal dialog after reading the saved capture size
// from disk; the headless modal helper closes it through the normal OK button.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup(registerHeadlessCommands: true)
    captmeTestRegisterIoActions(f.main)

    let capturePath = captmeTestPrepareSavedCapture(f.capture)
    defer { discard catch File.delete(capturePath) }

    var didClick: bool
    f.gui.app.sigFrame += func|host = &f.gui, didClick = &didClick|(app)
    {
        if !dref didClick
        {
            @assert(host.clickModalButton(Dialog.BtnOk))
            dref didClick = true
        }
    }

    f.main.sendCommandEvent(ActionFile.FileDetails)
    f.gui.pump()

    @assert(didClick)
    @assert(f.gui.app.surfaces.count == 0)

    f.shutdown()
}

// Full-screen OS capture is tested without creating a Captme library file:
// sendToEditor=false keeps the result in the real clipboard only.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup(registerHeadlessCommands: true)
    captmeTestRegisterIoActions(f.main)

    f.main.captureOptions.hideEditorBefore = false
    f.main.captureOptions.captureCursor = false
    f.main.captureOptions.sendToClipboard = true
    f.main.captureOptions.sendToEditor = false
    f.main.captureOptions.inPlaceEdit = false
    f.main.captureOptions.delay = 0

    f.main.sendCommandEvent(ActionCapture.FullScreen)

    let img = Clipboard.getImage()
    @assert(img.isValid())
    @assert(img.width > 1)
    @assert(img.height > 1)

    f.shutdown()
}
