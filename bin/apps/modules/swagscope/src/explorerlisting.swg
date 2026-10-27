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
    movie:         MovieSummary
    music:         MusicSummary
    attempted:     bool
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

        var result:  #returntype
        var folders: HashSet'String
        for &entry, index in .archive.entries where Utf8.startsWith(entry.path, folder)
        {
            let relative = entry.path.toString()[folder.count to]
            if not relative.count do
                continue
            let slash = Utf8.indexOf(relative, "/")
            if slash != Swag.U64.Max
            {
                let name = String.from(relative[0 until slash])
                if name.isEmpty() or folders.contains(name) do
                    continue
                folders.add(name)
                var path = String.from(folder)
                path += name
                path += '/'u8
                result.add({name: name, path: #move path, directory: true})
            }
            elif entry.isDirectory
            {
                let name = String.from(relative)
                if folders.contains(name) do
                    continue
                folders.add(name)
                var path = String.from(entry.path)
                path += '/'u8
                result.add({name: name, path: #move path, directory: true})
            }
            else
            {
                result.add({name: relative, path: entry.path, size: entry.uncompressedSize,
                            directory: entry.isDirectory, archiveIndex: index})
            }
        }

        return result
    }
}
