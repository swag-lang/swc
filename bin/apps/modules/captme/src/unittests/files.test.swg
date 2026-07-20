#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, File

func testPrepareSavedCapture(capture: #nonull *Capture)->String
{
    let path = testTempCapturePath()
    capture.file    = path
    capture.changed = true

    catch capture.save()
    @assert(@err == null)
    @assert(File.exists(path))
    return path
}

func testSamePath(left: String, right: String)->bool
{
    var l = String.from(left)
    var r = String.from(right)
    Path.normalize(&l)
    Path.normalize(&r)
    return Path.equals(l.toString(), r.toString())
}

func testHasCaptmeFileMetadata(img: Image, captureFile: String)->bool
{
    for md in img.metaDatas
    {
        if md.isTag("Captme.File")
        {
            if testSamePath(cast(#nonull string) md.toSlice(), captureFile) do
                return true
        }
    }

    return false
}

func testPrepareRecentLibrary(main: #nonull *MainWnd)
{
    catch Library.init()
    @assert(@err == null)
    g_Library.files.clear()
    g_Library.loaded = true

    if !main.recentWnd do
        main.recentWnd = RecentWnd.create(main, main)
}

// New Image uses its real modal dialog, then creates and persists a new capture.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    testRegisterIoActions(f.main)
    testPrepareRecentLibrary(f.main)

    f.gui.clickModalButtonWhenShown(Dialog.BtnOk)
    f.gui.withModalEdit("Width", "48")
    f.gui.withModalEdit("Height", "32")

    @assert(Testing.actionExecute'ActionFile(f.main, ActionFile.NewImage))
    f.gui.pump()

    @assert(f.gui.autoHandled)
    @assert(f.gui.app.surfaces.count == 0)

    let capture = assume f.main.getCapture()
    let generatedPath = capture.file
    defer
    {
        discard catch File.delete(generatedPath)
        g_Library.files.clear()
    }

    @assert(capture.width == 48)
    @assert(capture.height == 32)
    @assert(capture.backImg.isValid())
    @assert(capture.backImg.width == 48)
    @assert(capture.backImg.height == 32)
    @assert(File.exists(generatedPath))
    @assert(f.main.recentWnd.recentView.items.count == 1)
    @assert(f.main.recentWnd.recentView.selected == 0)

    f.shutdown()
}

// New From Clipboard consumes the real image clipboard and creates a persisted capture.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    testRegisterIoActions(f.main)
    testPrepareRecentLibrary(f.main)

    Clipboard.addImage(Testing.indexedImage(19, 11))

    @assert(Testing.actionExecute'ActionFile(f.main, ActionFile.NewFromClipboard))
    f.gui.pump()

    let capture = assume f.main.getCapture()
    let generatedPath = capture.file
    defer
    {
        discard catch File.delete(generatedPath)
        g_Library.files.clear()
    }

    @assert(capture.width == 19)
    @assert(capture.height == 11)
    @assert(capture.backImg.isValid())
    @assert(capture.linkedImage == null)
    @assert(File.exists(generatedPath))
    @assert(f.main.recentWnd.recentView.items.count == 1)
    @assert(f.main.recentWnd.recentView.selected == 0)

    f.shutdown()
}

// Open Image drives the real file dialog, loads a real PNG, then persists a capture.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    testRegisterIoActions(f.main)
    testPrepareRecentLibrary(f.main)

    let sourcePath = Testing.tempFilePath("captme-", ".png")
    defer { discard catch File.delete(sourcePath) }

    var source = Testing.indexedImage(21, 13)
    catch source.save(sourcePath)
    @assert(@err == null)

    f.gui.acceptModalFileDialog(sourcePath)

    @assert(Testing.actionExecute'ActionFile(f.main, ActionFile.OpenImage))
    f.gui.pump()

    @assert(f.gui.autoHandled)
    @assert(f.gui.app.surfaces.count == 0)

    let capture = assume f.main.getCapture()
    let generatedPath = capture.file
    defer
    {
        discard catch File.delete(generatedPath)
        g_Library.files.clear()
    }

    @assert(capture.width == 21)
    @assert(capture.height == 13)
    @assert(capture.backImg.isValid())
    @assert(testSamePath(capture.linkedImage, sourcePath))
    @assert(File.exists(generatedPath))
    @assert(f.main.recentWnd.recentView.items.count == 1)
    @assert(f.main.recentWnd.recentView.selected == 0)

    f.shutdown()
}

// Save As Image writes a real PNG that can be loaded back with Captme metadata.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    testRegisterIoActions(f.main)

    f.capture.width = 32
    f.capture.height = 20
    f.capture.backImg = Testing.indexedImage(32, 20)

    let capturePath = testPrepareSavedCapture(f.capture)
    defer { discard catch File.delete(capturePath) }

    let pngPath = Testing.tempFilePath("captme-", ".png")
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
    @assert(testHasCaptmeFileMetadata(saved, capturePath))

    f.shutdown()
}

// The Save As Image command drives the real file dialog before writing the PNG.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    testRegisterIoActions(f.main)

    f.capture.width = 34
    f.capture.height = 22
    f.capture.backImg = Testing.indexedImage(34, 22)

    let capturePath = testPrepareSavedCapture(f.capture)
    defer { discard catch File.delete(capturePath) }

    let pngPath = Testing.tempFilePath("captme-", ".png")
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
    @assert(testHasCaptmeFileMetadata(saved, capturePath))

    f.shutdown()
}

// Existing file targets exercise the nested overwrite confirmation from FileDlg.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    testRegisterIoActions(f.main)

    f.capture.width = 40
    f.capture.height = 30
    f.capture.backImg = Testing.indexedImage(40, 30)

    let capturePath = testPrepareSavedCapture(f.capture)
    defer { discard catch File.delete(capturePath) }

    let pngPath = Testing.tempFilePath("captme-", ".png")
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
    @assert(testHasCaptmeFileMetadata(saved, capturePath))

    f.shutdown()
}

// Save As Linked Image persists the linked file association into the capture file.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    testRegisterIoActions(f.main)

    f.capture.width = 28
    f.capture.height = 18
    f.capture.backImg = Testing.indexedImage(28, 18)

    let capturePath = testPrepareSavedCapture(f.capture)
    defer { discard catch File.delete(capturePath) }

    let linkedPath = Testing.tempFilePath("captme-", ".png")
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
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    testRegisterIoActions(f.main)

    f.capture.width = 36
    f.capture.height = 24
    f.capture.backImg = Testing.indexedImage(36, 24)

    let capturePath = testPrepareSavedCapture(f.capture)
    defer { discard catch File.delete(capturePath) }

    let linkedPath = Testing.tempFilePath("captme-", ".png")
    defer { discard catch File.delete(linkedPath) }

    f.gui.acceptModalFileDialog(linkedPath)

    f.main.sendCommandEvent(ActionFile.SaveAsLinkedImage)
    f.gui.pump()

    @assert(f.gui.autoHandled)
    @assert(f.gui.app.surfaces.count == 0)
    @assert(File.exists(linkedPath))
    @assert(testSamePath(f.capture.linkedImage, linkedPath))
    @assert(f.capture.linkedUpToDate)

    let loaded = catch Capture.load(capturePath)
    @assert(@err == null)
    defer { Memory.delete(loaded) }

    @assert(testSamePath(loaded.linkedImage, linkedPath))
    @assert(loaded.linkedUpToDate)

    f.shutdown()
}

// Updating an existing linked image avoids the file dialog and still exercises
// real PNG output plus capture-file persistence.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    testRegisterIoActions(f.main)

    f.capture.width = 26
    f.capture.height = 16
    f.capture.backImg = Testing.indexedImage(26, 16)

    let capturePath = testPrepareSavedCapture(f.capture)
    defer { discard catch File.delete(capturePath) }

    let linkedPath = Testing.tempFilePath("captme-", ".png")
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
    @assert(testHasCaptmeFileMetadata(linked, capturePath))

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
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    testRegisterIoActions(f.main)

    f.capture.width = 38
    f.capture.height = 26
    f.capture.backImg = Testing.indexedImage(38, 26)

    let capturePath = testPrepareSavedCapture(f.capture)
    defer { discard catch File.delete(capturePath) }

    let linkedPath = Testing.tempFilePath("captme-", ".png")
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
    @assert(testHasCaptmeFileMetadata(linked, capturePath))

    let loaded = catch Capture.load(capturePath)
    @assert(@err == null)
    defer { Memory.delete(loaded) }

    @assert(testSamePath(loaded.linkedImage, linkedPath))
    @assert(loaded.linkedUpToDate)

    f.shutdown()
}

// Unlinking an image goes through the confirmation dialog and persists the capture.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    testRegisterIoActions(f.main)
    f.main.recentWnd = RecentWnd.create(f.main, f.main)

    f.capture.width = 24
    f.capture.height = 18
    f.capture.backImg = Testing.indexedImage(24, 18)

    let capturePath = testPrepareSavedCapture(f.capture)
    defer { discard catch File.delete(capturePath) }

    let linkedPath = Testing.tempFilePath("captme-", ".png")
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

// Duplicate Capture creates an independent capture file and recent entry.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    testRegisterIoActions(f.main)
    testPrepareRecentLibrary(f.main)

    discard testAddShape(f.capture, 4, 5, 12, 13)
    let originalPath = testPrepareSavedCapture(f.capture)
    defer { discard catch File.delete(originalPath) }

    @assert(Testing.actionExecute'ActionFile(f.main, ActionFile.DupCapture))
    f.gui.pump()

    @assert(f.main.recentWnd.recentView.items.count == 1)
    @assert(f.main.recentWnd.recentView.selected == 0)

    let duplicatedPath = f.main.recentWnd.recentView.items[0].file
    defer
    {
        discard catch File.delete(duplicatedPath)
        g_Library.files.clear()
    }

    @assert(!testSamePath(duplicatedPath, originalPath))
    @assert(File.exists(duplicatedPath))

    let duplicated = catch Capture.load(duplicatedPath)
    @assert(@err == null)
    defer { Memory.delete(duplicated) }

    @assert(duplicated.forms.count == 1)
    @assert(duplicated.linkedImage == null)

    f.shutdown()
}

// Delete Capture confirms through the real modal and removes the selected capture file.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    testRegisterIoActions(f.main)
    testPrepareRecentLibrary(f.main)

    let capturePath = testPrepareSavedCapture(f.capture)
    g_Library.addFile(capturePath)

    let loaded = catch f.main.recentWnd.addRecent(capturePath, true, true)
    @assert(@err == null)
    Memory.delete(loaded)
    @assert(f.main.recentWnd.recentView.selected == 0)

    f.gui.clickModalButtonWhenShown(Dialog.BtnYes)

    @assert(Testing.actionExecute'ActionFile(f.main, ActionFile.DeleteCapture))
    f.gui.pump()

    @assert(f.gui.autoHandled)
    @assert(f.gui.app.surfaces.count == 0)
    @assert(!File.exists(capturePath))
    @assert(g_Library.files.count == 0)

    f.shutdown()
}

// File Details opens a real modal dialog after reading the saved capture size
// from disk; the headless modal helper closes it through the normal OK button.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    testRegisterIoActions(f.main)

    let capturePath = testPrepareSavedCapture(f.capture)
    defer { discard catch File.delete(capturePath) }

    f.gui.clickModalButtonWhenShown(Dialog.BtnOk)

    f.main.sendCommandEvent(ActionFile.FileDetails)
    f.gui.pump()

    @assert(f.gui.autoHandled)
    @assert(f.gui.app.surfaces.count == 0)

    f.shutdown()
}
