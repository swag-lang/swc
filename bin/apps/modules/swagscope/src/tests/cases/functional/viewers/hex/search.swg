#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Gui.Testing, Viewers

func openHexSearchWindow(host: *Testing.HeadlessHost, fileName: string)->*ViewerWindow
{
    let window = framedViewerWindow(host, fileName, false)
    var found: bool
    for choice, index in window.choices where choice.key == "hex"
    {
        window.selectViewer(cast(u32, index))
        found = true
        break
    }

    Swag.require(found)
    completeQueuedViewerFile(host, window)
    window.showSearch()
    return window
}

// `selection:` captures the current selection once, seeks directly to it, and accepts only
// complete patterns inside that half-open byte range, including patterns crossing read chunks.
#test
{
    let fileName = Testing.tempFilePath("scope-hex-search-range-", ".bin")
    defer discard catch File.delete(fileName)

    let start = 17'u64
    let length = ViewerWindow.SearchChunkSize + 5
    let end = start + length
    var bytes: Array'u8
    bytes.resize(end + 20)
    // Cross the lower boundary, match just inside it, cross a stream chunk, fit at the upper
    // boundary, and cross that boundary. Only the three complete in-range matches count.
    bytes[start - 1] = 0xAA
    bytes[start] = 0xBB
    bytes[start + 2] = 0xAA
    bytes[start + 3] = 0xBB
    bytes[start + ViewerWindow.SearchChunkSize - 1] = 0xAA
    bytes[start + ViewerWindow.SearchChunkSize] = 0xBB
    bytes[end - 3] = 0xAA
    bytes[end - 2] = 0xBB
    bytes[end - 1] = 0xAA
    bytes[end] = 0xBB
    expect File.writeAllBytes(fileName, bytes.toSlice())

    var host: Testing.HeadlessHost
    let window = openHexSearchWindow(&host, fileName)
    let view = assume cast(*Hex.Panel, window.instances[window.activeChoiceIndex].view)
    window.searchBox.setText("selection: hex: AA BB")
    // No selection is reported as a visible query error before reading the file.
    Swag.require(window.searchTimer == null and window.searchMatches.isEmpty())
    Swag.require(window.searchError == Hex.texts().ui_SearchSelectionRequired)

    window.searchBox.setText("")
    view.grid.selectRange(start, length)
    Swag.require(view.grid.hasSelection() and view.grid.selectionStart() == start and view.grid.selectionLength() == length)
    var plan: Viewer.SearchPlan
    let parseState = view.prepareSearch("selection: hex: AA BB", &plan)
    Swag.require(parseState == .Valid and plan.byteRange.offset == start and plan.byteRange.length == length)
    window.searchBox.setText("selection: hex: AA BB")
    Swag.require(window.searchByteRange.length == length and window.searchByteRange.offset == start)
    Swag.require(window.searchCarryBase == start)
    Swag.require(window.searchStream.isOpen())
    Swag.require(window.searchTotalBytes == length and window.searchBytesRead == 0)
    host.fireTimer(window.searchTimer)
    Swag.require(window.searchProcessed > 0 and window.searchProcessed < length)
    let progress = Format.toString(appStrings().ui_SearchProgress,
                                   StrConv.toDisplaySize(window.searchProcessed),
                                   StrConv.toDisplaySize(length))
    Swag.require(window.searchCountLabel.toolTip == progress)
    var steps = 0'u32
    while window.searchTimer and steps < 8
    {
        host.fireTimer(window.searchTimer)
        steps += 1
    }
    Swag.require(window.searchComplete and window.searchProcessed == length)
    Swag.require(window.searchMatches.count == 3)
    Swag.require(window.searchMatches[0].offset == start + 2)
    Swag.require(window.searchMatches[1].offset == start + ViewerWindow.SearchChunkSize - 1)
    Swag.require(window.searchMatches[2].offset == end - 3)

    // An explicit one-byte selection differs from a caret, even though both have length one.
    window.searchBox.setText("")
    view.grid.selectRange(start + 2, 1)
    Swag.require(view.grid.hasSelection() and view.grid.selectionLength() == 1)
    window.searchBox.setText("selection: AA")
    Swag.require(window.searchByteRange.offset == start + 2 and window.searchByteRange.length == 1)
    host.fireTimer(window.searchTimer)
    Swag.require(window.searchComplete and window.searchMatches.count == 1)
    Swag.require(window.searchMatches[0].offset == start + 2)
}

// The hexadecimal scan publishes its first stable chunk before EOF, so F3 can navigate those hits.
#test
{
    let fileName = Testing.tempFilePath("scope-hex-search-live-", ".bin")
    defer discard catch File.delete(fileName)

    var bytes: Array'u8
    bytes.resize(ViewerWindow.SearchChunkSize * 3)
    bytes[10]  = 0xAA
    bytes[100] = 0xAA
    expect File.writeAllBytes(fileName, bytes.toSlice())

    var host: Testing.HeadlessHost
    let window = openHexSearchWindow(&host, fileName)
    window.searchBox.setText("AA")
    Swag.require(window.searchTimer != null and window.searchStream.isOpen())
    Swag.require(window.searchCancelButton.isLocallyVisible() and window.searchCancelButton.isEnabled())

    host.fireTimer(window.searchTimer)
    Swag.require(window.searchProcessed > 0 and window.searchProcessed < bytes.count)
    Swag.require(window.searchMatches.count == 2 and window.searchIndex == 0)
    Swag.require(window.searchMatch == 10 and window.searchNext.isEnabled())
    Swag.require(Utf8.contains(window.searchCountLabel.text(), "KB"))
    let progress = Format.toString(appStrings().ui_SearchProgress,
                                   StrConv.toDisplaySize(window.searchProcessed),
                                   StrConv.toDisplaySize(bytes.count))
    Swag.require(window.searchCountLabel.toolTip == progress)

    host.click(window.searchNext.surfaceRect().center())
    Swag.require(window.searchIndex == 1 and window.searchMatch == 100)
    host.click(window.searchCancelButton.surfaceRect().center())
    Swag.require(window.searchTimer == null and not window.searchStream.isOpen())
    Swag.require(window.searchCancelled and window.searchComplete)
    Swag.require(window.searchMatches.count == 2 and window.searchIndex == 1)
    Swag.require(window.searchCountLabel.text() == "2/2")
    Swag.require(Utf8.contains(window.searchCountLabel.toolTip, "cancelled"))

    window.findPrevious()
    Swag.require(window.searchIndex == 0 and window.searchMatch == 10)
    window.findNext()
    Swag.require(window.searchIndex == 1 and window.searchMatch == 100)
}
