#global #if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Soft-delete plumbing: a capture can be moved to the recycle bin and brought back,
// and name collisions never overwrite an existing trashed/restored capture.
#test
{
    var f: HeadlessFixture
    f.setup()
    defer f.shutdown()

    catch Library.init()
    @assert(@err == null)

    // A source capture file living in the temp area. Everything this test writes into
    // the (real) recycle bin and library folder is cleaned up in a defer so a failed
    // assertion can never leave stray captures behind for the running app to load.
    let src  = testTempCapturePath()
    let base = Path.getFileName(src)
    defer
    {
        discard catch File.delete(src)
        discard catch File.delete(Path.combine(Library.getTrashFolder(), base))
        discard catch File.delete(Path.combine(Library.getFolder(), base))
    }

    let cap = Memory.new'Capture()
    cap.width, cap.widthOrg = 8
    cap.height, cap.heightOrg = 6
    cap.backImg = Testing.indexedImage(8, 6)
    cap.file    = src
    cap.changed = true
    catch cap.save()
    @assert(@err == null)
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

    let cap = Memory.new'Capture()
    cap.width, cap.widthOrg = 8
    cap.height, cap.heightOrg = 6
    cap.backImg = Testing.indexedImage(8, 6)
    let path = testTempCapturePath()
    defer { discard catch File.delete(path) }
    cap.file    = path
    cap.changed = true
    catch cap.save()
    @assert(@err == null)
    Memory.delete(cap)

    f.main.setCaptureTitle(path, "Renamed")

    let loaded = catch Capture.load(path)
    @assert(@err == null)
    defer { Memory.delete(loaded) }
    @assert(loaded.title == "Renamed")
    @assert(loaded.width == 8)
    @assert(loaded.backImg.isValid())

    f.shutdown()
}

// Copying a stored capture from the library places its full-resolution image on the
// clipboard, composited from the file rather than the low-res preview.
#test
{
    var f: HeadlessFixture
    f.setup()

    let cap = Memory.new'Capture()
    cap.width, cap.widthOrg = 20
    cap.height, cap.heightOrg = 14
    cap.backImg = Testing.indexedImage(20, 14)
    let path = testTempCapturePath()
    defer { discard catch File.delete(path) }
    cap.file    = path
    cap.changed = true
    catch cap.save()
    @assert(@err == null)
    Memory.delete(cap)

    f.main.copyLibraryImage(path)

    let img = Clipboard.getImage()
    @assert(img.isValid())
    @assert(img.width == 20)
    @assert(img.height == 14)

    f.shutdown()
}

// Loading a capture that has no preview (e.g. an older file, or one restored from the
// recycle bin) must not fault: Haar features are simply skipped. Regression for a crash
// where quickExtractHaarFeatures asserted on a zero-sized preview image.
#test
{
    var f: HeadlessFixture
    f.setup()
    let lib  = f.setupLibraryWnd()
    let view = lib.view

    let cap = Memory.new'Capture()
    cap.width, cap.widthOrg = 8
    cap.height, cap.heightOrg = 6
    cap.backImg = Testing.indexedImage(8, 6)
    let path = testTempCapturePath()
    defer { discard catch File.delete(path) }
    cap.file    = path
    cap.changed = true
    catch cap.save()
    @assert(@err == null)
    Memory.delete(cap)

    let it = view.allItems.addNewPtr()
    it.fi.fullname = path
    view.items.add(it)
    view.loadOne(it)

    @assert(it.capture != null)
    @assert(!it.capture.preview.isValid())
    @assert(it.capture.haar.size == 0)

    f.shutdown()
}
