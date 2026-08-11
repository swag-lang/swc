#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, File

func testPrepareSavedCapture(capture: *Capture)->String
{
    let path = testTempCapturePath()
    capture.file    = path
    capture.changed = true

    expect capture.save()
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

func testHasSCaptureFileMetadata(img: Image, captureFile: String)->bool
{
    for md in img.metadata
    {
        if md.isTag("sCapture.File")
        {
            if testSamePath(cast(string) md.toSlice(), captureFile) do
                return true
        }
    }

    return false
}

func testPrepareRecentLibrary(main: *MainWnd)
{
    // Each scenario owns the callbacks it registers. Drop previous closures before their
    // captured windows disappear, then restore a pristine library value.
    @drop(&g_Library, 1)
    @init(&g_Library, 1)

    expect Library.init()
    g_Library.loaded = true

    if !@isset(main.recentWnd) do
        main.recentWnd = RecentWnd.create(main, main)
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

    @assert(Gui.Testing.actionExecute'ActionFile(f.main, ActionFile.NewImage))
    f.gui.pump()

    @assert(f.gui.autoHandled)
    @assert(f.gui.openedSurfaceCount() == 0)

    let capture       = f.main.getCapture()!
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

    @assert(Gui.Testing.actionExecute'ActionFile(f.main, ActionFile.NewFromClipboard))
    f.gui.pump()

    let capture       = f.main.getCapture()!
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
}

// Open Image drives the real file dialog, loads a real PNG, then persists a capture.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)
    testPrepareRecentLibrary(f.main)

    let sourcePath = Gui.Testing.tempFilePath("scapture-", ".png")
    defer discard catch File.delete(sourcePath)
    var source = Gui.Testing.indexedImage(21, 13)
    expect source.save(sourcePath)
    f.gui.acceptModalFileDialog(sourcePath)

    @assert(Gui.Testing.actionExecute'ActionFile(f.main, ActionFile.OpenImage))
    f.gui.pump()

    @assert(f.gui.autoHandled)
    @assert(f.gui.openedSurfaceCount() == 0)

    let capture       = f.main.getCapture()!
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
}

// Dragging a capture out offers it as a PNG named after it, encoded only when a target asks.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)
    testPrepareRecentLibrary(f.main)

    f.capture.width   = 18
    f.capture.height  = 11
    f.capture.backImg = Gui.Testing.indexedImage(18, 11)
    f.capture.file    = testTempCapturePath()

    var img = f.capture.toImage()

    var data: Gui.DragData
    f.main.fillDragData(&data, f.capture, &img)

    // The gesture announces a file named after the capture, and has encoded nothing to do it.
    @assert(data.hasImage())
    @assert(data.contents.count == 1)
    @assert(Path.lowercaseExtension(data.contents[0].name) == ".png")
    @assert(Path.fileNameWithoutExtension(data.contents[0].name) == Path.fileNameWithoutExtension(f.capture.file))
    @assert(!data.contents[0].isReady())

    // Asking for the file is what produces it, and what it holds is the capture, readable by
    // anything that reads a PNG.
    let bytes = data.contentData(0)
    @assert(@countof(bytes) != 0)

    let readBack = expect Image.decode("drag.png", bytes, {})
    @assert(readBack.width == 18)
    @assert(readBack.height == 11)
}

// The whole drag-out path runs with no desktop under it, and leaves nothing behind.
//
// This is the point of producing the file on demand: no target ever asks, so the PNG is never
// encoded and never written, where exporting it up front left one file per abandoned gesture.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)
    testPrepareRecentLibrary(f.main)

    f.capture.width   = 9
    f.capture.height  = 6
    f.capture.backImg = Gui.Testing.indexedImage(9, 6)
    f.capture.file    = testTempCapturePath()

    f.main.dragOutCapture(f.editView)

    let temp     = Env.getSpecialDirectory(Env.SpecialDirectory.Temp)
    var expected = String.from(Path.fileNameWithoutExtension(f.capture.file) orelse "capture")
    expected += ".png"
    let exported = Path.combine(Path.combine(temp.toString(), "sCapture").toString(), expected.toString())
    @assert(!File.exists(exported))
}

// A picture dropped on the editor opens it, exactly as the Open command does.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)
    testPrepareRecentLibrary(f.main)

    let sourcePath = Gui.Testing.tempFilePath("scapture-drop-", ".png")
    defer discard catch File.delete(sourcePath)
    var source = Gui.Testing.indexedImage(23, 17)
    expect source.save(sourcePath)

    @assert(f.gui.dropFilesOnWnd(f.editView, [sourcePath.toString()]) == Gui.DropEffect.Copy)

    let capture       = f.main.getCapture()!
    let generatedPath = capture.file
    defer
    {
        discard catch File.delete(generatedPath)
        g_Library.files.clear()
    }

    @assert(capture.width == 23)
    @assert(capture.height == 17)
    @assert(testSamePath(capture.linkedImage, sourcePath))
    @assert(File.exists(generatedPath))
    @assert(f.main.recentWnd.recentView.items.count == 1)
}

// Several pictures dropped at once open one capture each, in the order they were listed.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)
    testPrepareRecentLibrary(f.main)

    let firstPath = Gui.Testing.tempFilePath("scapture-drop-a-", ".png")
    let lastPath  = Gui.Testing.tempFilePath("scapture-drop-b-", ".png")
    defer discard catch File.delete(firstPath)
    defer discard catch File.delete(lastPath)
    var first = Gui.Testing.indexedImage(12, 9)
    var last  = Gui.Testing.indexedImage(31, 7)
    expect first.save(firstPath)
    expect last.save(lastPath)

    @assert(f.gui.dropFilesOnWnd(f.editView, [firstPath.toString(), lastPath.toString()]) == Gui.DropEffect.Copy)

    defer g_Library.files.clear()
    @assert(f.main.recentWnd.recentView.items.count == 2)

    // The last one dropped is the one left on the easel.
    let capture = f.main.getCapture()!
    defer discard catch File.delete(capture.file)
    @assert(capture.width == 31)
    @assert(capture.height == 7)
    @assert(testSamePath(capture.linkedImage, lastPath))
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
    @assert(f.gui.dropFilesOnWnd(f.editView, ["c:/notes/readme.txt"]) == Gui.DropEffect.None)
    @assert(f.main.getCapture() == before)
    @assert(f.main.recentWnd.recentView.items.count == 0)
}

// Save As Image writes a real PNG that can be loaded back with sCapture metadata.
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
    let pngPath = Gui.Testing.tempFilePath("scapture-", ".png")
    defer discard catch File.delete(pngPath)
    f.main.doSaveAsImage(pngPath)
    f.gui.pump()

    @assert(File.exists(pngPath))

    let saved = expect Image.load(pngPath)
    @assert(saved.isValid())
    @assert(saved.width == 32)
    @assert(saved.height == 20)
    @assert(saved.metadata.count > 0)
    @assert(testHasSCaptureFileMetadata(saved, capturePath))
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
    let pngPath = Gui.Testing.tempFilePath("scapture-", ".png")
    defer discard catch File.delete(pngPath)
    f.gui.acceptModalFileDialog(pngPath)

    f.main.sendCommandEvent(ActionFile.SaveAsImage)
    f.gui.pump()

    @assert(f.gui.autoHandled)
    @assert(f.gui.openedSurfaceCount() == 0)
    @assert(File.exists(pngPath))

    let saved = expect Image.load(pngPath)
    @assert(saved.isValid())
    @assert(saved.width == 34)
    @assert(saved.height == 22)
    @assert(testHasSCaptureFileMetadata(saved, capturePath))
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
    let pngPath = Gui.Testing.tempFilePath("scapture-", ".png")
    defer discard catch File.delete(pngPath)
    var oldImage = Image.create(3, 2, .BGRA8)
    oldImage.fill(ColorRed)
    expect oldImage.save(pngPath)
    f.gui.acceptModalFileDialog(pngPath)
    f.gui.thenClickModalButton(Dialog.BtnYes)

    f.main.sendCommandEvent(ActionFile.SaveAsImage)
    f.gui.pump()

    @assert(f.gui.autoHandled)
    @assert(f.gui.openedSurfaceCount() == 0)

    let saved = expect Image.load(pngPath)
    @assert(saved.isValid())
    @assert(saved.width == 40)
    @assert(saved.height == 30)
    @assert(testHasSCaptureFileMetadata(saved, capturePath))
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
    let linkedPath = Gui.Testing.tempFilePath("scapture-", ".png")
    defer discard catch File.delete(linkedPath)
    f.main.doSaveAsImage(linkedPath, linked: true)
    f.gui.pump()

    @assert(File.exists(linkedPath))
    @assert(f.capture.linkedImage == linkedPath)
    @assert(f.capture.linkedUpToDate)

    let loaded = expect Capture.load(capturePath)!
    defer Memory.delete(loaded)
    @assert(loaded.linkedImage == linkedPath)
    @assert(loaded.linkedUpToDate)
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
    let linkedPath = Gui.Testing.tempFilePath("scapture-", ".png")
    defer discard catch File.delete(linkedPath)
    f.gui.acceptModalFileDialog(linkedPath)

    f.main.sendCommandEvent(ActionFile.SaveAsLinkedImage)
    f.gui.pump()

    @assert(f.gui.autoHandled)
    @assert(f.gui.openedSurfaceCount() == 0)
    @assert(File.exists(linkedPath))
    @assert(testSamePath(f.capture.linkedImage, linkedPath))
    @assert(f.capture.linkedUpToDate)

    let loaded = expect Capture.load(capturePath)!
    defer Memory.delete(loaded)
    @assert(testSamePath(loaded.linkedImage, linkedPath))
    @assert(loaded.linkedUpToDate)
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
    let linkedPath = Gui.Testing.tempFilePath("scapture-", ".png")
    defer discard catch File.delete(linkedPath)
    f.capture.linkedImage    = linkedPath
    f.capture.linkedUpToDate = false
    f.main.editorOptions.confirmLinkedOverwrite = false

    f.main.sendCommandEvent(ActionFile.UpdateLinkedImage)
    f.gui.pump()

    @assert(File.exists(linkedPath))
    @assert(f.capture.linkedUpToDate)

    let linked = expect Image.load(linkedPath)
    @assert(linked.isValid())
    @assert(linked.width == 26)
    @assert(linked.height == 16)
    @assert(testHasSCaptureFileMetadata(linked, capturePath))

    let loaded = expect Capture.load(capturePath)!
    defer Memory.delete(loaded)
    @assert(loaded.linkedImage == linkedPath)
    @assert(loaded.linkedUpToDate)
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
    let linkedPath = Gui.Testing.tempFilePath("scapture-", ".png")
    defer discard catch File.delete(linkedPath)
    f.capture.linkedImage    = linkedPath
    f.capture.linkedUpToDate = false
    f.main.editorOptions.confirmLinkedOverwrite = true

    f.gui.clickModalButtonWhenShown(Dialog.BtnYes)

    f.main.sendCommandEvent(ActionFile.UpdateLinkedImage)
    f.gui.pump()

    @assert(f.gui.autoHandled)
    @assert(f.gui.openedSurfaceCount() == 0)
    @assert(File.exists(linkedPath))
    @assert(f.capture.linkedUpToDate)

    let linked = expect Image.load(linkedPath)
    @assert(linked.isValid())
    @assert(linked.width == 38)
    @assert(linked.height == 26)
    @assert(testHasSCaptureFileMetadata(linked, capturePath))

    let loaded = expect Capture.load(capturePath)!
    defer Memory.delete(loaded)
    @assert(testSamePath(loaded.linkedImage, linkedPath))
    @assert(loaded.linkedUpToDate)
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
    let linkedPath = Gui.Testing.tempFilePath("scapture-", ".png")
    f.capture.linkedImage    = linkedPath
    f.capture.linkedUpToDate = true
    f.capture.changed        = true
    expect f.capture.save()
    f.gui.clickModalButtonWhenShown(Dialog.BtnYes)

    f.main.sendCommandEvent(ActionFile.UnlinkImage)
    f.gui.pump()

    @assert(f.gui.autoHandled)
    @assert(f.gui.openedSurfaceCount() == 0)
    @assert(f.capture.linkedImage.isEmpty())
    @assert(!f.capture.linkedUpToDate)

    let loaded = expect Capture.load(capturePath)!
    defer Memory.delete(loaded)
    @assert(loaded.linkedImage.isEmpty())
    @assert(!loaded.linkedUpToDate)
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
    @assert(Gui.Testing.actionExecute'ActionFile(f.main, ActionFile.DupCapture))
    f.gui.pump()

    @assert(f.main.recentWnd.recentView.items.count == 1)
    @assert(f.main.recentWnd.recentView.selected == 0)

    let duplicatedPath = f.main.recentWnd.recentView.items[0]!.file
    defer
    {
        discard catch File.delete(duplicatedPath)
        g_Library.files.clear()
    }

    @assert(!testSamePath(duplicatedPath, originalPath))
    @assert(File.exists(duplicatedPath))

    let duplicated = expect Capture.load(duplicatedPath)!
    defer Memory.delete(duplicated)
    @assert(duplicated.forms.count == 1)
    @assert(duplicated.linkedImage == null)
}

// Delete Capture confirms through the real modal and removes the selected capture file.
#test
{
    var f: HeadlessFixture
    f.setup(registerHeadlessCommands: true)
    defer f.shutdown()
    testRegisterIoActions(f.main)
    testPrepareRecentLibrary(f.main)

    let capturePath = testPrepareSavedCapture(f.capture)
    g_Library.addFile(capturePath)

    let loaded = expect f.main.recentWnd.addRecent(capturePath, true, true)
    Memory.delete(loaded)
    @assert(f.main.recentWnd.recentView.selected == 0)

    f.gui.clickModalButtonWhenShown(Dialog.BtnYes)

    @assert(Gui.Testing.actionExecute'ActionFile(f.main, ActionFile.DeleteCapture))
    f.gui.pump()

    @assert(f.gui.autoHandled)
    @assert(f.gui.openedSurfaceCount() == 0)
    @assert(!File.exists(capturePath))
    @assert(g_Library.files.count == 0)
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

    @assert(f.gui.autoHandled)
    @assert(f.gui.openedSurfaceCount() == 0)
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
    other.backImg = Gui.Testing.indexedImage(37, 23)
    other.preview = Gui.Testing.indexedImage(32, 20)
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

    let saved = expect Capture.load(editorPath)!
    defer Memory.delete(saved)
    @assert(saved.title == "Unsaved editor title")
    @assert(f.main.editWnd.getCapture()!.file == otherPath)
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
    first.backImg = Gui.Testing.indexedImage(41, 29)
    first.preview = Gui.Testing.indexedImage(32, 20)
    let firstPath = testPrepareSavedCapture(first)
    defer
    {
        discard catch File.delete(firstPath)
        Memory.delete(first)
    }

    let second = Memory.new'Capture()
    second.width, second.widthOrg   = 43
    second.height, second.heightOrg = 31
    second.backImg = Gui.Testing.indexedImage(43, 31)
    second.preview = Gui.Testing.indexedImage(32, 20)
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

    @assert(f.main.recentWnd.recentView.items[0]!.file == secondPath)
    @assert(f.main.recentWnd.recentView.items[1]!.file == firstPath)
    @assert(Math.isEqualEpsilon(f.main.recentWnd.recentView.items[1]!.zoom, 1.75, 0.001))
    @assert(f.main.recentWnd.recentView.selected == 0)
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

    @assert(f.main.recentWnd.recentView.items.count == 15)
    @assert(f.main.recentWnd.recentView.items[0]!.file == "capture-15")
    @assert(f.main.recentWnd.recentView.items.back()!.file == "capture-1")

    f.main.recentWnd.recentView.selected = 14
    f.main.recentWnd.addRecent("one-more", preview, front: true)
    @assert(f.main.recentWnd.recentView.selected == Swag.U64.Max)
}
