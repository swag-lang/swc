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
    @assert(!File.exists(u1))

    let moved = Library.moveFile(trash, src)
    @assert(!moved.isEmpty())
    @assert(!File.exists(src))
    @assert(File.exists(moved))

    let u2 = Library.uniqueName(trash, moved)
    @assert(u2 != moved)
    @assert(!File.exists(u2))

    // Restore brings the capture back into the library folder.
    let restored = Library.restoreFile(moved)
    @assert(!restored.isEmpty())
    @assert(!File.exists(moved))
    @assert(File.exists(restored))

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
    cap.backImg               = Gui.Testing.indexedImage(8, 6)
    let path = testTempCapturePath()
    defer discard catch File.delete(path)
    cap.file    = path
    cap.changed = true
    expect cap.save()
    Memory.delete(cap)

    f.main.setCaptureTitle(path, "Renamed")

    let loaded = expect Capture.load(path)!
    defer Memory.delete(loaded)
    @assert(loaded.title == "Renamed")
    @assert(loaded.width == 8)
    @assert(loaded.backImg.isValid())
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
    cap.backImg               = Gui.Testing.indexedImage(20, 14)
    let path = testTempCapturePath()
    defer discard catch File.delete(path)
    cap.file    = path
    cap.changed = true
    expect cap.save()
    Memory.delete(cap)

    f.main.copyLibraryImage(path)

    let img = Clipboard.getImage()
    @assert(img.isValid())
    @assert(img.width == 20)
    @assert(img.height == 14)
}

// The library breadcrumb mirrors the real on-disk folder: it ends at the library folder
// normally and at the recycle-bin folder in trash mode, each level carrying its full path.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let lib = f.setupLibraryWnd()

    // The headless fixture does not build the real toolbar, so attach a breadcrumb here.
    lib.breadcrumb = BreadcrumbCtrl.create(cast(*Wnd) lib, {0, 0, 600, 32})

    // Default (empty) current folder falls back to the library folder.
    @assert(lib.currentFolder() == Library.getFolder())
    lib.updateBreadcrumb()
    @assert(lib.breadcrumb.items.count > 0)
    let lastNormal = lib.breadcrumb.items.back()
    @assert(lastNormal.name == (Path.fileName(Library.getFolder()) orelse ""))
    @assert(lastNormal.tag == Library.getFolder())

    // Point the library at the recycle bin folder.
    lib.curFolder = Library.getTrashFolder()
    @assert(lib.currentFolder() == Library.getTrashFolder())
    lib.updateBreadcrumb()
    let lastTrash = lib.breadcrumb.items.back()
    @assert(lastTrash.tag == Library.getTrashFolder())

    // The recycle-bin leaf sits directly under the sCapture folder.
    @assert(lib.breadcrumb.items.count >= 2)
    let parentOfTrash = lib.breadcrumb.items[lib.breadcrumb.items.count - 2]
    @assert(parentOfTrash.tag == Library.getFolder())
}

// The breadcrumb drop-down lists a level's real sub-folders and keeps their path ids in
// owned storage (menu items hold ids as non-owning slices, so the source data — a local
// directory listing — must be copied or the id dangles once the popup is shown).
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()
    let lib = f.setupLibraryWnd()
    lib.breadcrumb = BreadcrumbCtrl.create(cast(*Wnd) lib, {0, 0, 600, 32})

    expect Library.init()
    lib.curFolder = Library.getFolder()
    lib.updateBreadcrumb()

    // Fill the drop-down for the sCapture level (the last one).
    let idx  = lib.breadcrumb.items.count - 1
    let menu = MenuCtrl.createPopup(cast(*Wnd) lib)
    lib.fillBreadcrumbMenu(lib.breadcrumb, idx, menu)

    // Its recycle bin sub-folder is listed, with its path preserved in owned storage.
    @assert(!lib.menuPaths.isEmpty())
    var foundTrash = false
    for p in lib.menuPaths
    {
        if dref p == Library.getTrashFolder() do
            foundTrash = true
    }

    @assert(foundTrash)

    menu.destroy()
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
    cap.backImg               = Gui.Testing.indexedImage(8, 6)
    let path = testTempCapturePath()
    defer discard catch File.delete(path)
    cap.file    = path
    cap.changed = true
    expect cap.save()
    Memory.delete(cap)

    let it = view.allItems.addNew()
    it.fi.fullname = path
    view.items.add(it)
    view.loadOne(it)

    let itCapture = it.capture!
    @assert(!itCapture.preview.isValid())
    @assert(itCapture.haar.size == 0)
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
    capture.backImg                   = Gui.Testing.indexedImage(24, 16)
    let source = testTempCapturePath()
    capture.file    = source
    capture.changed = true
    expect capture.save()
    Memory.delete(capture)

    let folder = Path.combine(Library.getFolder(), Format.toString("export-%", Guid64.random().toString()))
    expect Directory.create(folder)
    let exported = Path.combine(folder, Format.toString("%.png", Path.fileNameWithoutExtension(source) orelse "capture"))
    defer
    {
        discard catch File.delete(source)
        discard catch File.delete(exported)
        discard catch Directory.delete(folder)
    }

    expect lib.exportCapture(source, folder)
    @assert(File.exists(exported))
    let image = expect Image.load(exported)
    @assert(image.width == 24)
    @assert(image.height == 16)
}
