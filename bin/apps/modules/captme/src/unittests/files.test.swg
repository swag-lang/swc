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

func captmeTestSamePath(left: string, right: string)->bool
{
    var l = String.from(left)
    var r = String.from(right)
    Path.normalize(&l)
    Path.normalize(&r)
    return Path.equals(l.toString(), r.toString())
}

func captmeTestHasCaptmeFileMetadata(img: Image, captureFile: string)->bool
{
    foreach md in img.metaDatas
    {
        if md.isTag("Captme.File")
        {
            if captmeTestSamePath(cast(string) md.toSlice(), captureFile) do
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
    f.capture.backImg = guiTestIndexedImage(32, 20)

    let capturePath = captmeTestPrepareSavedCapture(f.capture)
    defer { discard catch File.delete(capturePath) }

    let pngPath = guiTestTempFilePath("captme-", ".png")
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

// The Save As Image command drives the real file dialog before writing the PNG.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup(registerHeadlessCommands: true)
    captmeTestRegisterIoActions(f.main)

    f.capture.width = 34
    f.capture.height = 22
    f.capture.backImg = guiTestIndexedImage(34, 22)

    let capturePath = captmeTestPrepareSavedCapture(f.capture)
    defer { discard catch File.delete(capturePath) }

    let pngPath = guiTestTempFilePath("captme-", ".png")
    defer { discard catch File.delete(pngPath) }

    f.gui.acceptModalFileDialog(pngPath)

    f.main.sendCommandEvent(ActionFile.SaveAsImage)
    f.gui.pump()

    @assert(f.gui.autoHandled)
    @assert(f.gui.app.surfaces.count == 0)
    @assert(File.exists(pngPath))

    let saved = catch Image.load(pngPath)
    @assert(@err == null)
    @assert(saved.isValid())
    @assert(saved.width == 34)
    @assert(saved.height == 22)
    @assert(captmeTestHasCaptmeFileMetadata(saved, capturePath))

    f.shutdown()
}

// Existing file targets exercise the nested overwrite confirmation from FileDlg.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup(registerHeadlessCommands: true)
    captmeTestRegisterIoActions(f.main)

    f.capture.width = 40
    f.capture.height = 30
    f.capture.backImg = guiTestIndexedImage(40, 30)

    let capturePath = captmeTestPrepareSavedCapture(f.capture)
    defer { discard catch File.delete(capturePath) }

    let pngPath = guiTestTempFilePath("captme-", ".png")
    defer { discard catch File.delete(pngPath) }

    var oldImage = Image.create(3, 2, .BGRA8)
    oldImage.fill(ColorRed)
    catch oldImage.save(pngPath)
    @assert(@err == null)

    f.gui.acceptModalFileDialog(pngPath)
    f.gui.thenClickModalButton(Dialog.BtnYes)

    f.main.sendCommandEvent(ActionFile.SaveAsImage)
    f.gui.pump()

    @assert(f.gui.autoHandled)
    @assert(f.gui.app.surfaces.count == 0)

    let saved = catch Image.load(pngPath)
    @assert(@err == null)
    @assert(saved.isValid())
    @assert(saved.width == 40)
    @assert(saved.height == 30)
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
    f.capture.backImg = guiTestIndexedImage(28, 18)

    let capturePath = captmeTestPrepareSavedCapture(f.capture)
    defer { discard catch File.delete(capturePath) }

    let linkedPath = guiTestTempFilePath("captme-", ".png")
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

// The linked-image variant uses the same real file dialog and persists the chosen path.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup(registerHeadlessCommands: true)
    captmeTestRegisterIoActions(f.main)

    f.capture.width = 36
    f.capture.height = 24
    f.capture.backImg = guiTestIndexedImage(36, 24)

    let capturePath = captmeTestPrepareSavedCapture(f.capture)
    defer { discard catch File.delete(capturePath) }

    let linkedPath = guiTestTempFilePath("captme-", ".png")
    defer { discard catch File.delete(linkedPath) }

    f.gui.acceptModalFileDialog(linkedPath)

    f.main.sendCommandEvent(ActionFile.SaveAsLinkedImage)
    f.gui.pump()

    @assert(f.gui.autoHandled)
    @assert(f.gui.app.surfaces.count == 0)
    @assert(File.exists(linkedPath))
    @assert(captmeTestSamePath(f.capture.linkedImage, linkedPath))
    @assert(f.capture.linkedUpToDate)

    let loaded = catch Capture.load(capturePath)
    @assert(@err == null)
    defer { Memory.delete(loaded) }

    @assert(captmeTestSamePath(loaded.linkedImage, linkedPath))
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
    f.capture.backImg = guiTestIndexedImage(26, 16)

    let capturePath = captmeTestPrepareSavedCapture(f.capture)
    defer { discard catch File.delete(capturePath) }

    let linkedPath = guiTestTempFilePath("captme-", ".png")
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

// Updating a linked image also works through the real overwrite confirmation dialog.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup(registerHeadlessCommands: true)
    captmeTestRegisterIoActions(f.main)

    f.capture.width = 38
    f.capture.height = 26
    f.capture.backImg = guiTestIndexedImage(38, 26)

    let capturePath = captmeTestPrepareSavedCapture(f.capture)
    defer { discard catch File.delete(capturePath) }

    let linkedPath = guiTestTempFilePath("captme-", ".png")
    defer { discard catch File.delete(linkedPath) }

    f.capture.linkedImage = linkedPath
    f.capture.linkedUpToDate = false
    f.main.editorOptions.confirmLinkedOverwrite = true

    f.gui.clickModalButtonWhenShown(Dialog.BtnYes)

    f.main.sendCommandEvent(ActionFile.UpdateLinkedImage)
    f.gui.pump()

    @assert(f.gui.autoHandled)
    @assert(f.gui.app.surfaces.count == 0)
    @assert(File.exists(linkedPath))
    @assert(f.capture.linkedUpToDate)

    let linked = catch Image.load(linkedPath)
    @assert(@err == null)
    @assert(linked.isValid())
    @assert(linked.width == 38)
    @assert(linked.height == 26)
    @assert(captmeTestHasCaptmeFileMetadata(linked, capturePath))

    let loaded = catch Capture.load(capturePath)
    @assert(@err == null)
    defer { Memory.delete(loaded) }

    @assert(captmeTestSamePath(loaded.linkedImage, linkedPath))
    @assert(loaded.linkedUpToDate)

    f.shutdown()
}

// Unlinking an image goes through the confirmation dialog and persists the capture.
#test
{
    var f: CaptmeHeadlessFixture
    f.setup(registerHeadlessCommands: true)
    captmeTestRegisterIoActions(f.main)
    f.main.recentWnd = RecentWnd.create(f.main, f.main)

    f.capture.width = 24
    f.capture.height = 18
    f.capture.backImg = guiTestIndexedImage(24, 18)

    let capturePath = captmeTestPrepareSavedCapture(f.capture)
    defer { discard catch File.delete(capturePath) }

    let linkedPath = guiTestTempFilePath("captme-", ".png")
    f.capture.linkedImage = linkedPath
    f.capture.linkedUpToDate = true
    f.capture.changed = true
    catch f.capture.save()
    @assert(@err == null)

    f.gui.clickModalButtonWhenShown(Dialog.BtnYes)

    f.main.sendCommandEvent(ActionFile.UnlinkImage)
    f.gui.pump()

    @assert(f.gui.autoHandled)
    @assert(f.gui.app.surfaces.count == 0)
    @assert(f.capture.linkedImage.isEmpty())
    @assert(!f.capture.linkedUpToDate)

    let loaded = catch Capture.load(capturePath)
    @assert(@err == null)
    defer { Memory.delete(loaded) }

    @assert(loaded.linkedImage.isEmpty())
    @assert(!loaded.linkedUpToDate)

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

    f.gui.clickModalButtonWhenShown(Dialog.BtnOk)

    f.main.sendCommandEvent(ActionFile.FileDetails)
    f.gui.pump()

    @assert(f.gui.autoHandled)
    @assert(f.gui.app.surfaces.count == 0)

    f.shutdown()
}

