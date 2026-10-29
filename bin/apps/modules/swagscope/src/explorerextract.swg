#global internal

using Core, Gui

// Extracts members of an archive into a folder the reader chose, away from the GUI thread.
//
// A member lands at its path in the archive, less the folder it was extracted from. A path that
// would leave the chosen folder, or name what the system cannot, is left out; a file already
// there is kept rather than overwritten.
struct ArchiveExtraction
{
    using operation: Viewer.BackgroundOperation
    archiveFile:     String
    members:         Array'Viewers.Archive.ZipEntry
    strip:           String     // The folder of the archive the members are extracted from, left out of their paths.
    target:          String
    written:         u64
    kept:            u64        // Files already in the target folder, left as they were.
    error:           String
}

impl ArchiveExtraction
{
    // Returns where `member` lands under `target` once `strip` is left out of it, or an empty
    // path when it could leave `target` or names what the system cannot.
    func destination(target, strip, member: string)->String
    {
        if not Utf8.startsWith(member, strip) do
            return {}
        var result = String.from(target)
        var parts  = 0'u64
        for part in Tokenize.split(member[strip.count to], '/'rune)
        {
            if not part.count do
                continue
            if part == "." or part == ".." or not Path.isValidFileName(part) do
                return {}
            result = Path.combine(result, part)
            parts += 1
        }

        if not parts do
            return {}
        return result
    }

    // Extracts `members` of `archiveFile` under `target`; `owner` receives a [[Gui.TaskEvent]] when it ends.
    mtd start(archiveFile: string, members: #move Array'Viewers.Archive.ZipEntry, strip, target: string, owner: *Wnd)
    {
        Swag.assert(not .started)

        // The arguments may be views of what the previous extraction left here: own them first.
        var file   = String.from(archiveFile)
        var folder = String.from(strip)
        var into   = String.from(target)
        .archiveFile = #move file
        .members     = #move members
        .strip       = #move folder
        .target      = #move into
        .written     = 0
        .kept        = 0
        .error.clear()

        let operation = me
        .submit(func|operation|()
        {
            catch
            {
                try Directory.create(operation.target, recurse: true)
                for &member in operation.members
                {
                    let path = destination(operation.target, operation.strip, member.path)
                    if path.isEmpty() do
                        continue
                    if member.isDirectory
                    {
                        try Directory.create(path, recurse: true)
                        continue
                    }

                    if File.exists(path)
                    {
                        operation.kept += 1
                        continue
                    }

                    let parent = Path.directoryName(path)
                    if parent != null and parent.count do
                        try Directory.create(parent, recurse: true)
                    try Viewers.Archive.Zip.extractEntry(operation.archiveFile, member, path)
                    operation.written += 1
                }
            }
            {
                operation.error = Viewer.failureText(Swag.err)
            }
        },
                owner)
    }

    mtd opDrop() { .wait() }
}
