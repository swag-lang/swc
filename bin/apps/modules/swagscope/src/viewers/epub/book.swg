#global internal
#global namespace Viewers.Epub

using Core

// One reading document named by the EPUB spine.
struct Chapter
{
    path: String
    id:   String
}

private struct ManifestItem
{
    id:         String
    path:       String
    mediaType:  String
    properties: String
}

private func requiredEntry(archive: const *Archive.Zip, path: string)->const *Archive.ZipEntry fail
{
    let entry = archive.tryFindEntry(path)
    if not entry do
        fail Errors.InvalidFormatError{texts().err_Invalid}
    return entry
}

private func requiredPath(base: string, path: string)->String fail
{
    let result = Package.resolvePath(base, path)
    if result.isEmpty() do
        fail Errors.InvalidFormatError{texts().err_Invalid}
    return result
}

private func requiredAttribute(token: const *Package.Token, name: string)->string fail
{
    let value = token.attribute(name)
    if not value do
        fail Errors.InvalidFormatError{texts().err_Invalid}
    return value
}

// What the package says of the book in its Dublin Core metadata, as written.
struct BookMetadata
{
    title:     String     // The first title.
    creators:  String     // Every creator, in order, joined by a middle dot.
    language:  String     // The first language code.
    publisher: String
    date:      String     // The first date, as the package writes it.
}

// An EPUB package extracted to a bounded disposable folder for the HTML reader.
struct Book
{
    chapters:   Array'Chapter
    root:       String
    navigation: Navigation
    metadata:   BookMetadata
}

impl Book
{
    mtd opDrop()
    {
        if not .root.isEmpty() do
            discard catch Directory.delete(.root, recurse: true)
    }

    // Reads the package's declared document order, then extracts its safe local resources.
    func load(fileName: string)->Book fail
    {
        var result: #returntype
        let archive = try Archive.Zip.load(fileName)
        if archive.uncompressedSize > 512 * 1024 * 1024'u64 do
            fail Errors.UnsupportedFormatError{texts().err_TooLarge}

        let mimetype = try requiredEntry(&archive, "mimetype")
        let kind     = try Archive.Zip.loadEntry(fileName, mimetype)
        if cast(string, kind.toSlice()) != "application/epub+zip" do
            fail Errors.InvalidFormatError{texts().err_Invalid}

        let container    = try requiredEntry(&archive, "META-INF/container.xml")
        let packagePath  = try rootFile(fileName, container)
        let packageEntry = try requiredEntry(&archive, packagePath)
        var index        = try readPackage(fileName, packageEntry, &archive)
        result.chapters = #move index.chapters
        result.metadata = #move index.metadata
        let navigationPath = index.navPath.isEmpty() ? index.ncxPath.toString() : index.navPath.toString()
        if navigationPath.count
        {
            var navigationError: Swag.Error
            result.navigation = catch readNavigation(fileName, &archive, navigationPath, index.navPath.isEmpty()) as navigationError orelse {}
            if navigationError.value() do
                result.navigation.failure = Viewer.failureText(navigationError.value())
            result.navigation.bind(result.chapters.toSlice())
        }

        result.root = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("swagscope-epub-%", Guid64.random()))
        try Directory.create(result.root)
        for &entry in archive.entries where not entry.isDirectory
        {
            let safe = try requiredPath("", entry.path)
            if safe != entry.path do
                fail Errors.InvalidFormatError{texts().err_Invalid}
            let output = Path.combine(result.root, safe)
            let parent = unwrap Path.directoryName(output)
            try Directory.create(parent, recurse: true)
            try Archive.Zip.extractEntry(fileName, entry, output)
        }

        return result
    }
}

// Returns the encoded bytes and the package path of the picture an EPUB names as its cover, read
// from the archive without extracting the rest of the book; both are empty when the package names
// none.
func loadCover(fileName: string)->{ bytes: Array'u8, path: String } fail
{
    let archive      = try Archive.Zip.load(fileName)
    let container    = try requiredEntry(&archive, "META-INF/container.xml")
    let packagePath  = try rootFile(fileName, container)
    let packageEntry = try requiredEntry(&archive, packagePath)
    let index        = try readPackage(fileName, packageEntry, &archive)
    var result: #returntype
    if index.coverPath.isEmpty() do
        return result
    let entry = try requiredEntry(&archive, index.coverPath)
    if entry.uncompressedSize > 32 * 1024 * 1024'u64 do
        fail Errors.UnsupportedFormatError{texts().err_TooLarge}

    result.bytes = try Archive.Zip.loadEntry(fileName, entry)
    result.path  = index.coverPath
    return result
}

// Reads the unique root package path from the EPUB container.
private func rootFile(fileName: string, entry: const *Archive.ZipEntry)->String fail
{
    if entry.uncompressedSize > 1024 * 1024 do
        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
    let bytes = try Archive.Zip.loadEntry(fileName, entry)
    var scan  = Package.Scanner.create(cast(string, bytes.toSlice()))
    var token:  Package.Token
    var result: String
    while scan.next(&token)
    {
        if token.kind != .Start or not token.isElement("rootfile") do
            continue
        let path = token.attribute("full-path")
        if not path do
            continue
        let safe = try requiredPath("", path)
        if result.isEmpty() do
            result = safe
        else do
            fail Errors.InvalidFormatError{texts().err_Invalid}
    }

    if scan.damaged or result.isEmpty() do
        fail Errors.InvalidFormatError{texts().err_Invalid}
    return result
}

private struct PackageIndex
{
    chapters:  Array'Chapter
    navPath:   String
    ncxPath:   String
    coverPath: String     // Picture the package names as its cover, or empty.
    metadata:  BookMetadata
}

private func readNavigation(fileName: string, archive: const *Archive.Zip, path: string, ncx: bool)->Navigation fail
{
    let entry = try requiredEntry(archive, path)
    if entry.uncompressedSize > 4 * 1024 * 1024 do
        fail Errors.UnsupportedFormatError{texts().err_ContentsTooLarge}
    let bytes = try Archive.Zip.loadEntry(fileName, entry)
    return try Navigation.parse(cast(string, bytes.toSlice()), path, ncx)
}

// Resolves manifest entries and follows the spine instead of ZIP or alphabetical order.
private func readPackage(fileName: string, entry: const *Archive.ZipEntry, archive: const *Archive.Zip)->PackageIndex fail
{
    if entry.uncompressedSize > 16 * 1024 * 1024 do
        fail Errors.UnsupportedFormatError{texts().err_TooLarge}
    let bytes = try Archive.Zip.loadEntry(fileName, entry)
    var scan  = Package.Scanner.create(cast(string, bytes.toSlice()))
    var token:   Package.Token
    var items:   Array'ManifestItem
    var order:   Array'String
    var tocId:   String
    var coverId: String
    let base  = Package.parentPath(entry.path)

    // The Dublin Core element whose text is being read, and that text.
    var metadata: BookMetadata
    var field:    String
    var text:     String

    while scan.next(&token)
    {
        if token.kind == .Text
        {
            if not field.isEmpty() do
                text += token.text
            continue
        }

        if token.kind == .End
        {
            if not field.isEmpty() and token.isElement(field.toString())
            {
                let value = Latin1.trim(text.toString())
                switch field.toString()
                {
                case "title":
                    if metadata.title.isEmpty() do
                        metadata.title = value

                case "language":
                    if metadata.language.isEmpty() do
                        metadata.language = value

                case "publisher":
                    if metadata.publisher.isEmpty() do
                        metadata.publisher = value

                case "date":
                    if metadata.date.isEmpty() do
                        metadata.date = value

                case "creator":
                    if value.count
                    {
                        if not metadata.creators.isEmpty() do
                            metadata.creators += " · "
                        metadata.creators += value
                    }
                }

                field.clear()
                text.clear()
            }

            continue
        }

        if token.kind != .Start do
            continue
        if not token.empty and Utf8.startsWith(token.name.toString(), "dc:")
        {
            for name in ["title", "creator", "language", "publisher", "date"] where token.isElement(name)
            {
                field = name
                text.clear()
            }
        }

        if token.isElement("item")
        {
            let id        = try requiredAttribute(&token, "id")
            let href      = try requiredAttribute(&token, "href")
            let mediaType = try requiredAttribute(&token, "media-type")
            let path      = try requiredPath(base, href)
            items.add(ManifestItem{id, path, mediaType, token.attribute("properties") orelse ""})
        }
        elif token.isElement("meta") and (token.attribute("name") orelse "") == "cover"
        {
            // EPUB 2 names its cover picture by manifest identifier.
            coverId = token.attribute("content") orelse ""
        }
        elif token.isElement("spine")
        {
            tocId = token.attribute("toc") orelse ""
        }
        elif token.isElement("itemref")
        {
            let id = try requiredAttribute(&token, "idref")
            order.add(id)
        }
    }

    if scan.damaged do
        fail Errors.InvalidFormatError{texts().err_Invalid}

    var result: #returntype
    result.metadata = #move metadata
    for item in items
    {
        for property in Tokenize.split(item.properties, ' 'u8)
        {
            if property == "nav" do
                result.navPath = item.path
            elif property == "cover-image" do
                result.coverPath = item.path
        }

        if result.coverPath.isEmpty() and
           not coverId.isEmpty() and
           item.id == coverId and
           Utf8.startsWith(item.mediaType, "image/") do
            result.coverPath = item.path
        if (not tocId.isEmpty() and item.id == tocId) or
           (tocId.isEmpty() and item.mediaType == "application/x-dtbncx+xml") do
            result.ncxPath = item.path
    }

    // The spine names manifest items by identifier; index them once rather than scanning the
    // manifest for every reference. The first item declaring an identifier is the one named.
    var itemById: HashTable'(string, u64)
    for item, index in items do
        itemById.add(item.id.toString(), index, updateValue: false)

    for id in order
    {
        let found = itemById.tryFind(id.toString())
        if not found do
            fail Errors.InvalidFormatError{texts().err_Invalid}

        let item = &items[found.value]
        if item.mediaType != "application/xhtml+xml" and item.mediaType != "text/html" do
            fail Errors.UnsupportedFormatError{texts().err_UnsupportedChapter}
        if archive.tryFindEntry(item.path) == null do
            fail Errors.InvalidFormatError{texts().err_Invalid}
        result.chapters.add(Chapter{item.path, item.id})
    }

    if result.chapters.isEmpty() do
        fail Errors.InvalidFormatError{texts().err_NoChapters}
    return result
}
