var g_Library: Library

// The captures and images in the library folder, and the folder itself.
struct Library
{
    files:        Array'File.FileInfo
    onDeleteFile: SigArray'func||(String)
    rootFolder:   String
    revision:     u64
    loaded:       bool

    // Resolved default folder, kept because the documents folder is a shell lookup and the
    // library grid asks for the folder once per item. See `getDefaultFolder`.
    defaultFolder: String
}

impl Library
{
    func ensureFolder(folder: String) fail
    {
        if not Directory.exists(folder) do
            try Directory.create(folder)

        let trash = Path.combine(folder, ".trash")
        if not Directory.exists(trash) do
            try Directory.create(trash)
    }

    func init() fail
    {
        try ensureFolder(getFolder())
    }

    // Returns the stable default folder. Application state stays here even when the user
    // points the capture library somewhere else, so that choice can be found next launch.
    //
    // The answer cannot change while the process runs, and reaching the documents folder is a
    // shell call: resolve it once. The library grid asks for the library folder once per item
    // as it filters, and paying that call per item is what made a large library crawl.
    func getDefaultFolder()->String
    {
        if not g_Library.defaultFolder.isEmpty() do
            return g_Library.defaultFolder

        let documents = Env.getSpecialDirectory(.UserDocuments)
        Swag.assert(not documents.isEmpty())

        g_Library.defaultFolder = Path.combine(documents, ProductName)
        return g_Library.defaultFolder
    }

    // Returns the configured folder holding captures and browsable images.
    //
    // Nothing here knows about testing: a sandboxed run answers the documents folder inside
    // its own root, so a test naturally gets an empty library of its own.
    func getFolder()->String
    {
        if not g_Library.rootFolder.isEmpty() do
            return g_Library.rootFolder
        return getDefaultFolder()
    }

    // Changes the root used for new captures and indexing, creating its private recycle
    // folder and invalidating the in-memory index.
    mtd setFolder(folder: String) fail
    {
        let target = folder.isEmpty() ? getDefaultFolder() : folder
        try ensureFolder(target)

        .rootFolder = folder
        .files.clear()
        .loaded   = false
        .revision += 1
    }

    // Deleted captures are moved here instead of being erased, so a mistaken delete can
    // be undone. It lives inside the library folder but the (non-recursive) capture
    // enumeration never descends into it, so trashed files stay out of the main list.
    func getTrashFolder()->String => Path.combine(getFolder(), ".trash")

    func enumerateTrash()->Array'File.FileInfo fail
    {
        var result: #returntype
        let files = try Directory.enumerateFiles(getTrashFolder())
        for file in files where Capture.isFileName(file.fullName) do
            result.add(file)
        return result
    }

    // Lists every item the library understands without pretending an ordinary image is a
    // capture. Sub-folders remain explicit navigation levels: tabs and lens entries.
    func enumerateSupportedFiles(folder: String)->Array'File.FileInfo fail
    {
        var result: #returntype
        let files = try Directory.enumerateFiles(folder)
        for fi in files where Capture.isFileName(fi.fullName) or Image.canLoad(fi.fullName) do
            result.add(fi)
        return result
    }

    // Picks a destination inside `folder` for `name` that does not collide with an
    // existing file, prefixing "<n>_" as needed. Both the trash and the restore paths
    // must stay unique so one delete/restore never overwrites another capture.
    func uniqueName(folder: String, name: String)->String
    {
        let base = Path.fileName(name) orelse ""
        var dst  = Path.combine(folder, base)
        var n    = 1
        while File.exists(dst)
        {
            // Build "<n>_<base>" without passing the name through a formatted `any` arg,
            // then combine (Path.combine wants a plain string, so convert the String).
            var candidate = Format.toString("%_", n)
            candidate += base
            dst       = Path.combine(folder, candidate)
            n         += 1
        }

        return dst
    }

    // Copy+delete because the filesystem module has no atomic move; on any failure we
    // leave the source untouched and remove the partial copy, so a capture is never lost.
    func moveFile(dstFolder: String, srcFile: String)->String
    {
        let dst = uniqueName(dstFolder, srcFile)

        catch File.duplicate(dst, srcFile) do
            return ""

        catch File.delete(srcFile)
        {
            discard catch File.delete(dst)
            return ""
        }

        return dst
    }

    func emptyTrash()
    {
        let files = catch enumerateTrash()
        {
            return
        }

        for fi in files do
            discard catch File.delete(fi.fullName)
    }

    // Brings a trashed capture back into the library folder. Returns the restored path
    // (empty on failure) so the caller can register it again.
    func restoreFile(trashFile: String)->String => moveFile(getFolder(), trashFile)

    func newFileName()->String
    {
        let t        = Time.DateTime.now()
        var fileName = Format.toString("%_%_%_%_%_%_%", t.month, t.day, t.year, t.hour, t.minute, t.second, Guid64.random())
        fileName += CaptureFileExtension
        return Path.combine(getFolder(), fileName)
    }

    mtd fill()
    {
        .files    = catch enumerateSupportedFiles(getFolder())
        .loaded   = true
        .revision += 1
    }

    // Soft-delete: move the capture to the recycle bin rather than erasing it. The
    // observers (recent strip, library grid) still see it leave the library through
    // onDeleteFile; it can be brought back from the trash view.
    mtd removeFile(name: string)
    {
        // An observer can destroy the object that supplied `name` (the recent strip does
        // exactly that). Take a view, whose borrow does not cover the text, and keep an owned
        // path alive until every observer has returned.
        let stableName = String.from(name)
        if not Capture.isFile(stableName) do
            return

        // A background save may still be writing this capture; if the move happened
        // first, the save would land its temporary right back at the removed path.
        discard g_CaptureSaves.flush(stableName)

        for fi, idx in .files
        {
            if fi.fullName == stableName
            {
                let trashed = moveFile(getTrashFolder(), stableName)
                if not trashed.isEmpty()
                {
                    .files.removeAtOrdered(idx)
                    .revision += 1
                    .onDeleteFile.call(stableName)
                }

                break
            }
        }
    }

    // Moves the capture or the image `name` to `folder` and returns where it went, empty when it
    // could not move. A file of the library leaves it through `onDeleteFile`, and comes back in
    // when `folder` is the library itself. `name` must outlive the observers of `onDeleteFile`,
    // which may destroy the item it was read from: the caller passes a copy it owns.
    mtd moveTo(name: String, folder: String)->String
    {
        discard g_CaptureSaves.flush(name)
        let dst = moveFile(folder, name)
        if dst.isEmpty() do
            return dst

        for fi, idx in .files where fi.fullName == name
        {
            .files.removeAtOrdered(idx)
            .revision += 1
            .onDeleteFile.call(name)
            break
        }

        if folder == getFolder() do
            .addFile(dst)
        return dst
    }

    mtd addFile(name: String)
    {
        let file = catch File.info(name)
        {
            return
        }

        .files.add(file)
        .revision += 1
    }
}
