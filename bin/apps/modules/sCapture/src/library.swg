var g_Library: Library

struct Library
{
    files:        Array'File.FileInfo
    onDeleteFile: SigArray'func||(String)
    loaded:       bool
}

impl Library
{
    func init() fail
    {
        let str = getFolder()
        if !Directory.exists(str) do
            Directory.create(str)

        let trash = getTrashFolder()
        if !Directory.exists(trash) do
            Directory.create(trash)
    }

    // Returns the folder holding the captures.
    //
    // Nothing here knows about testing: a sandboxed run answers the documents folder inside
    // its own root, so a test naturally gets an empty library of its own.
    func getFolder()->String
    {
        let str = Env.getSpecialDirectory(.UserDocuments)
        Debug.assert(!str.isEmpty())
        return Path.combine(str, "sCapture")
    }

    // Deleted captures are moved here instead of being erased, so a mistaken delete can
    // be undone. It lives inside the library folder but the (non-recursive) capture
    // enumeration never descends into it, so trashed files stay out of the main list.
    func getTrashFolder()->String
    {
        return Path.combine(getFolder(), ".trash")
    }

    func enumerateTrash()->Array'File.FileInfo fail
    {
        return try Directory.enumerateFiles(getTrashFolder(), ".scapture")
    }

    // Pick a destination inside 'folder' for 'name' that does not collide with an
    // existing file, prefixing "<n>_" as needed. Both the trash and the restore paths
    // must stay unique so one delete/restore never overwrites another capture.
    func uniqueName(folder: String, name: String)->String
    {
        let base = Path.fileName(name) orelse ""
        var dst  = Path.combine(folder, base)
        var n    = 1
        while File.exists(dst)
        {
            // Build "<n>_<base>" without passing the name through a formatted 'any' arg,
            // then combine (Path.combine wants a plain string, so convert the String).
            var candidate = Format.toString("%_", n)
            candidate += base
            dst       = Path.combine(folder, candidate.toString())
            n         += 1
        }

        return dst
    }

    // Copy+delete because the filesystem module has no atomic move; on any failure we
    // leave the source untouched and remove the partial copy, so a capture is never lost.
    func moveFile(dstFolder: String, srcFile: String)->String
    {
        let dst = uniqueName(dstFolder, srcFile)

        catch File.duplicate(dst, srcFile) else do
            return ""

        catch File.delete(srcFile) else
        {
            discard catch File.delete(dst)
            return ""
        }

        return dst
    }

    func emptyTrash()
    {
        let files = catch enumerateTrash() as err
        if err != null do
            return
        for fi in files do
            discard catch File.delete(fi.fullname)
    }

    // Bring a trashed capture back into the library folder. Returns the restored path
    // (empty on failure) so the caller can register it again.
    func restoreFile(trashFile: String)->String
    {
        return moveFile(getFolder(), trashFile)
    }

    func newFileName()->String
    {
        let t        = Time.DateTime.now()
        let fileName = Format.toString("%_%_%_%_%_%_%.scapture", t.month, t.day, t.year, t.hour, t.minute, t.second, Guid64.random().toString())
        return Path.combine(getFolder(), fileName.toString())
    }

    mtd fill()
    {
        .files  = catch Directory.enumerateFiles(getFolder(), ".scapture")
        .loaded = true
    }

    // Soft-delete: move the capture to the recycle bin rather than erasing it. The
    // observers (recent strip, library grid) still see it leave the library through
    // onDeleteFile; it can be brought back from the trash view.
    mtd removeFile(name: String)
    {
        for fi, [idx] in .files
        {
            if fi.fullname == name
            {
                let trashed = moveFile(getTrashFolder(), name)
                if !trashed.isEmpty()
                {
                    .files.removeAtOrdered(idx)
                    .onDeleteFile.call(name)
                }

                break
            }
        }
    }

    mtd addFile(name: String)
    {
        let file = catch File.info(name) as err
        if err != null do
            return
        .files.add(file)
    }
}
