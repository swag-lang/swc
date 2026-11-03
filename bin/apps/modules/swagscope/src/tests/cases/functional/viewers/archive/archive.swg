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

struct ZipFixtureEntry
{
    name:   String
    plain:  Array'u8
    packed: Array'u8
    method: u16
    crc32:  u32
    local:  u64
}

func zipFixtureU16(bytes: *Array'u8, value: u16)
{
    bytes.add(cast #bit (u8, value))
    bytes.add(cast #bit (u8, (value >> 8)))
}

func zipFixtureU32(bytes: *Array'u8, value: u32)
{
    zipFixtureU16(bytes, cast #bit (u16, value))
    zipFixtureU16(bytes, cast #bit (u16, (value >> 16)))
}

func addZipFixtureEntry(bytes: *Array'u8, entry: *ZipFixtureEntry)
{
    entry.crc32 = Hash.Crc32.compute(entry.plain.toSlice())
    entry.local = bytes.count
    zipFixtureU32(bytes, 0x04034B50)
    zipFixtureU16(bytes, 20)
    zipFixtureU16(bytes, 1 << 11)
    zipFixtureU16(bytes, entry.method)
    zipFixtureU16(bytes, 0)
    zipFixtureU16(bytes, 0)
    zipFixtureU32(bytes, entry.crc32)
    zipFixtureU32(bytes, cast(u32, entry.packed.count))
    zipFixtureU32(bytes, cast(u32, entry.plain.count))
    zipFixtureU16(bytes, cast(u16, entry.name.length))
    zipFixtureU16(bytes, 0)
    bytes.add(entry.name.toSlice())
    bytes.add(entry.packed.toSlice())
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

    var result: #returntype
    for &entry in entries do
        addZipFixtureEntry(&result, entry)

    let directoryAt = result.count
    for entry in entries
    {
        zipFixtureU32(&result, 0x02014B50)
        zipFixtureU16(&result, 20)
        zipFixtureU16(&result, 20)
        zipFixtureU16(&result, 1 << 11)
        zipFixtureU16(&result, entry.method)
        zipFixtureU16(&result, 0)
        zipFixtureU16(&result, 0)
        zipFixtureU32(&result, entry.crc32)
        zipFixtureU32(&result, cast(u32, entry.packed.count))
        zipFixtureU32(&result, cast(u32, entry.plain.count))
        zipFixtureU16(&result, cast(u16, entry.name.length))
        zipFixtureU16(&result, 0)
        zipFixtureU16(&result, 0)
        zipFixtureU16(&result, 0)
        zipFixtureU16(&result, 0)
        zipFixtureU32(&result, 0)
        zipFixtureU32(&result, cast(u32, entry.local))
        result.add(entry.name.toSlice())
    }

    let directorySize = result.count - directoryAt
    zipFixtureU32(&result, 0x06054B50)
    zipFixtureU16(&result, 0)
    zipFixtureU16(&result, 0)
    zipFixtureU16(&result, entries.count)
    zipFixtureU16(&result, entries.count)
    zipFixtureU32(&result, cast(u32, directorySize))
    zipFixtureU32(&result, cast(u32, directoryAt))
    zipFixtureU16(&result, 0)
    return result
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
