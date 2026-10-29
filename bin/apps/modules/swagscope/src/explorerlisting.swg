#global internal

using Core, Pixel, Gui

// One immediate child of a filesystem or archive location.
struct ExplorerEntry
{
    name:          String
    path:          String
    size:          u64
    creationStamp: u64
    modifiedStamp: u64
    modified:      String
    directory:     bool
    archiveIndex:  u64 = Swag.U64.Max
    texture:       Texture
    duration:      u64     // Seconds of a time-based medium, from its thumbnail; zero for anything else.
    children:      u64 = Swag.U64.Max     // Items a folder holds, when they were counted.

    // What a cell of the mixed board shows of a file it has no picture of, and the facts it
    // writes under it, read beside the listing: a picture's size, a document's pages, the lines
    // of code, the sections of Markdown, a font's family and style, and the first lines of a
    // text.
    width:         u32
    height:        u32
    pages:         u64
    lines:         u64
    sections:      u64
    members:       u64
    face:          String
    excerpt:       String
    movie:         MovieSummary
    music:         MusicSummary
    attempted:     bool
}

// The extensions whose content a cell of the mixed board draws, compared without case.
private const ProbeCodeExtensions     = [".swg", ".swgs", ".c", ".cpp", ".h", ".hpp", ".cs", ".js", ".ts", ".py", ".rs", ".go", ".java", ".json", ".xml", ".css", ".sh", ".lua", ".toml", ".yaml", ".yml", ".txt"]
private const ProbeImageExtensions    = [".png", ".jpg", ".jpeg", ".gif", ".bmp", ".tga", ".webp", ".qoi", ".ico"]
private const ProbeMarkdownExtensions = [".md", ".markdown"]
private const ProbeFontExtensions     = [".ttf", ".otf"]

// Reports whether the extension of `name` is one of `list`, without case.
private func probeKind(name: string, list: const [..] string)->bool
{
    let ext = Path.lowercaseExtension(name)
    for one in list where ext == one do
        return true
    return false
}

// Reads the head of `path`, at most `limit` bytes.
private func readHead(path: string, limit: u64)->Array'u8 fail
{
    var result: #returntype
    var stream = try File.openRead(path)
    result.resize(Math.min(try stream.size(), limit))
    result.resize(try stream.read(result.toSlice()))
    return result
}

// Reads what a cell shows of `entry` and the facts written under it. Returns whether the file
// was one it reads.
func probeEntry(entry: *ExplorerEntry)->bool
{
    let name = entry.name.toString()
    if probeKind(name, ProbeImageExtensions)
    {
        // The size of a picture is in its head; the pixels are not decoded.
        catch
        {
            let head  = try readHead(entry.path, 512 * 1024)
            let image = try Image.decode(name, head.toSlice(), DecodeOptions{decodePixels: false, decodeMetadata: false})
            entry.width  = cast(u32, image.width)
            entry.height = cast(u32, image.height)
        }

        return true
    }

    if Path.lowercaseExtension(name) == ".pdf"
    {
        if entry.size <= 64 * 1024 * 1024
        {
            catch
            {
                let reader = try Pdf.Reader.open(entry.path)
                entry.pages = reader.pageCount()
            }
        }

        return true
    }

    let markdown = probeKind(name, ProbeMarkdownExtensions)
    if markdown or probeKind(name, ProbeCodeExtensions)
    {
        catch
        {
            let head = try readHead(entry.path, 1024 * 1024)
            let text = cast(string, head.toSlice())
            var lines, sections: u64
            var start = 0'u64
            var kept  = 0'u64
            for at in text.count + 1
            {
                if at < text.count and text[at] != '\n' do
                    continue
                lines += 1
                var line = text[start until at]
                if line.count and line[line.count - 1] == '\r' do
                    line = line[0 until line.count - 1]
                if markdown and line.count and line[0] == '#' do
                    sections += 1
                if kept < 8 and Utf8.isValid(cast(const [..] u8, line))
                {
                    entry.excerpt += line[0 until Math.min(line.count, 80'u64)]
                    entry.excerpt += "\n"
                    kept += 1
                }

                start = at + 1
            }

            if text.count and text[text.count - 1] == '\n' do
                lines -= 1
            entry.lines    = lines
            entry.sections = sections
        }

        return true
    }

    // An archive holds files; its directory says how many without unpacking any.
    if Path.lowercaseExtension(name) == ".zip"
    {
        catch
        {
            let zip = try Viewers.Archive.Zip.load(entry.path)
            for &member in zip.entries where not member.isDirectory do
                entry.members += 1
        }

        return true
    }

    if probeKind(name, ProbeFontExtensions)
    {
        catch
        {
            let bytes = try File.readAllBytes(entry.path)
            let face  = try TrueType.Face.load(bytes.toSlice())
            entry.face = face.familyName
            if not face.styleName.isEmpty()
            {
                entry.face += " · "
                entry.face += face.styleName
            }
        }

        return true
    }

    return false
}

// A listing is acquired off the GUI thread; archive folders are projected without extraction.
struct ExplorerListing
{
    path:      String
    entries:   Array'ExplorerEntry
    archive:   Viewers.Archive.Zip
    isArchive: bool
}

impl ExplorerListing
{
    func load(path: string)->ExplorerListing fail
    {
        var result: #returntype
        result.path = try Path.absolute(path)
        Path.normalize(&result.path)
        if Directory.exists(path)
        {
            let files = try Directory.enumerate(path, {})
            for &file in files
            {
                with var entry: ExplorerEntry
                {
                    .name          = Path.fileName(file.fullName) orelse file.fullName.toString()
                    .path          = file.fullName
                    .size          = file.size
                    .creationStamp = Hash.hash64(file.creationTime)
                    .modifiedStamp = Hash.hash64(file.lastWriteTime)
                    .directory     = file.isDirectory()
                    .modified      = file.lastWriteTime.toString(.DateTimeIsoHm)
                }

                result.entries.add(#move entry)
            }

            // What a cell shows of a file is read for a bounded number of them.
            var probed = 0'u64
            for &entry in result.entries where not entry.directory and probed < 256
            {
                if Swag.isCancelled() do
                    break
                if probeEntry(entry) do
                    probed += 1
            }

            // A folder says how many items it holds; past a few dozen folders, counting them all
            // would keep a slow share waiting, and the count is left out.
            var counted = 0'u64
            for &entry in result.entries where entry.directory and counted < 64
            {
                counted += 1
                let inside = catch Directory.enumerate(entry.path, {})
                entry.children = inside.count
            }
        }
        else
        {
            result.archive   = try Viewers.Archive.Zip.load(path)
            result.isArchive = true
        }

        return result
    }

    mtd children(folder: string)->Array'ExplorerEntry
    {
        if not .isArchive do
            return .entries

        // A folder of the archive is dated by the latest of what it holds.
        var result:  #returntype
        var folders: HashTable'(String, u64)
        var latest:  Array'Time.DateTime
        for &entry, index in .archive.entries where Utf8.startsWith(entry.path, folder)
        {
            let relative = entry.path.toString()[folder.count to]
            if not relative.count do
                continue
            let slash = Utf8.indexOf(relative, "/")
            if slash != Swag.U64.Max or entry.isDirectory
            {
                let name  = String.from(slash != Swag.U64.Max ? relative[0 until slash] : relative)
                if name.isEmpty() do
                    continue
                let found = folders.tryFind(name)
                if found
                {
                    if entry.modified > latest[found.value] do
                        latest[found.value] = entry.modified
                    continue
                }

                folders.add(name, result.count)
                latest.add(entry.modified)
                var path = String.from(folder)
                path += name
                path += '/'u8
                result.add({name: name, path: #move path, directory: true})
            }
            else
            {
                result.add({name: relative, path: entry.path, size: entry.uncompressedSize,
                            directory: entry.isDirectory, archiveIndex: index})
                latest.add(entry.modified)
            }
        }

        for &entry, index in result where latest[index].year
        {
            entry.modified      = latest[index].toString(.DateTimeIsoHm)
            entry.modifiedStamp = Hash.hash64(latest[index])
        }

        return result
    }
}
