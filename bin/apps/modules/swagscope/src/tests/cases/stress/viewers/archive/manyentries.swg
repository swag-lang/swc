#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// Open an archive with far more members than the visible tree and render its expanded folder.
#[Swag.TestTag("stress")]
#test
{
    var entries: Array'ZipFixtureEntry
    for index in 1_500
    {
        var entry: ZipFixtureEntry
        entry.name = Format.toString("records/item%.txt", index)
        entry.plain.add("archived record\n")
        entry.packed = entry.plain
        entries.add(#move entry)
    }
    let file = Testing.tempFilePath("scope-many-entries-", ".zip")
    defer discard catch File.delete(file)
    let bytes = buildZipEntries(entries.toSlice())
    expect File.writeAllBytes(file, bytes.toSlice())

    let archive = expect Archive.Zip.load(file)
    Swag.require(archive.entries.count == 1_500)
    Swag.require(archive.entries[0].path == "records/item0.txt")

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    shipFrame(&host)
    var registry = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move registry)
    window.thumbnailMode = true
    window.resize(900, 600)
    window.openFile(file)
    completeViewerWindowClassification(&host, window)
    Swag.require(window.choices[window.activeChoiceIndex].key == "archive")
    let view = assume cast(*Archive.Panel, window.currentView)
    completeViewerBackgroundLoad(&host, &view.load)
    Swag.require(view.archive.entries.count == 1_500 and view.entryLines.count == 1_500)
    Swag.require(view.list.lineCount() == 1_501)
    var image = host.render(&host.surfaceWnd)
    Swag.require(image.isValid())
}
