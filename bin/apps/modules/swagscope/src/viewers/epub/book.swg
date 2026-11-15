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

// An EPUB package extracted to a bounded disposable folder for the HTML reader.
struct Book
{
    chapters:   Array'Chapter
    root:       String
    navigation: Navigation
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
        let index        = try readPackage(fileName, packageEntry, &archive)
        result.chapters = index.chapters
        let navigationPath = index.navPath.isEmpty() ? index.ncxPath.toString() : index.navPath.toString()
        if navigationPath.count
        {
            var navigationError: Swag.Error
            result.navigation = catch readNavigation(fileName, &archive, navigationPath, index.navPath.isEmpty()) as navigationError
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
    chapters: Array'Chapter
    navPath:  String
    ncxPath:  String
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
    var token: Package.Token
    var items: Array'ManifestItem
    var order: Array'String
    var tocId: String
    let base  = Package.parentPath(entry.path)

    while scan.next(&token)
    {
        if token.kind != .Start do
            continue
        if token.isElement("item")
        {
            let id        = try requiredAttribute(&token, "id")
            let href      = try requiredAttribute(&token, "href")
            let mediaType = try requiredAttribute(&token, "media-type")
            let path      = try requiredPath(base, href)
            items.add(ManifestItem{id, path, mediaType, token.attribute("properties") orelse ""})
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
    for item in items
    {
        for property in Tokenize.split(item.properties, ' 'u8) where property == "nav" do
            result.navPath = item.path
        if (not tocId.isEmpty() and item.id == tocId) or
           (tocId.isEmpty() and item.mediaType == "application/x-dtbncx+xml") do
            result.ncxPath = item.path
    }

    for id in order
    {
        var found = false
        for &item in items where item.id == id
        {
            found = true
            if item.mediaType != "application/xhtml+xml" and item.mediaType != "text/html" do
                fail Errors.UnsupportedFormatError{texts().err_UnsupportedChapter}
            if archive.tryFindEntry(item.path) == null do
                fail Errors.InvalidFormatError{texts().err_Invalid}
            result.chapters.add(Chapter{item.path, item.id})
            break
        }

        if not found do
            fail Errors.InvalidFormatError{texts().err_Invalid}
    }

    if result.chapters.isEmpty() do
        fail Errors.InvalidFormatError{texts().err_NoChapters}
    return result
}
