#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, File

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

