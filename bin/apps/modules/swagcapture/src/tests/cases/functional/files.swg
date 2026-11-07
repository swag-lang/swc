#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, File

func testPrepareSavedCapture(capture: *Capture)->String
{
    let path = testTempCapturePath()
    capture.file    = path
    capture.changed = true

    expect capture.save()
    Swag.require(File.exists(path))
    return path
}

func testSamePath(left: String, right: String)->bool
{
    var l = String.from(left)
    var r = String.from(right)
    Path.normalize(&l)
    Path.normalize(&r)
    return Path.equals(l, r)
}

func testHasCaptureFileMetadata(img: Image, captureFile: String)->bool
{
    for md in img.metadata
    {
        if md.isTag(CaptureFileMetadataTag)
        {
            if testSamePath(cast(string, md.toSlice()), captureFile) do
                return true
        }
    }

    return false
}

// The automatic save snapshots on the interface thread and lands on a job worker:
// scheduling clears the dirty flag immediately, an edit made after scheduling must
// not leak into the file being written, and the flush waits for the atomic replace.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    f.capture.title = "Scheduled title"
    let path = testPrepareSavedCapture(f.capture)

    f.capture.changed = true
    expect f.capture.scheduleSave()
    Swag.require(not f.capture.changed)

    // The scheduled write only reads its snapshot, never the live capture.
    f.capture.title = "Mutated after scheduling"

    let failedSave = g_CaptureSaves.flush()
    Swag.require(failedSave.isEmpty())
    Swag.require(g_CaptureSaves.pending == null)

    let saved = expect Capture.load(path)
    defer Memory.delete(saved)
    Swag.require(saved.title == "Scheduled title")
}

// New Image uses its real modal dialog, then creates and persists a new capture.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)
    testPrepareRecentLibrary(f.main)

    f.gui.clickModalButtonWhenShown(Dialog.BtnOk)
    f.gui.withModalEdit("Width", "48")
    f.gui.withModalEdit("Height", "32")

    let actionExecuted = Gui.Testing.actionExecute'ActionFile(f.main, ActionFile.NewImage)
    Swag.require(actionExecuted)
    f.gui.pump()

    Swag.require(f.gui.autoHandled)
    Swag.require(f.gui.openedSurfaceCount() == 0)

    let capture       = unwrap f.main.getCapture()
    let generatedPath = capture.file
    defer
    {
        discard catch File.delete(generatedPath)
        g_Library.files.clear()
    }

    Swag.require(capture.width == 48)
    Swag.require(capture.height == 32)
    Swag.require(capture.backImg.isValid())
    Swag.require(capture.backImg.width == 48)
    Swag.require(capture.backImg.height == 32)
    Swag.require(File.exists(generatedPath))
    Swag.require(f.main.recentWnd.recentView.items.count == 1)
    Swag.require(f.main.recentWnd.recentView.selected == 0)
}

// New From Clipboard consumes the real image clipboard and creates a persisted capture.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)
    testPrepareRecentLibrary(f.main)

    Clipboard.addImage(Gui.Testing.indexedImage(19, 11))

    let actionExecuted = Gui.Testing.actionExecute'ActionFile(f.main, ActionFile.NewFromClipboard)
    Swag.require(actionExecuted)
    f.gui.pump()

    let capture       = unwrap f.main.getCapture()
    let generatedPath = capture.file
    defer
    {
        discard catch File.delete(generatedPath)
        g_Library.files.clear()
    }

    Swag.require(capture.width == 19)
    Swag.require(capture.height == 11)
    Swag.require(capture.backImg.isValid())
    Swag.require(capture.linkedImage == null)
    Swag.require(File.exists(generatedPath))
    Swag.require(f.main.recentWnd.recentView.items.count == 1)
    Swag.require(f.main.recentWnd.recentView.selected == 0)
}

// Open Image drives the real file dialog, loads a real PNG, then persists a capture.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)
    testPrepareRecentLibrary(f.main)

    let sourcePath = Gui.Testing.tempFilePath("capture-", ".png")
    defer discard catch File.delete(sourcePath)
    var source = Gui.Testing.indexedImage(21, 13)
    expect source.save(sourcePath)
    f.gui.acceptModalFileDialog(sourcePath)

    let actionExecuted = Gui.Testing.actionExecute'ActionFile(f.main, ActionFile.OpenImage)
    Swag.require(actionExecuted)
    f.gui.pump()

    Swag.require(f.gui.autoHandled)
    Swag.require(f.gui.openedSurfaceCount() == 0)

    let capture       = unwrap f.main.getCapture()
    let generatedPath = capture.file
    defer
    {
        discard catch File.delete(generatedPath)
        g_Library.files.clear()
    }

    Swag.require(capture.width == 21)
    Swag.require(capture.height == 13)
    Swag.require(capture.backImg.isValid())
    Swag.require(testSamePath(capture.linkedImage, sourcePath))
    Swag.require(File.exists(generatedPath))
    Swag.require(f.main.recentWnd.recentView.items.count == 1)
    Swag.require(f.main.recentWnd.recentView.selected == 0)
}

// A picture dropped on the editor opens it, exactly as the Open command does.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)
    testPrepareRecentLibrary(f.main)

    let sourcePath = Gui.Testing.tempFilePath("capture-drop-", ".png")
    defer discard catch File.delete(sourcePath)
    var source = Gui.Testing.indexedImage(23, 17)
    expect source.save(sourcePath)

    Swag.require(f.gui.dropFilesOnWnd(f.editView, [sourcePath.toString()]) == Gui.DropEffect.Copy)

    let capture       = unwrap f.main.getCapture()
    let generatedPath = capture.file
    defer
    {
        discard catch File.delete(generatedPath)
        g_Library.files.clear()
    }

    Swag.require(capture.width == 23)
    Swag.require(capture.height == 17)
    Swag.require(testSamePath(capture.linkedImage, sourcePath))
    Swag.require(File.exists(generatedPath))
    Swag.require(f.main.recentWnd.recentView.items.count == 1)
}

// Several pictures dropped at once open one capture each, in the order they were listed.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)
    testPrepareRecentLibrary(f.main)

    let firstPath = Gui.Testing.tempFilePath("capture-drop-a-", ".png")
    let lastPath  = Gui.Testing.tempFilePath("capture-drop-b-", ".png")
    defer discard catch File.delete(firstPath)
    defer discard catch File.delete(lastPath)
    var first = Gui.Testing.indexedImage(12, 9)
    var last  = Gui.Testing.indexedImage(31, 7)
    expect first.save(firstPath)
    expect last.save(lastPath)

    Swag.require(f.gui.dropFilesOnWnd(f.editView, [firstPath, lastPath.toString()]) == Gui.DropEffect.Copy)

    defer g_Library.files.clear()
    Swag.require(f.main.recentWnd.recentView.items.count == 2)

    // The last one dropped is the one left on the easel.
    let capture = unwrap f.main.getCapture()
    defer discard catch File.delete(capture.file)
    Swag.require(capture.width == 31)
    Swag.require(capture.height == 7)
    Swag.require(testSamePath(capture.linkedImage, lastPath))
}

// A file no decoder claims is refused, and leaves the editor on what it was showing.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)
    testPrepareRecentLibrary(f.main)

    let before = f.main.getCapture()
    Swag.require(f.gui.dropFilesOnWnd(f.editView, ["c:/notes/readme.txt"]) == Gui.DropEffect.None)
    Swag.require(f.main.getCapture() == before)
    Swag.require(f.main.recentWnd.recentView.items.count == 0)
}

// Save As Image writes a real PNG that can be loaded back with Swag Capture metadata.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)

    f.capture.width   = 32
    f.capture.height  = 20
    f.capture.backImg = Gui.Testing.indexedImage(32, 20)

    let capturePath = testPrepareSavedCapture(f.capture)
    defer discard catch File.delete(capturePath)
    let pngPath = Gui.Testing.tempFilePath("capture-", ".png")
    defer discard catch File.delete(pngPath)
    f.main.doSaveAsImage(pngPath)
    f.gui.pump()

    Swag.require(File.exists(pngPath))

    let saved = expect Image.load(pngPath)
    Swag.require(saved.isValid())
    Swag.require(saved.width == 32)
    Swag.require(saved.height == 20)
    Swag.require(saved.metadata.count > 0)
    Swag.require(testHasCaptureFileMetadata(saved, capturePath))
}

// The Save As Image command drives the real file dialog before writing the PNG.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)

    f.capture.width   = 34
    f.capture.height  = 22
    f.capture.backImg = Gui.Testing.indexedImage(34, 22)

    let capturePath = testPrepareSavedCapture(f.capture)
    defer discard catch File.delete(capturePath)
    let pngPath = Gui.Testing.tempFilePath("capture-", ".png")
    defer discard catch File.delete(pngPath)
    f.gui.acceptModalFileDialog(pngPath)

    f.main.sendCommandEvent(ActionFile.SaveAsImage)
    f.gui.pump()

    Swag.require(f.gui.autoHandled)
    Swag.require(f.gui.openedSurfaceCount() == 0)
    Swag.require(File.exists(pngPath))

    let saved = expect Image.load(pngPath)
    Swag.require(saved.isValid())
    Swag.require(saved.width == 34)
    Swag.require(saved.height == 22)
    Swag.require(testHasCaptureFileMetadata(saved, capturePath))
}

// Existing file targets exercise the nested overwrite confirmation from FileDlg.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)

    f.capture.width   = 40
    f.capture.height  = 30
    f.capture.backImg = Gui.Testing.indexedImage(40, 30)

    let capturePath = testPrepareSavedCapture(f.capture)
    defer discard catch File.delete(capturePath)
    let pngPath = Gui.Testing.tempFilePath("capture-", ".png")
    defer discard catch File.delete(pngPath)
    var oldImage = Image.create(3, 2, .BGRA8)
    oldImage.fill(ColorRed)
    expect oldImage.save(pngPath)
    f.gui.acceptModalFileDialog(pngPath)
    f.gui.thenClickModalButton(Dialog.BtnYes)

    f.main.sendCommandEvent(ActionFile.SaveAsImage)
    f.gui.pump()

    Swag.require(f.gui.autoHandled)
    Swag.require(f.gui.openedSurfaceCount() == 0)

    let saved = expect Image.load(pngPath)
    Swag.require(saved.isValid())
    Swag.require(saved.width == 40)
    Swag.require(saved.height == 30)
    Swag.require(testHasCaptureFileMetadata(saved, capturePath))
}

// Save As Linked Image persists the linked file association into the capture file.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)

    f.capture.width   = 28
    f.capture.height  = 18
    f.capture.backImg = Gui.Testing.indexedImage(28, 18)

    let capturePath = testPrepareSavedCapture(f.capture)
    defer discard catch File.delete(capturePath)
    let linkedPath = Gui.Testing.tempFilePath("capture-", ".png")
    defer discard catch File.delete(linkedPath)
    f.main.doSaveAsImage(linkedPath, linked: true)
    f.gui.pump()

    Swag.require(File.exists(linkedPath))
    Swag.require(f.capture.linkedImage == linkedPath)
    Swag.require(f.capture.linkedUpToDate)

    let loaded = expect Capture.load(capturePath)
    defer Memory.delete(loaded)
    Swag.require(loaded.linkedImage == linkedPath)
    Swag.require(loaded.linkedUpToDate)
}

// The linked-image variant uses the same real file dialog and persists the chosen path.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)

    f.capture.width   = 36
    f.capture.height  = 24
    f.capture.backImg = Gui.Testing.indexedImage(36, 24)

    let capturePath = testPrepareSavedCapture(f.capture)
    defer discard catch File.delete(capturePath)
    let linkedPath = Gui.Testing.tempFilePath("capture-", ".png")
    defer discard catch File.delete(linkedPath)
    f.gui.acceptModalFileDialog(linkedPath)

    f.main.sendCommandEvent(ActionFile.SaveAsLinkedImage)
    f.gui.pump()

    Swag.require(f.gui.autoHandled)
    Swag.require(f.gui.openedSurfaceCount() == 0)
    Swag.require(File.exists(linkedPath))
    Swag.require(testSamePath(f.capture.linkedImage, linkedPath))
    Swag.require(f.capture.linkedUpToDate)

    let loaded = expect Capture.load(capturePath)
    defer Memory.delete(loaded)
    Swag.require(testSamePath(loaded.linkedImage, linkedPath))
    Swag.require(loaded.linkedUpToDate)
}

// Updating an existing linked image avoids the file dialog and still exercises
// real PNG output plus capture-file persistence.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)

    f.capture.width   = 26
    f.capture.height  = 16
    f.capture.backImg = Gui.Testing.indexedImage(26, 16)

    let capturePath = testPrepareSavedCapture(f.capture)
    defer discard catch File.delete(capturePath)
    let linkedPath = Gui.Testing.tempFilePath("capture-", ".png")
    defer discard catch File.delete(linkedPath)
    f.capture.linkedImage    = linkedPath
    f.capture.linkedUpToDate = false
    f.main.editorOptions.confirmLinkedOverwrite = false

    f.main.sendCommandEvent(ActionFile.UpdateLinkedImage)
    f.gui.pump()

    Swag.require(File.exists(linkedPath))
    Swag.require(f.capture.linkedUpToDate)

    let linked = expect Image.load(linkedPath)
    Swag.require(linked.isValid())
    Swag.require(linked.width == 26)
    Swag.require(linked.height == 16)
    Swag.require(testHasCaptureFileMetadata(linked, capturePath))

    let loaded = expect Capture.load(capturePath)
    defer Memory.delete(loaded)
    Swag.require(loaded.linkedImage == linkedPath)
    Swag.require(loaded.linkedUpToDate)
}

// Updating a linked image also works through the real overwrite confirmation dialog.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)

    f.capture.width   = 38
    f.capture.height  = 26
    f.capture.backImg = Gui.Testing.indexedImage(38, 26)

    let capturePath = testPrepareSavedCapture(f.capture)
    defer discard catch File.delete(capturePath)
    let linkedPath = Gui.Testing.tempFilePath("capture-", ".png")
    defer discard catch File.delete(linkedPath)
    f.capture.linkedImage    = linkedPath
    f.capture.linkedUpToDate = false
    f.main.editorOptions.confirmLinkedOverwrite = true

    f.gui.clickModalButtonWhenShown(Dialog.BtnYes)

    f.main.sendCommandEvent(ActionFile.UpdateLinkedImage)
    f.gui.pump()

    Swag.require(f.gui.autoHandled)
    Swag.require(f.gui.openedSurfaceCount() == 0)
    Swag.require(File.exists(linkedPath))
    Swag.require(f.capture.linkedUpToDate)

    let linked = expect Image.load(linkedPath)
    Swag.require(linked.isValid())
    Swag.require(linked.width == 38)
    Swag.require(linked.height == 26)
    Swag.require(testHasCaptureFileMetadata(linked, capturePath))

    let loaded = expect Capture.load(capturePath)
    defer Memory.delete(loaded)
    Swag.require(testSamePath(loaded.linkedImage, linkedPath))
    Swag.require(loaded.linkedUpToDate)
}

// Unlinking an image goes through the confirmation dialog and persists the capture.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)
    f.main.recentWnd = RecentWnd.create(f.main, f.main)

    f.capture.width   = 24
    f.capture.height  = 18
    f.capture.backImg = Gui.Testing.indexedImage(24, 18)

    let capturePath = testPrepareSavedCapture(f.capture)
    defer discard catch File.delete(capturePath)
    let linkedPath = Gui.Testing.tempFilePath("capture-", ".png")
    f.capture.linkedImage    = linkedPath
    f.capture.linkedUpToDate = true
    f.capture.changed        = true
    expect f.capture.save()
    f.gui.clickModalButtonWhenShown(Dialog.BtnYes)

    f.main.sendCommandEvent(ActionFile.UnlinkImage)
    f.gui.pump()

    Swag.require(f.gui.autoHandled)
    Swag.require(f.gui.openedSurfaceCount() == 0)
    Swag.require(f.capture.linkedImage.isEmpty())
    Swag.require(not f.capture.linkedUpToDate)

    let loaded = expect Capture.load(capturePath)
    defer Memory.delete(loaded)
    Swag.require(loaded.linkedImage.isEmpty())
    Swag.require(not loaded.linkedUpToDate)
}

// Duplicate Capture creates an independent capture file and recent entry.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)
    testPrepareRecentLibrary(f.main)

    discard testAddShape(f.capture, 4, 5, 12, 13)
    let originalPath = testPrepareSavedCapture(f.capture)
    defer discard catch File.delete(originalPath)
    let actionExecuted = Gui.Testing.actionExecute'ActionFile(f.main, ActionFile.DupCapture)
    Swag.require(actionExecuted)
    f.gui.pump()

    Swag.require(f.main.recentWnd.recentView.items.count == 1)
    Swag.require(f.main.recentWnd.recentView.selected == 0)

    let duplicatedPath = f.main.recentWnd.recentView.items[0]!.file
    defer
    {
        discard catch File.delete(duplicatedPath)
        g_Library.files.clear()
    }

    Swag.require(not testSamePath(duplicatedPath, originalPath))
    Swag.require(File.exists(duplicatedPath))

    let duplicated = expect Capture.load(duplicatedPath)
    defer Memory.delete(duplicated)
    Swag.require(duplicated.forms.count == 1)
    Swag.require(duplicated.linkedImage == null)
}

// Delete Capture confirms through the real modal and removes the selected capture file.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)
    testPrepareRecentLibrary(f.main)
    g_Library.onDeleteFile += func|recent = f.main.recentWnd|(file) { recent.onLibraryFileDeleted(file) }

    let capturePath = testPrepareSavedCapture(f.capture)
    g_Library.addFile(capturePath)

    let loaded = expect f.main.recentWnd.addRecent(capturePath, true, true)
    Memory.delete(loaded)
    Swag.require(f.main.recentWnd.recentView.selected == 0)

    // The library observer is registered after the history observer, as it is when the user
    // opens the library after editing a new capture. Both observers must receive a stable path
    // even though the first one destroys the history item that supplied it.
    f.main.libWnd = LibraryWnd.create(f.main)
    f.main.libWnd.fill()
    f.main.libWnd.view.stopLoading()

    f.gui.clickModalButtonWhenShown(Dialog.BtnYes)

    let actionExecuted = Gui.Testing.actionExecute'ActionFile(f.main, ActionFile.DeleteCapture)
    Swag.require(actionExecuted)
    f.gui.pump()

    Swag.require(f.gui.autoHandled)
    Swag.require(f.gui.openedSurfaceCount() == 0)
    Swag.require(not File.exists(capturePath))
    Swag.require(g_Library.files.count == 0)
    Swag.require(f.main.recentWnd.recentView.items.count == 0)
    Swag.require(f.main.libWnd.view.items.count == 0)
}

// File Details opens a real modal dialog after reading the saved capture size
// from disk; the headless modal helper closes it through its one Close button.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)

    let capturePath = testPrepareSavedCapture(f.capture)
    defer discard catch File.delete(capturePath)
    f.gui.clickModalButtonWhenShown(Dialog.BtnCancel)

    f.main.sendCommandEvent(ActionFile.FileDetails)
    f.gui.pump()

    Swag.require(f.gui.autoHandled)
    Swag.require(f.gui.openedSurfaceCount() == 0)
}

// Opening a library item replaces the editor document only after saving that editor document.
// Library mode exposes a lightweight preview through MainWnd.getCapture(); it must never stand in
// for the independently owned capture that EditView is about to release.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    testPrepareRecentLibrary(f.main)
    let lib = f.setupLibraryWnd()

    let editorPath = testPrepareSavedCapture(f.capture)
    defer discard catch File.delete(editorPath)
    f.capture.title   = "Unsaved editor title"
    f.capture.changed = true

    let other = Memory.new'Capture()
    other.width, other.widthOrg   = 37
    other.height, other.heightOrg = 23
    other.backImg                 = Gui.Testing.indexedImage(37, 23)
    other.preview                 = Gui.Testing.indexedImage(32, 20)
    let otherPath = testPrepareSavedCapture(other)
    defer
    {
        discard catch File.delete(otherPath)
        Memory.delete(other)
    }

    f.main.recentWnd.addRecent(otherPath, other.preview, front: true)
    discard testAddLibraryItem(lib.view, otherPath, 1, 1)
    lib.view.focusItem = 0
    f.main.libraryMode = true

    f.main.recentWnd.recentView.select(0)

    let saved = expect Capture.load(editorPath)
    defer Memory.delete(saved)
    Swag.require(saved.title == "Unsaved editor title")
    Swag.require(f.main.editWnd.getCapture()!.file == otherPath)
}

// Moving an existing recent item to the front keeps the old selected item identified while its
// zoom is saved. The selection index follows the pointer relocation before the new item is opened.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    testPrepareRecentLibrary(f.main)

    let first = Memory.new'Capture()
    first.width, first.widthOrg   = 41
    first.height, first.heightOrg = 29
    first.backImg                 = Gui.Testing.indexedImage(41, 29)
    first.preview                 = Gui.Testing.indexedImage(32, 20)
    let firstPath = testPrepareSavedCapture(first)
    defer
    {
        discard catch File.delete(firstPath)
        Memory.delete(first)
    }

    let second = Memory.new'Capture()
    second.width, second.widthOrg   = 43
    second.height, second.heightOrg = 31
    second.backImg                  = Gui.Testing.indexedImage(43, 31)
    second.preview                  = Gui.Testing.indexedImage(32, 20)
    let secondPath = testPrepareSavedCapture(second)
    defer
    {
        discard catch File.delete(secondPath)
        Memory.delete(second)
    }

    f.main.recentWnd.addRecent(firstPath, first.preview, front: false)
    f.main.recentWnd.addRecent(secondPath, second.preview, front: false)
    f.main.recentWnd.recentView.select(0)
    f.main.editWnd.editView.setZoom(1.75)

    f.main.recentWnd.addRecent(secondPath, second.preview, front: true, sel: true)

    Swag.require(f.main.recentWnd.recentView.items[0]!.file == secondPath)
    Swag.require(f.main.recentWnd.recentView.items[1]!.file == firstPath)
    Swag.require(Math.isEqualEpsilon(f.main.recentWnd.recentView.items[1]!.zoom, 1.75, 0.001))
    Swag.require(f.main.recentWnd.recentView.selected == 0)
}

// Startup must not validate the complete library before showing the recent strip. The newest
// capture is loaded directly into the editor, while the full library index stays lazy until the
// user opens the library surface.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    let root = Gui.Testing.tempFilePath("capture-startup-", "")
    expect Directory.create(root)
    defer discard catch Directory.delete(root, recurse: true)
    let previousDefault = g_Library.defaultFolder
    defer g_Library.defaultFolder = previousDefault
    g_Library.defaultFolder = root
    expect g_Library.setFolder(root)

    // State shares the file extension but must never consume a recent-document load turn.
    discard expect File.writeAllText(Library.getStatePath(), "application state")

    f.capture.preview = Gui.Testing.indexedImage(32, 20)
    f.capture.file    = Path.combine(root, "newest.scc")
    f.capture.changed = true
    expect f.capture.save()
    let capturePath = String.from(f.capture.file)

    f.editView.capture = null
    Memory.delete(f.capture)
    f.main.recentWnd = RecentWnd.create(f.main, f.main)
    f.main.recentWnd.scheduleLoadRecent()
    Swag.require(not f.main.recentWnd.loadDone)
    f.gui.fireTimer(f.main.recentWnd.loadTimer)
    Swag.require(f.main.recentWnd.loadDone)
    Swag.require(f.main.recentWnd.pendingRecentFiles.count == 1)
    Swag.require(f.main.editWnd.getCapture()!.file == capturePath)
    Swag.require(not f.main.recentWnd.loadTimer)
    Swag.require((expect Library.enumerateSupportedFiles(root)).count == 1)

    // The same basename remains an ordinary capture outside the reserved state path.
    let elsewhere = Path.combine(root, "elsewhere")
    expect Directory.create(elsewhere)
    let captureBytes = expect File.readAllBytes(capturePath)
    discard expect File.writeAllBytes(Path.combine(elsewhere, "settings.scc"), captureBytes.toSlice())
    Swag.require((expect Library.enumerateSupportedFiles(elsewhere)).count == 1)

    Swag.require(not g_Library.loaded)
    while f.main.recentWnd.loadTimer
    {
        let timer = f.main.recentWnd.loadTimer
        f.gui.fireTimer(timer)
    }

    Swag.require(not g_Library.loaded)
    Swag.require(f.main.recentWnd.recentView.items.count == 1)
    Swag.require(f.main.recentWnd.recentView.selected == 0)
    Swag.require(f.main.editWnd.getCapture()!.file == capturePath)
    Swag.require(g_Library.files.count == 1)
}

// Captures created from an in-memory image use the preview overload directly. Keep that path
// bounded too, otherwise each new capture retains another thumbnail texture indefinitely.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    testPrepareRecentLibrary(f.main)

    let preview = Gui.Testing.indexedImage(32, 20)
    for i in 16 do
        f.main.recentWnd.addRecent(Format.toString("capture-%", i), preview, front: true)

    Swag.require(f.main.recentWnd.recentView.items.count == 15)
    Swag.require(f.main.recentWnd.recentView.items[0]!.file == "capture-15")
    Swag.require(f.main.recentWnd.recentView.items.back()!.file == "capture-1")

    f.main.recentWnd.recentView.selected = 14
    f.main.recentWnd.addRecent("one-more", preview, front: true)
    Swag.require(f.main.recentWnd.recentView.selected == Swag.U64.Max)
}
