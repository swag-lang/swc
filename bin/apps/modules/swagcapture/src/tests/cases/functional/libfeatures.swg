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

    let image = Clipboard.getImage()
    Swag.require(image.isValid())
    Swag.require(image.width == 20)
    Swag.require(image.height == 14)
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
