#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Soft-delete plumbing: a capture can be moved to the recycle bin and brought back,
// and name collisions never overwrite an existing trashed/restored capture.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    expect Library.init()

    // A source capture file living in the temp area. Everything this test writes into
    // the (real) recycle bin and library folder is cleaned up in a defer so a failed
    // assertion can never leave stray captures behind for the running app to load.
    let src  = testTempCapturePath()
    let base = Path.fileName(src)
    defer
    {
        discard catch File.delete(src)
        discard catch File.delete(Path.combine(Library.getTrashFolder(), base))
        discard catch File.delete(Path.combine(Library.getFolder(), base))
    }

    let cap = Memory.new'Capture()
    cap.width, cap.widthOrg   = 8
    cap.height, cap.heightOrg = 6
    cap.backImg               = Gui.Testing.indexedImage(8, 6)
    cap.file                  = src
    cap.changed               = true
    expect cap.save()
    Memory.delete(cap)

    let trash = Library.getTrashFolder()

    let u1 = Library.uniqueName(trash, src)
    Swag.require(not File.exists(u1))

    let moved = Library.moveFile(trash, src)
    Swag.require(not moved.isEmpty())
    Swag.require(not File.exists(src))
    Swag.require(File.exists(moved))

    let u2 = Library.uniqueName(trash, moved)
    Swag.require(u2 != moved)
    Swag.require(not File.exists(u2))

    // Restore brings the capture back into the library folder.
    let restored = Library.restoreFile(moved)
    Swag.require(not restored.isEmpty())
    Swag.require(not File.exists(moved))
    Swag.require(File.exists(restored))

    discard catch File.delete(restored)
}

// Renaming and marking an inactive capture update its model and library header while preserving
// the exact compressed background chunk.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let cap = Memory.new'Capture()
    cap.width, cap.widthOrg   = 8
    cap.height, cap.heightOrg = 6
    cap.backImg = Gui.Testing.indexedImage(8, 6)
    let path = testTempCapturePath()
    defer discard catch File.delete(path)
    cap.file    = path
    cap.changed = true
    expect cap.save()
    Memory.delete(cap)

    var before: Scc.Reader
    expect before.initialize(path)
    Swag.require(before.chunks().count == 2)
    let backgroundId    = before.chunks()[1].id
    let backgroundCodec = before.chunks()[1].codecId
    let backgroundBytes = expect before.readStoredChunk(backgroundId)
    before.close()

    f.main.setCaptureTitle(path, "Renamed")

    var tags: Array'String
    tags.add("reviewed")
    let favorite = true
    let rating   = 4'u8
    let library  = f.setupLibraryWnd()
    library.updateMetadata(path, tags: &tags, favorite: &favorite, rating: &rating)
    Swag.require(g_CaptureSaves.writing(path))
    Swag.require(g_CaptureSaves.flush(path).isEmpty())

    let loaded = expect Capture.load(path)
    defer Memory.delete(loaded)
    Swag.require(loaded.title == "Renamed")
    Swag.require(loaded.width == 8)
    Swag.require(loaded.backImg.isValid())
    Swag.require(loaded.tags.count == 1 and loaded.tags[0] == "reviewed")
    Swag.require(loaded.favorite and loaded.rating == 4)

    let preview = expect Capture.load(path, preview: true)
    defer Memory.delete(preview)
    Swag.require(preview.title == "Renamed")
    Swag.require(preview.tags.count == 1 and preview.tags[0] == "reviewed")
    Swag.require(preview.favorite and preview.rating == 4)

    var after: Scc.Reader
    expect after.initialize(path)
    Swag.require(after.chunks().count == 2)
    Swag.require(after.chunks()[1].id == backgroundId)
    Swag.require(after.chunks()[1].codecId == backgroundCodec)
    let unchanged = expect after.readStoredChunk(backgroundId)
    Swag.require(Slice.equals(unchanged.toSlice(), backgroundBytes.toSlice()))
}

// A metadata write queued behind an automatic save edits the version that just landed.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    let path = testTempCapturePath()
    defer discard catch File.delete(path)
    f.capture.file = path
    f.capture.title = "First version"
    f.capture.changed = true
    expect f.capture.save()

    f.capture.title = "Automatic save"
    f.capture.changed = true
    expect f.capture.scheduleSave()
    let rating = 3'u8
    f.main.queueCaptureMetadata(path, rating: &rating)
    Swag.require(g_CaptureSaves.writing(path))
    Swag.require(g_CaptureSaves.flush(path).isEmpty())

    let loaded = expect Capture.load(path)
    defer Memory.delete(loaded)
    Swag.require(loaded.title == "Automatic save" and loaded.rating == 3)
}

// Duplicating a document gives the copy a new identity and no external link while preserving
// the exact compressed background block.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let source = testTempCapturePath()
    let target = testTempCapturePath()
    defer
    {
        discard catch File.delete(source)
        discard catch File.delete(target)
    }

    let capture = Memory.new'Capture()
    capture.width, capture.widthOrg   = 18
    capture.height, capture.heightOrg = 12
    capture.backImg = Gui.Testing.indexedImage(18, 12)
    capture.file = source
    capture.linkedImage = Path.combine(Library.getFolder(), "original.png")
    capture.linkedUpToDate = false
    capture.changed = true
    expect capture.save()
    Memory.delete(capture)

    var before: Scc.Reader
    expect before.initialize(source)
    let originalId = before.id()
    Swag.require(before.chunks().count == 2)
    let background = before.chunks()[1]
    let stored = expect before.readStoredChunk(background.id)
    before.close()

    expect Capture.duplicateDocument(source, target)
    var after: Scc.Reader
    expect after.initialize(target)
    Swag.require(after.id() != originalId and after.generation() == 1)
    let copied = expect after.readStoredChunk(background.id)
    Swag.require(Slice.equals(copied.toSlice(), stored.toSlice()))
    after.close()

    let full = expect Capture.load(target)
    defer Memory.delete(full)
    Swag.require(full.backImg.isValid() and full.width == 18 and full.height == 12)
    Swag.require(full.linkedImage.isEmpty() and full.linkedUpToDate)
    let preview = expect Capture.load(target, preview: true)
    defer Memory.delete(preview)
    Swag.require(preview.linkedImage.isEmpty() and preview.linkedUpToDate)
}

// Copying a stored capture from the library places its full-resolution image on the
// clipboard, composited from the file rather than the low-res preview.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let cap = Memory.new'Capture()
    cap.width, cap.widthOrg   = 20
    cap.height, cap.heightOrg = 14
    cap.backImg = Gui.Testing.indexedImage(20, 14)
    let path = testTempCapturePath()
    defer discard catch File.delete(path)
    cap.file    = path
    cap.changed = true
    expect cap.save()
    Memory.delete(cap)

    f.main.copyLibraryImage(path)
    f.main.copyJob!.task.wait()
    f.gui.pump()

    let image = Clipboard.getImage()
    Swag.require(image.isValid())
    Swag.require(image.width == 20)
    Swag.require(image.height == 14)
}

// A newer library copy replaces an in-flight request and waits for writes to its file.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    let firstPath  = testTempCapturePath()
    let secondPath = testTempCapturePath()
    defer
    {
        discard catch File.delete(firstPath)
        discard catch File.delete(secondPath)
        Clipboard.clear()
    }

    let first = Memory.new'Capture()
    first.width, first.widthOrg   = 9
    first.height, first.heightOrg = 7
    first.backImg = Gui.Testing.indexedImage(9, 7)
    first.file = firstPath
    first.changed = true
    expect first.save()
    Memory.delete(first)

    let second = Memory.new'Capture()
    second.width, second.widthOrg   = 13
    second.height, second.heightOrg = 7
    second.backImg = Gui.Testing.indexedImage(13, 7)
    second.file = secondPath
    second.changed = true
    expect second.save()
    Memory.delete(second)

    f.main.copyLibraryImage(firstPath)
    let firstJob = unwrap f.main.copyJob
    let rating = 4'u8
    f.main.queueCaptureMetadata(secondPath, rating: &rating)
    f.main.copyLibraryImage(secondPath)
    firstJob.task.wait()
    f.gui.pump()
    Swag.require(f.main.copyJob == null and f.main.copyTimer != null)

    Swag.require(g_CaptureSaves.flush(secondPath).isEmpty())
    f.gui.fireTimer(f.main.copyTimer)
    Swag.require(f.main.copyJob and f.main.copyJob.file == secondPath)
    f.main.copyJob.task.wait()
    f.gui.pump()

    let copied = Clipboard.getImage()
    Swag.require(copied.isValid() and copied.width == 13 and copied.height == 7)
    let stored = expect Capture.load(secondPath, preview: true)
    defer Memory.delete(stored)
    Swag.require(stored.rating == 4)
}

// The page is named after the folder it shows, and its folders are tabs: the library first, its
// sub-folders after it, the recycle bin among them; choosing a tab opens its folder.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    expect Library.init()

    f.main.libWnd = LibraryWnd.create(f.main)
    let lib = f.main.libWnd
    defer lib.requestClose()

    // Default (empty) current folder falls back to the library folder.
    Swag.require(lib.currentFolder() == Library.getFolder())
    lib.updateFolderMode()
    Swag.require(lib.titleLabel.name == appStrings().act_Library)
    Swag.require(lib.tabFolders.count >= 2 and lib.tabFolders[0] == Library.getFolder())
    Swag.require(lib.folderTabs.selectedIndex == 0)
    Swag.require(lib.tabFolders.contains(Library.getTrashFolder()))

    // The recycle bin is one of the tabs; choosing it opens it and names the page after it.
    for folder, i in lib.tabFolders where folder[] == Library.getTrashFolder()
    {
        lib.folderTabs.setSelectedIndex(cast(u32, i))
        break
    }

    Swag.require(lib.currentFolder() == Library.getTrashFolder())
    Swag.require(lib.trashMode)
    Swag.require(lib.titleLabel.name == appStrings().act_RecycleBin)

    lib.setTrashMode(false)
    Swag.require(lib.currentFolder() == Library.getFolder())
    Swag.require(lib.titleLabel.name == appStrings().act_Library)
}

// The lens of the library lists its folders, the recycle bin among them, and choosing one opens it.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    expect Library.init()

    f.main.libWnd = LibraryWnd.create(f.main)
    let lib = f.main.libWnd
    defer lib.requestClose()
    lib.updateFolderMode()

    var results: Lens.Results
    lib.describeLens(&results)
    var trash: *Lens.Entry?
    for section in results.sections where section!.label == appStrings().ui_BarFolders
    {
        for &entry in section.entries where entry.title == appStrings().act_RecycleBin do
            trash = entry
    }

    let run = unwrap (unwrap trash).run
    run()
    Swag.require(lib.currentFolder() == Library.getTrashFolder())
}

// Loading a capture that has no preview (e.g. an older file, or one restored from the
// recycle bin) must not fault: Haar features are simply skipped. Regression for a crash
// where quickExtractHaarFeatures asserted on a zero-sized preview image.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let lib  = f.setupLibraryWnd()
    let view = lib.view

    let cap = Memory.new'Capture()
    cap.width, cap.widthOrg   = 8
    cap.height, cap.heightOrg = 6
    cap.backImg = Gui.Testing.indexedImage(8, 6)
    let path = testTempCapturePath()
    defer discard catch File.delete(path)
    cap.file    = path
    cap.changed = true
    expect cap.save()
    Memory.delete(cap)

    let it = view.allItems.addNew()
    it.fi.fullName = path
    view.items.add(it)
    view.loadOne(it)

    let itCapture = unwrap it.capture
    Swag.require(not itCapture.preview.isValid())
    Swag.require(itCapture.haar.size == 0)
}

// Batch export uses the full capture, not the lightweight library preview, and writes a
// regular PNG that another application can open.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let lib = f.setupLibraryWnd()

    let capture = Memory.new'Capture()
    capture.width, capture.widthOrg   = 24
    capture.height, capture.heightOrg = 16
    capture.backImg = Gui.Testing.indexedImage(24, 16)
    let source = testTempCapturePath()
    capture.file    = source
    capture.changed = true
    expect capture.save()
    Memory.delete(capture)

    let folder = Path.combine(Library.getFolder(), Format.toString("export-%", Guid64.random()))
    expect Directory.create(folder)
    let exported = Path.combine(folder, Format.toString("%.png", Path.fileNameWithoutExtension(source) orelse "capture"))
    defer
    {
        discard catch File.delete(source)
        discard catch File.delete(exported)
        discard catch Directory.delete(folder)
    }

    expect lib.exportCapture(source, folder)
    Swag.require(File.exists(exported))
    let image = expect Image.load(exported)
    Swag.require(image.width == 24)
    Swag.require(image.height == 16)
}

// Exporting multiple library pictures decodes each capture on a worker in selection order.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let library = f.setupLibraryWnd()

    let firstPath  = testTempCapturePath()
    let secondPath = testTempCapturePath()
    let folder = Path.combine(Library.getFolder(), Format.toString("export-%", Guid64.random()))
    expect Directory.create(folder)
    defer
    {
        discard catch File.delete(firstPath)
        discard catch File.delete(secondPath)
        discard catch Directory.delete(folder, recurse: true)
    }

    let first = Memory.new'Capture()
    first.width, first.widthOrg   = 16
    first.height, first.heightOrg = 10
    first.backImg = Gui.Testing.indexedImage(16, 10)
    first.file = firstPath
    first.changed = true
    expect first.save()
    Memory.delete(first)

    let second = Memory.new'Capture()
    second.width, second.widthOrg   = 19
    second.height, second.heightOrg = 12
    second.backImg = Gui.Testing.indexedImage(19, 12)
    second.file = secondPath
    second.changed = true
    expect second.save()
    Memory.delete(second)

    var files: Array'String
    files.add(firstPath)
    files.add(secondPath)
    library.beginExport(files, folder)
    Swag.require(library.exporting and library.exportJob != null)
    for 4
    {
        if not library.exporting do
            break
        Swag.require(library.exportJob != null)
        library.exportJob.task.wait()
        f.gui.pump()
    }
    Swag.require(not library.exporting and library.exportJob == null)

    let firstImage = expect Image.load(Path.combine(folder, Format.toString("%.png", Path.fileNameWithoutExtension(firstPath) orelse "capture")))
    let secondImage = expect Image.load(Path.combine(folder, Format.toString("%.png", Path.fileNameWithoutExtension(secondPath) orelse "capture")))
    Swag.require(firstImage.width == 16 and firstImage.height == 10)
    Swag.require(secondImage.width == 19 and secondImage.height == 12)
}
