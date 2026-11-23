#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

#[Swag.TestTag("stress")]
#test
{
    let fileName = Testing.tempFilePath("scope-hex-search-cap-", ".bin")
    defer discard catch File.delete(fileName)

    let size = ViewerWindow.SearchMatchLimit + ViewerWindow.SearchChunkSize * 2
    var bytes: Array'u8
    bytes.resize(size)
    for index in size do
        bytes[index] = 0xAA
    expect File.writeAllBytes(fileName, bytes.toSlice())

    var host:  Testing.HeadlessHost
    let window = framedViewerWindow(&host, fileName, false)
    var found: bool
    for choice, index in window.choices where choice.key == "hex"
    {
        window.selectViewer(cast(u32, index))
        found = true
        break
    }

    Swag.require(found)
    completeQueuedViewerFile(&host, window)
    window.showSearch()
    window.searchBox.setText("AA")

    var steps = 0'u32
    while window.searchTimer and steps < 4_096
    {
        host.fireTimer(window.searchTimer)
        steps += 1
    }

    Swag.require(window.searchTimer == null and window.searchComplete)
    Swag.require(window.searchProcessed == size)
    Swag.require(window.searchMatchesCapped and window.searchMatches.count == ViewerWindow.SearchMatchLimit)
    Swag.require(window.searchCountLabel.text() == "1/100000+")
    Swag.require(window.searchCountLabel.toolTip == Format.toString(appStrings().ui_SearchResultsLimited,
                                                                    ViewerWindow.SearchMatchLimit))

    window.searchIndex = ViewerWindow.SearchMatchLimit - 1
    window.findNext()
    Swag.require(window.searchIndex == 0 and window.searchMatch == 0)
    window.findPrevious()
    Swag.require(window.searchIndex == ViewerWindow.SearchMatchLimit - 1 and
                 window.searchMatch == ViewerWindow.SearchMatchLimit - 1)
}

// The match cap and progress count apply to the captured selection, and the scanner never reads
// its surrounding file prefix or suffix.
#[Swag.TestTag("stress")]
#test
{
    let fileName = Testing.tempFilePath("scope-hex-search-range-cap-", ".bin")
    defer discard catch File.delete(fileName)

    let start = 113'u64
    let length = ViewerWindow.SearchMatchLimit + ViewerWindow.SearchChunkSize * 2
    var bytes: Array'u8
    bytes.resize(start + length + 256)
    for index in bytes.count do
        bytes[index] = 0xAA
    expect File.writeAllBytes(fileName, bytes.toSlice())

    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, fileName, false)
    var found: bool
    for choice, index in window.choices where choice.key == "hex"
    {
        window.selectViewer(cast(u32, index))
        found = true
        break
    }

    Swag.require(found)
    completeQueuedViewerFile(&host, window)
    let view = assume cast(*Hex.Panel, window.instances[window.activeChoiceIndex].view)
    view.grid.selectRange(start, length)
    window.showSearch()
    window.searchBox.setText("selection: AA")

    var steps = 0'u32
    while window.searchTimer and steps < 4_096
    {
        host.fireTimer(window.searchTimer)
        steps += 1
    }

    Swag.require(window.searchTimer == null and window.searchComplete)
    Swag.require(window.searchByteRange.offset == start and window.searchByteRange.length == length)
    Swag.require(window.searchProcessed == length and window.searchBytesRead == length)
    Swag.require(window.searchMatchesCapped and window.searchMatches.count == ViewerWindow.SearchMatchLimit)
    Swag.require(window.searchMatches[0].offset == start)
    Swag.require(window.searchMatches[ViewerWindow.SearchMatchLimit - 1].offset ==
                 start + ViewerWindow.SearchMatchLimit - 1)

    // The explicit range scope uses the same bounded result set and its offsets remain absolute.
    window.searchBox.setText(Format.toString("range:0d%:0d%:AA", start, length))
    steps = 0
    while window.searchTimer and steps < 4_096
    {
        host.fireTimer(window.searchTimer)
        steps += 1
    }

    Swag.require(window.searchTimer == null and window.searchComplete)
    Swag.require(window.searchByteRange.offset == start and window.searchByteRange.length == length)
    Swag.require(window.searchProcessed == length and window.searchBytesRead == length)
    Swag.require(window.searchMatchesCapped and window.searchMatches.count == ViewerWindow.SearchMatchLimit)
    Swag.require(window.searchMatches[0].offset == start)
    Swag.require(window.searchMatches[ViewerWindow.SearchMatchLimit - 1].offset ==
                 start + ViewerWindow.SearchMatchLimit - 1)
}
