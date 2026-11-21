#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// Extraction owns a formatted worker failure after the task's caught error has been released.
#test
{
    var operation: Archive.ZipEntryExtract
    var entry:     Archive.ZipEntry
    entry.method = 99
    let destination = Testing.tempFilePath("scope-extract-failure-", ".bin")
    defer discard catch File.delete(destination)
    operation.start("unused.zip", &entry, destination)
    operation.task.wait()
    let failure = operation.finish()
    Swag.require(failure == failureShape(appStrings().ui_FailureFormat, Format.toString(Archive.texts().err_Method, 99)))
    Swag.require(not File.exists(destination))

    entry.method = 100
    operation.start("unused.zip", &entry, destination)
    operation.task.wait()
    let replacement = operation.finish()
    Swag.require(replacement == failureShape(appStrings().ui_FailureFormat, Format.toString(Archive.texts().err_Method, 100)))
    Swag.require(failure == failureShape(appStrings().ui_FailureFormat, Format.toString(Archive.texts().err_Method, 99)))
}

func buildZipFixture()->Array'u8
{
    var entries: [2] ZipFixtureEntry
    entries[0].name = "docs/readme.txt"
    entries[0].plain.add("Archive preview through the text viewer.\n")
    entries[0].packed = entries[0].plain

    entries[1].name = "data/sample.json"
    entries[1].plain.add("{\"answer\": 42}\n")
    entries[1].method = 8
    var deflater: Compress.Deflate
    deflater.init(.BestSpeed, flags: .Zero)
    expect deflater.compress(&entries[1].packed, entries[1].plain.toSlice())

    return buildZipEntries(entries[0 until entries.count])
}

func writeZipFixture()->String
{
    let path = Gui.Testing.tempFilePath("scope-archive-", ".zip")
    discard expect File.writeAllBytes(path, buildZipFixture().toSlice())
    return path
}

// Archive hierarchy sorting keeps folders ahead of files at the root and inside each folder,
// including explicit empty directories that have no child row to identify them.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 480)

    with let list = ListCtrl.createMultiColumns(&host.root)
    {
        .addColumn("Name", 200)
        .addColumn("Size", 80)
        .compareLines = &Archive.compareTreeLines
    }

    with let rootFile = list.createLine(null)
    {
        .setItem(0, "a.txt")
        .setItem(1, "1 B")
        .userData0 = cast(*void?, 1)
    }

    let rootFolder = list.createLine("z-folder")

    with let childFile = list.createLine(rootFolder)
    {
        .setItem(0, "a.txt")
        .setItem(1, "1 B")
        .userData0 = cast(*void?, 2)
    }

    let childFolder = list.createLine("z-empty", parentLine: rootFolder)

    list.sort(0, persistent: true)
    Swag.require(list.lineAt(0) == rootFolder)
    list.expand(rootFolder)
    Swag.require(list.lineAt(1) == childFolder)
    Swag.require(list.lineAt(2) == childFile)
    Swag.require(list.lineAt(3) == rootFile)

    list.sort(0, descending: true)
    Swag.require(list.lineAt(0) == rootFolder and list.lineAt(1) == childFolder)
}

// Legacy ZIP names use CP437 when the UTF-8 flag is absent.
#test
{
    const EncodedName: [8] u8 = ['c', 'a', 'f', 0x82, '.', 't', 'x', 't']
    Swag.require(Archive.Zip.text(EncodedName, false) == "café.txt")
}

// ZIP discovery reads the real hierarchy and both stored and Deflate entries round-trip through
// the same bounded extractor used for previews.
#test
{
    let archiveFile = writeZipFixture()
    defer discard catch File.delete(archiveFile)

    let archive = expect Archive.Zip.load(archiveFile)
    Swag.require(archive.entries.count == 2)
    Swag.require(archive.entries[0].path == "data/sample.json")
    Swag.require(archive.entries[1].path == "docs/readme.txt")

    for &entry in archive.entries
    {
        let extension = Path.extension(entry.path) orelse ".bin"
        let output    = Gui.Testing.tempFilePath("scope-archive-entry-", extension)
        defer discard catch File.delete(output)
        expect Archive.Zip.extractEntry(archiveFile, entry, output)
        let decoded = expect File.readAllBytes(output)
        if entry.path == "data/sample.json" do
            Swag.require(cast(string, decoded.toSlice()) == "{\"answer\": 42}\n")
        else do
            Swag.require(cast(string, decoded.toSlice()) == "Archive preview through the text viewer.\n")
    }
}

// The checked-in archive sample and its `.zip` alias contain only the two generated entries the
// archive preview tests exercise.
#test
{
    for fileName in ["viewer.archive.zip", "viewer.zip"]
    {
        let path    = scopeTestDataPath(fileName)
        let archive = expect Archive.Zip.load(path)
        Swag.require(archive.entries.count == 2)
        var foundReadme = false
        var foundJson   = false
        for &entry in archive.entries
        {
            let payload = expect Archive.Zip.loadEntry(path, entry)
            if entry.path == "docs/readme.txt"
            {
                foundReadme = true
                Swag.require(cast(string, payload.toSlice()) == "Archive preview through the text viewer.\n")
            }
            elif entry.path == "data/sample.json"
            {
                foundJson = true
                Swag.require(cast(string, payload.toSlice()) == "{\"answer\": 42}\n")
            }
            else
            {
                Swag.require(false, entry.path)
            }
        }

        Swag.require(foundReadme and foundJson, fileName)
    }
}

// ZIP64 size, offset, and end-directory fields resolve through their extra records and trailer.
#test
{
    let archiveFile = scopeTestDataPath("viewer.zip64.zip")
    let archive     = expect Archive.Zip.load(archiveFile)
    Swag.require(archive.entries.count == 1)
    let entry = &archive.entries[0]
    Swag.require(entry.path == "reports/zip64-summary.txt")
    Swag.require(entry.uncompressedSize == 61 and entry.compressedSize == 61)
    let output = Gui.Testing.tempFilePath("scope-zip64-entry-", ".txt")
    defer discard catch File.delete(output)
    expect Archive.Zip.extractEntry(archiveFile, entry, output)
    Swag.require((expect File.readAllText(output)) == "ZIP64 central directory and local extra fields are readable.\n")
}

// A forward-only writer uses bit 3 and a data descriptor after the compressed payload.
#test
{
    let archiveFile = scopeTestDataPath("viewer.zip-descriptor.zip")
    let archive     = expect Archive.Zip.load(archiveFile)
    Swag.require(archive.entries.count == 1)
    let entry = &archive.entries[0]
    Swag.require(entry.path == "logs/streamed-observations.txt" and entry.flags & 8 != 0)
    let output = Gui.Testing.tempFilePath("scope-zip-descriptor-", ".txt")
    defer discard catch File.delete(output)
    expect Archive.Zip.extractEntry(archiveFile, entry, output)
    Swag.require((expect File.readAllText(output)) == "A forward-only writer records this payload before its CRC and sizes.\n")
}

// Valid UTF-8 paths survive decoding, and duplicate member names remain individually browseable.
#test
{
    let archiveFile = scopeTestDataPath("viewer.zip-unicode-duplicates.zip")
    let archive     = expect Archive.Zip.load(archiveFile)
    Swag.require(archive.entries.count == 3)
    Swag.require(archive.tryFindEntry("field notes/café-日本語.txt") != null)

    var firstCopy  = false
    var secondCopy = false
    var duplicates = 0'u64
    for &entry in archive.entries where entry.path == "reports/repeated.txt"
    {
        duplicates += 1
        let output = Gui.Testing.tempFilePath("scope-zip-duplicate-", ".txt")
        defer discard catch File.delete(output)
        expect Archive.Zip.extractEntry(archiveFile, entry, output)
        let text = expect File.readAllText(output)
        if text == "first copy\n" do
            firstCopy = true
        elif text == "second copy\n" do
            secondCopy = true
    }

    Swag.require(duplicates == 2 and firstCopy and secondCopy)
}

// A generated PKZIP/ZipCrypto member is listed, then reported as unsupported before output.
#test
{
    let archiveFile = scopeTestDataPath("viewer.zipcrypto-encrypted.zip")
    let archive     = expect Archive.Zip.load(archiveFile)
    Swag.require(archive.entries.count == 1 and archive.entries[0].flags & 1 != 0)
    let output = Gui.Testing.tempFilePath("scope-zip-encrypted-", ".txt")
    defer discard catch File.delete(output)
    var error: Swag.Error
    catch Archive.Zip.extractEntry(archiveFile, &archive.entries[0], output) as error
    Swag.require(error.value() is Errors.UnsupportedFormatError)
    Swag.require(not File.exists(output))
}

// Corrupt central-directory bytes fail during discovery before an entry can be previewed.
#test
{
    var error: Swag.Error
    discard catch Archive.Zip.load(scopeTestDataPath("viewer.zip-damaged-directory.zip")) as error
    Swag.require(error.value() is Errors.InvalidFormatError)
}

// A declared output above PreviewLimit remains listable but never reaches extraction or disk.
#test
{
    let archiveFile = scopeTestDataPath("viewer.zip-preview-limit.zip")
    let archive     = expect Archive.Zip.load(archiveFile)
    let entry       = archive.tryFindEntry("data/preview-limit.txt")
    Swag.require(entry != null and entry.uncompressedSize == 256 * 1024 * 1024 + 1)
    let output = Gui.Testing.tempFilePath("scope-zip-preview-limit-", ".txt")
    defer discard catch File.delete(output)
    var error: Swag.Error
    catch Archive.Zip.extractEntry(archiveFile, entry, output) as error
    Swag.require(error.value() is Errors.UnsupportedFormatError)
    Swag.require(not File.exists(output))
}

// A realistic, generated project archive keeps its nested source and data files browseable.
#test
{
    let archiveFile = scopeTestDataPath("viewer.project.zip")
    let archive     = expect Archive.Zip.load(archiveFile)
    Swag.require(archive.entries.count == 7)

    var found = false
    if let entry = archive.tryFindEntry("data/observations.csv")
    {
        found = true
        Swag.require(entry.uncompressedSize > 150)
        let output = Gui.Testing.tempFilePath("scope-project-observations-", ".csv")
        defer discard catch File.delete(output)
        expect Archive.Zip.extractEntry(archiveFile, entry, output)
        let decoded = expect File.readAllBytes(output)
        Swag.require(Utf8.contains(cast(string, decoded.toSlice()), "north-marsh,2026-05-18T08:30:00Z"))
    }

    Swag.require(found)
}

// The JAR fallback fixture is a valid, deterministic Java package rather than a renamed text ZIP.
#test
{
    let archive = expect Archive.Zip.load(scopeTestDataPath("viewer.jar"))
    Swag.require(archive.entries.count == 4)
    Swag.require(archive.tryFindEntry("META-INF/MANIFEST.MF") != null)
    Swag.require(archive.tryFindEntry("FixtureApp.class") != null)
    Swag.require(archive.tryFindEntry("data/sites.csv") != null)
}

// A generated POSIX ustar package is browsable and its bounded payload opens through the shared extractor.
#test
{
    let archiveFile = scopeTestDataPath("viewer.field-kit.tar")
    let archive     = expect Archive.Zip.load(archiveFile)
    Swag.require(archive.entries.count == 3)
    Swag.require(archive.tryFindEntry("data/observations.csv") != null)
    let entry = archive.tryFindEntry("notes/README.txt")
    Swag.require(entry != null and entry.isTar and not entry.isDirectory)
    let output = Gui.Testing.tempFilePath("scope-tar-entry-", ".txt")
    defer discard catch File.delete(output)
    expect Archive.Zip.extractEntry(archiveFile, entry, output)
    Swag.require((expect File.readAllText(output)) == "Generated field kit archive.\n")
}

// TAR headers are checked before any member is offered to preview.
#test
{
    var bytes = expect File.readAllBytes(scopeTestDataPath("viewer.field-kit.tar"))
    bytes[0] ^= 1
    let archiveFile = Gui.Testing.tempFilePath("scope-tar-bad-header-", ".tar")
    defer discard catch File.delete(archiveFile)
    discard expect File.writeAllBytes(archiveFile, bytes.toSlice())
    var archiveErrorOutcome: Swag.Error
    discard catch Archive.Zip.load(archiveFile) as archiveErrorOutcome
    Swag.require(archiveErrorOutcome.value() is Errors.InvalidFormatError)
}

// POSIX PAX path records preserve long member names through listing and bounded extraction.
#test
{
    const Path = "field-reports/observations/2026/seasonal/north-marsh/watershed-measurements-early-summer-early-summer-early-summer-early-summer-early-summer-summary.txt"
    let archiveFile = scopeTestDataPath("viewer.pax-field-kit.tar")
    let archive     = expect Archive.Zip.load(archiveFile)
    Swag.require(archive.entries.count == 1, Format.toString("PAX entries: %", archive.entries.count))
    Swag.require(archive.entries[0].path == Path, Format.toString("PAX path: %", archive.entries[0].path))
    let output = Gui.Testing.tempFilePath("scope-pax-entry-", ".txt")
    defer discard catch File.delete(output)
    expect Archive.Zip.extractEntry(archiveFile, &archive.entries[0], output)
    Swag.require((expect File.readAllText(output)) == "PAX extended paths remain browseable.\n")
}

// A GZIP member opens by its stored filename, checks its trailer, and extracts through Archive's preview path.
#test
{
    let archiveFile = scopeTestDataPath("viewer.field-notes.txt.gz")
    let archive     = expect Archive.Zip.load(archiveFile)
    Swag.require(archive.entries.count == 1 and archive.entries[0].path == "field-notes.txt")
    Swag.require(archive.entries[0].isGzip and archive.entries[0].uncompressedSize > 0)
    let output = Gui.Testing.tempFilePath("scope-gzip-entry-", ".txt")
    defer discard catch File.delete(output)
    expect Archive.Zip.extractEntry(archiveFile, &archive.entries[0], output)
    Swag.require((expect File.readAllText(output)) == "Generated watershed field notes.\nRainfall: 12 mm\n")
}

// A TAR.GZ keeps each TAR payload offset relative to the bounded, CRC-checked GZIP output.
#test
{
    let archiveFile = scopeTestDataPath("viewer.field-kit.tar.gz")
    let archive     = expect Archive.Zip.load(archiveFile)
    Swag.require(archive.entries.count == 3 and archive.entries[0].isGzip and archive.entries[0].isTar)
    let entry = &archive.entries[1]
    Swag.require(entry.path == "notes/README.txt" and entry.isGzip and entry.isTar)
    let output = Gui.Testing.tempFilePath("scope-targz-entry-", ".txt")
    defer discard catch File.delete(output)
    expect Archive.Zip.extractEntry(archiveFile, entry, output)
    Swag.require((expect File.readAllText(output)) == "Generated field kit archive.\n")
}

// A GZIP CRC mismatch rejects the compressed document before offering a browsable member.
#test
{
    var bytes = expect File.readAllBytes(scopeTestDataPath("viewer.field-notes.txt.gz"))
    bytes[bytes.count - 8] ^= 1
    let path = Gui.Testing.tempFilePath("scope-gzip-crc-", ".gz")
    defer discard catch File.delete(path)
    discard expect File.writeAllBytes(path, bytes.toSlice())
    var error: Swag.Error
    discard catch Archive.Zip.load(path) as error
    Swag.require(error.value() is Errors.InvalidFormatError)
}

// A GZIP ISIZE mismatch also rejects the stream before exposing its payload.
#test
{
    var bytes = expect File.readAllBytes(scopeTestDataPath("viewer.field-notes.txt.gz"))
    bytes[bytes.count - 4] ^= 1
    let path = Gui.Testing.tempFilePath("scope-gzip-size-", ".gz")
    defer discard catch File.delete(path)
    discard expect File.writeAllBytes(path, bytes.toSlice())
    var error: Swag.Error
    discard catch Archive.Zip.load(path) as error
    Swag.require(error.value() is Errors.InvalidFormatError)
}

// A part is found by its exact name among names that differ only by case, and of a name stored
// twice, the entry found is the first in the archive's order.
#test
{
    var zip: Archive.Zip
    Swag.require(zip.tryFindEntry("missing") == null)
    for path in ["b/Chapter.xhtml", "a/one.xml", "B/chapter.xhtml", "b/chapter.xhtml", "b/chapter.xhtml", "c.txt"]
    {
        var entry: Archive.ZipEntry
        entry.path = path
        zip.entries.add(#move entry)
    }

    zip.entries.sort(func(a, b) => Utf8.compare(a.path.toSlice(), b.path.toSlice(), .Latin1NoCase))
    for path in ["a/one.xml", "b/Chapter.xhtml", "B/chapter.xhtml", "c.txt"]
    {
        let entry = zip.tryFindEntry(path)
        Swag.require(entry != null and entry.path == path, path)
    }

    var first: const *Archive.ZipEntry? = null
    for &entry in zip.entries where first == null and entry.path == "b/chapter.xhtml" do
        first = entry
    Swag.require(first != null and zip.tryFindEntry("b/chapter.xhtml") == first)

    for path in ["b/CHAPTER.xhtml", "b/chapter", "0", "d"] do
        Swag.require(zip.tryFindEntry(path) == null, path)
}

// A split central directory is rejected before any entry is offered for preview.
#test
{
    var bytes = buildZipFixture()
    bytes[bytes.count - 14] = 1
    let archiveFile = Gui.Testing.tempFilePath("scope-archive-split-", ".zip")
    defer discard catch File.delete(archiveFile)
    discard expect File.writeAllBytes(archiveFile, bytes.toSlice())

    var archiveErrorOutcome: Swag.Error
    discard catch Archive.Zip.load(archiveFile) as archiveErrorOutcome
    let archiveError = archiveErrorOutcome.value()
    Swag.require(archiveError is Errors.UnsupportedFormatError)
}

// A changed payload cannot cross the archive boundary under a stale central-directory checksum.
#test
{
    var bytes = buildZipFixture()
    bytes[30 + "docs/readme.txt".count] ^= 1
    let archiveFile = Gui.Testing.tempFilePath("scope-archive-crc-", ".zip")
    defer discard catch File.delete(archiveFile)
    discard expect File.writeAllBytes(archiveFile, bytes.toSlice())

    let archive = expect Archive.Zip.load(archiveFile)
    let output  = Gui.Testing.tempFilePath("scope-archive-crc-entry-", ".txt")
    defer discard catch File.delete(output)
    var extractErrorOutcome: Swag.Error
    catch Archive.Zip.extractEntry(archiveFile, &archive.entries[1], output) as extractErrorOutcome
    let extractError = extractErrorOutcome.value()
    Swag.require(extractError is Errors.InvalidFormatError)
}

// Extraction refuses an occupied destination and leaves its bytes untouched.
#test
{
    let archiveFile = writeZipFixture()
    defer discard catch File.delete(archiveFile)
    let archive = expect Archive.Zip.load(archiveFile)
    let output  = Gui.Testing.tempFilePath("scope-archive-occupied-", ".txt")
    defer discard catch File.delete(output)
    discard expect File.writeAllText(output, "keep existing file")

    var extractErrorOutcome: Swag.Error
    catch Archive.Zip.extractEntry(archiveFile, &archive.entries[1], output) as extractErrorOutcome
    Swag.require(extractErrorOutcome.value() is Swag.SystemError)
    Swag.require((expect File.readAllText(output)) == "keep existing file")
}
