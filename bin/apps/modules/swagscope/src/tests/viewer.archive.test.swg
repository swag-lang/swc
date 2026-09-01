#global if #command == Swag.CompilerCommand.Test
#global internal

using Core, Pixel, Gui

private func archiveViewerFixturePath()->String
{
    return Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/viewer.archive.zip")
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

private func zipFixtureU16(bytes: *Array'u8, value: u16)
{
    bytes.add(cast #bit (u8) value)
    bytes.add(cast #bit (u8) (value >> 8))
}

private func zipFixtureU32(bytes: *Array'u8, value: u32)
{
    zipFixtureU16(bytes, cast #bit (u16) value)
    zipFixtureU16(bytes, cast #bit (u16) (value >> 16))
}

private func addZipFixtureEntry(bytes: *Array'u8, entry: *ZipFixtureEntry)
{
    entry.local = bytes.count
    zipFixtureU32(bytes, 0x04034B50)
    zipFixtureU16(bytes, 20)
    zipFixtureU16(bytes, 1 << 11)
    zipFixtureU16(bytes, entry.method)
    zipFixtureU16(bytes, 0)
    zipFixtureU16(bytes, 0)
    zipFixtureU32(bytes, entry.crc32)
    zipFixtureU32(bytes, cast(u32) entry.packed.count)
    zipFixtureU32(bytes, cast(u32) entry.plain.count)
    zipFixtureU16(bytes, cast(u16) entry.name.length)
    zipFixtureU16(bytes, 0)
    bytes.add(entry.name.toSlice())
    bytes.add(entry.packed.toSlice())
}

private func buildZipFixture()->Array'u8
{
    var entries: [2] ZipFixtureEntry
    entries[0].name = "docs/readme.txt"
    let readme = String.from("Archive preview through the text viewer.\n")
    entries[0].plain.add(readme.toSlice())
    entries[0].packed = entries[0].plain
    entries[0].crc32  = Hash.Crc32.compute(entries[0].plain.toSlice())

    entries[1].name = "data/sample.json"
    let sample = String.from("{\"answer\": 42}\n")
    entries[1].plain.add(sample.toSlice())
    entries[1].method = 8
    entries[1].crc32  = Hash.Crc32.compute(entries[1].plain.toSlice())
    var deflater: Compress.Deflate
    deflater.init(.BestSpeed, flags: .Zero)
    expect deflater.compress(&entries[1].packed, entries[1].plain.toSlice())

    var result: retval
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
        zipFixtureU32(&result, cast(u32) entry.packed.count)
        zipFixtureU32(&result, cast(u32) entry.plain.count)
        zipFixtureU16(&result, cast(u16) entry.name.length)
        zipFixtureU16(&result, 0)
        zipFixtureU16(&result, 0)
        zipFixtureU16(&result, 0)
        zipFixtureU16(&result, 0)
        zipFixtureU32(&result, 0)
        zipFixtureU32(&result, cast(u32) entry.local)
        result.add(entry.name.toSlice())
    }

    let directorySize = result.count - directoryAt
    zipFixtureU32(&result, 0x06054B50)
    zipFixtureU16(&result, 0)
    zipFixtureU16(&result, 0)
    zipFixtureU16(&result, entries.count)
    zipFixtureU16(&result, entries.count)
    zipFixtureU32(&result, cast(u32) directorySize)
    zipFixtureU32(&result, cast(u32) directoryAt)
    zipFixtureU16(&result, 0)
    return result
}

private func writeZipFixture()->String
{
    let path = Gui.Testing.tempFilePath("scope-archive-", ".zip")
    discard expect File.writeAllBytes(path, buildZipFixture().toSlice())
    return path
}

// Legacy ZIP names use CP437 when the UTF-8 flag is absent.
#test
{
    const EncodedName: [8] u8 = ['c', 'a', 'f', 0x82, '.', 't', 'x', 't']
    Swag.assert(zipText(EncodedName, false) == "café.txt")
}

// ZIP discovery reads the real hierarchy and both stored and Deflate entries round-trip through
// the same bounded extractor used for previews.
#test
{
    let archiveFile = writeZipFixture()
    defer discard catch File.delete(archiveFile)

    let archive = expect loadZipArchive(archiveFile)
    Swag.assert(archive.entries.count == 2)
    Swag.assert(archive.entries[0].path == "data/sample.json")
    Swag.assert(archive.entries[1].path == "docs/readme.txt")

    for &entry in archive.entries
    {
        let extension = Path.extension(entry.path.toString()) orelse ".bin"
        let output    = Gui.Testing.tempFilePath("scope-archive-entry-", extension)
        defer discard catch File.delete(output)
        expect extractZipEntry(archiveFile, entry, output)
        let decoded = expect File.readAllBytes(output)
        if entry.path == "data/sample.json" do
            Swag.assert(cast(string) decoded.toSlice() == "{\"answer\": 42}\n")
        else do
            Swag.assert(cast(string) decoded.toSlice() == "Archive preview through the text viewer.\n")
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

    discard catch loadZipArchive(archiveFile) as archiveError
    Swag.assert(archiveError is Errors.UnsupportedFormatError)
}

// A changed payload cannot cross the archive boundary under a stale central-directory checksum.
#test
{
    var bytes = buildZipFixture()
    bytes[30 + "docs/readme.txt".count] ^= 1
    let archiveFile = Gui.Testing.tempFilePath("scope-archive-crc-", ".zip")
    defer discard catch File.delete(archiveFile)
    discard expect File.writeAllBytes(archiveFile, bytes.toSlice())

    let archive = expect loadZipArchive(archiveFile)
    let output  = Gui.Testing.tempFilePath("scope-archive-crc-entry-", ".txt")
    defer discard catch File.delete(output)
    catch extractZipEntry(archiveFile, &archive.entries[1], output) as extractError
    Swag.assert(extractError is Errors.InvalidFormatError)
}

// The integrated viewer builds synthetic folders and hosts the selected entry with the ordinary
// file viewer registry instead of maintaining an archive-only rendering path.
#[Swag.TestTag("golden")]
#test
{
    let archiveFile = archiveViewerFixturePath()

    var host: Testing.HeadlessHost
    host.setup(1180, 720)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.resize(1180, 720)
    window.openFile(archiveFile)
    completeViewerWindowClassification(&host, window)

    let viewer = cast(*ArchiveViewer) window.currentView!
    while !viewer.load.isDone() do
        Threading.Thread.sleep(1'ms)
    host.fireTimer(viewer.loadTimer)
    Swag.assert(viewer.list.lineCount() == 4)
    Swag.assert(viewer.entryLines.count == 2)

    let line         = viewer.entryLines[1]!
    var visibleIndex = Swag.U32.Max
    for index in viewer.list.lineCount() where viewer.list.lineAt(index) == line do
        visibleIndex = index
    Swag.assert(visibleIndex != Swag.U32.Max)
    viewer.list.selectLine(visibleIndex)
    viewer.requestPreview(1)
    Swag.assert(viewer.pendingPreview == Swag.U64.Max)

    while viewer.extract.started and !viewer.extract.isDone() do
        Threading.Thread.sleep(1'ms)
    host.fireTimer(viewer.previewTimer)
    Swag.assert(!viewer.previewFile.isEmpty())

    let embedded = cast(*EmbeddedViewer) viewer.previewPane.children[0]
    Swag.assert(embedded.choices[0].key == "text")
    Swag.assert(embedded.currentView != null)

    for 4_096 where viewer.embedded.isLoading()
    {
        Threading.Thread.sleep(1'ms)
        host.fireTimers()
    }

    Swag.assert(!viewer.embedded.isLoading())
    host.settleAnimations(window, 4)
    var image = host.render(window)
    Pixel.Testing.assertImageGolden(&image, "viewer.archive.document")

    var matches: Array'Viewer.SearchMatch
    let session = &window.instances[window.activeChoiceIndex]
    session.collectMatches!(viewer, "readme", {}, &matches)
    Swag.assert(matches.count == 1 and matches[0].major == 1)
    Swag.assert(session.revealMatch!(viewer, matches[0], "readme"))
    var bounds: Math.Rectangle
    Swag.assert(session.searchBounds!(viewer, matches[0], &bounds) and !bounds.isEmpty())
    session.clearSearch!(viewer)

    defer discard catch host.app.setLanguage(ReferenceLanguage)
    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.assert(viewer.list.header.itemAt(0).name.raw == archiveStrings().ui_ColName)
    Swag.assert(viewer.list.header.itemAt(1).name.raw == archiveStrings().ui_ColSize)
    expect host.app.setLanguage(ReferenceLanguage)
    host.notify(.LanguageChanged)
}
