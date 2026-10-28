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
    Swag.assert(not File.exists(u1))

    let moved = Library.moveFile(trash, src)
    Swag.assert(not moved.isEmpty())
    Swag.assert(not File.exists(src))
    Swag.assert(File.exists(moved))

    let u2 = Library.uniqueName(trash, moved)
    Swag.assert(u2 != moved)
    Swag.assert(not File.exists(u2))

    // Restore brings the capture back into the library folder.
    let restored = Library.restoreFile(moved)
    Swag.assert(not restored.isEmpty())
    Swag.assert(not File.exists(moved))
    Swag.assert(File.exists(restored))

    discard catch File.delete(restored)
}

// Renaming a capture that is not the one open in the editor updates the title on disk
// without destroying the (heavier) data the in-memory copy might not carry.
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

    f.main.setCaptureTitle(path, "Renamed")

    let loaded = expect Capture.load(path)
    defer Memory.delete(loaded)
    Swag.assert(loaded.title == "Renamed")
    Swag.assert(loaded.width == 8)
    Swag.assert(loaded.backImg.isValid())
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
    Swag.assert(image.isValid())
    Swag.assert(image.width == 20)
    Swag.assert(image.height == 14)
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
    Swag.assert(lib.currentFolder() == Library.getFolder())
    lib.updateFolderMode()
    Swag.assert(lib.titleLabel.name == appStrings().act_Library)
    Swag.assert(lib.tabFolders.count >= 2 and lib.tabFolders[0] == Library.getFolder())
    Swag.assert(lib.folderTabs.selectedIndex == 0)
    Swag.assert(lib.tabFolders.contains(Library.getTrashFolder()))

    // The recycle bin is one of the tabs; choosing it opens it and names the page after it.
    for folder, i in lib.tabFolders where folder[] == Library.getTrashFolder()
    {
        lib.folderTabs.setSelectedIndex(cast(u32, i))
        break
    }

    Swag.assert(lib.currentFolder() == Library.getTrashFolder())
    Swag.assert(lib.trashMode)
    Swag.assert(lib.titleLabel.name == appStrings().act_RecycleBin)

    lib.setTrashMode(false)
    Swag.assert(lib.currentFolder() == Library.getFolder())
    Swag.assert(lib.titleLabel.name == appStrings().act_Library)
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
    Swag.assert(lib.currentFolder() == Library.getTrashFolder())
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
    Swag.assert(not itCapture.preview.isValid())
    Swag.assert(itCapture.haar.size == 0)
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
    Swag.assert(File.exists(exported))
    let image = expect Image.load(exported)
    Swag.assert(image.width == 24)
    Swag.assert(image.height == 16)
}
