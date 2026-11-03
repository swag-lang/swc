#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// Content the picture is judged on: a readable header, a run of zeros, high bytes, and a line of
// text. Each of those is drawn differently, and the golden is what says they still are.
func writePreviewFile()->String
{
    let fileName = Gui.Testing.tempFilePath("viewer-hex-preview-", ".bin")

    var payload: Array'u8
    let header = "Swag Scope hex preview"
    payload.add(cast(const [..] u8, header))
    for 42 do
        payload.add(0)
    for index in 64 do
        payload.add(cast(u8, 0xC0 + index % 0x40))
    let text = "name=value; the text column stays readable"
    payload.add(cast(const [..] u8, text))
    for index in 128 do
        payload.add(index % 3 == 0 ? 0'u8 : cast(u8, ((index * 7) & 0xFF)))

    discard expect File.writeAllBytes(fileName, payload.toSlice())
    return fileName
}

func completeHexViewerSearch(host: *Testing.HeadlessHost, window: *ViewerWindow)
{
    var steps = 0'u32
    while window.searchTimer and steps < 128
    {
        host.fireTimer(window.searchTimer)
        steps += 1
    }

    Swag.require(window.searchTimer == null)
}

func completeHexViewerOpen(host: *Testing.HeadlessHost, window: *ViewerWindow)
{
    completeViewerWindowClassification(host, window)
    var steps = 0'u32
    while window.activeChoiceIndex < window.instances.count and steps < 4_096
    {
        let instance = &window.instances[window.activeChoiceIndex]
        if not instance.view or not instance.isLoading or not instance.isLoading() do
            break
        Threading.Thread.sleep(1'ms)
        host.fireTimers()
        steps += 1
    }
}

// Switches `window` to the hexadecimal viewer, and returns it once its document is open.
func selectHexViewer(host: *Testing.HeadlessHost, window: *ViewerWindow)->*Hex.Panel
{
    var hexIndex = Swag.U32.Max
    for choice, index in window.choices where choice.key == "hex" do
        hexIndex = cast(u32, index)
    Swag.require(hexIndex != Swag.U32.Max)
    window.selectViewer(hexIndex)
    completeHexViewerOpen(host, window)
    return assume cast(*Hex.Panel, window.currentView)
}

func completeHexViewerAnalysis(host: *Testing.HeadlessHost, view: *Hex.Panel)
{
    completeViewerBackgroundLoad(host, &view.analysis)
    Swag.require(not view.analysis.isPending())
}

// The host keeps a viewer-specific pattern intact across scanner chunks, publishes every exact
// byte range, and gives invalid input an explanation without opening a file scan.
#[Swag.TestTag("golden")]
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-hex-search-", ".bin")
    defer discard catch File.delete(fileName)

    var payload: Array'u8
    payload.resize(ViewerWindow.SearchChunkSize + 256)
    let first  = ViewerWindow.SearchChunkSize - 2
    let second = ViewerWindow.SearchChunkSize + 80
    for offset in [first, second]
    {
        payload[offset + 0] = 0xDE
        payload[offset + 1] = 0xAD
        payload[offset + 2] = 0xBE
        payload[offset + 3] = 0xEF
    }

    expect File.writeAllBytes(fileName, payload.toSlice())

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    shipFrame(&host)
    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(fileName)
    completeHexViewerOpen(&host, window)
    let view = selectHexViewer(&host, window)

    window.showSearch()
    window.searchBox.setText("DE AD ?E EF")
    completeHexViewerSearch(&host, window)
    Swag.require(window.searchMatches.count == 2 and
                 window.searchMatches[0].offset == first and
                 window.searchMatches[1].offset == second)
    Swag.require(window.searchMatches[0].length == 4 and view.grid.searchHits and view.grid.searchHits.count == 2)
    Swag.require(view.grid.matchStart == first and view.grid.matchLength == 4)
    Swag.require(window.searchBox.name.raw == Hex.texts().ui_SearchPlaceholder)
    Swag.require(not window.searchOptionsButton.isLocallyVisible())

    view.setValueWidth(2)
    view.setFormat(1)
    Swag.require(view.grid.grouping == .Unsigned32)
    window.searchBox.setText("value: 4022250974")
    completeHexViewerSearch(&host, window)
    Swag.require(window.searchMatches.count == 2 and window.searchMatches[0].offset == first)

    window.layoutFileInfo()
    window.resize(960, 680)
    window.applyLayout()
    host.moveMouse({-1, -1})
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.hex.search-inspector")

    window.searchBox.setText("4G")
    Swag.require(window.searchComplete)
    Swag.require(window.searchMatches.isEmpty())
    Swag.require(window.searchCountLabel.text() == "!")
    Swag.require(window.searchCountLabel.toolTip == Hex.texts().ui_SearchPatternError and not window.searchBox.isValid())

    // The inspector reads the value under the caret the way the grid shows it, then the same
    // bytes in the other common readings.
    view.grid.moveCaret(first, false)
    with let inspector = view.inspectorView
    {
        Swag.require(.headline == "2 917 007 360" and .caption == "u32 LE at 0x0003FFFC")
        Swag.require(.readings.count == 5 and .readings[0].value == "222")
        Swag.require(.readings[2].label == "s32" and .readings[2].value == "-272 716 322")
        Swag.require(.readings[3].label == "u32 BE" and .readings[3].value == "3 735 928 559")
        Swag.require(.fields.isEmpty())
    }

    Swag.require(Utf8.contains(view.details.toSlice(), "0x0003FFFE"))
}

// The analysis panel turns an unfamiliar file into exact byte evidence, and every inferred string
// remains a navigation target rather than detached report text.
#[Swag.TestTag("golden")]
#test
{
    let fileName = writePreviewFile()
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(1_100, 700)
    shipFrame(&host)

    // Use the shipped window rather than a viewer-only approximation: the integration contract
    // includes the readings at the foot of the document and the panel beside it, whose toggle
    // the window keeps off screen and names in its lens.
    var index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(fileName)
    completeHexViewerOpen(&host, window)
    let view = selectHexViewer(&host, window)
    Swag.require(window.currentInfo != null and window.currentInfo.parent == window.readingLine)
    Swag.require(not view.analysisButton.isLocallyVisible())
    let toggle = window.sendComputeCommandStateEvent(ViewerCommands.SidePanel)
    Swag.require(toggle.name == view.analysisButton.toolTip and not toggle.hidden and not toggle.checked)

    view.analysisButton.setChecked(true)
    view.analysisButton.sigCheckedChanged.call(view.analysisButton)
    completeHexViewerAnalysis(&host, view)

    Swag.require(view.analysisView.isLocallyVisible() and view.analysisView.result.scanned == view.grid.doc.fileSize)
    Swag.require(view.analysisView.result.entropy > 0 and view.analysisView.histogram.total == view.grid.doc.fileSize)
    Swag.require(view.analysisView.stringsList.virtualCount == view.analysisView.result.strings.count)
    Swag.require(view.analysisView.result.strings.count >= 2)

    let first = &view.analysisView.result.strings[0]
    view.analysisView.stringsList.selectLine(0)
    Swag.require(view.grid.selectionStart() == first.offset and view.grid.selectionLength() == first.length)

    // Re-running analysis derives its range from the live grid selection. It does not replay the
    // stale whole-file range that originally populated the panel.
    let selectedStart  = view.grid.selectionStart()
    let selectedLength = view.grid.selectionLength()
    view.analysisView.analyzeButton.sigPressed.call(cast(*Button, view.analysisView.analyzeButton))
    completeHexViewerAnalysis(&host, view)
    Swag.require(view.analysisView.selection and view.analysisView.result.range.offset == selectedStart)
    Swag.require(view.analysisView.result.range.length == selectedLength)
    Swag.require(not view.analysisView.stringsList.header.flags.has(.Separators))

    window.layoutFileInfo()
    window.resize(1_100, 700)
    window.applyLayout()
    host.moveMouse({-1, -1})
    var image = host.renderSettled(window)
    assertScopeImageGolden(&image, "viewer.hex.analysis")

    view.closeAnalysis()
    view.grid.moveCaret(0x80, false)
    view.grid.moveCaret(0x89, true)
    let selectionStart  = view.grid.selectionStart()
    let selectionLength = view.grid.selectionLength()
    view.analysisButton.setChecked(true)
    view.analysisButton.sigCheckedChanged.call(view.analysisButton)
    completeHexViewerAnalysis(&host, view)
    Swag.require(view.analysisView.selection and view.analysisView.result.range.offset == selectionStart)
    Swag.require(view.analysisView.result.range.length == selectionLength and view.analysisView.result.scanned == selectionLength)
}

// The typed command group stays bounded and keeps byte order beside the representation controls.
#[Swag.TestTag("golden")]
#test
{
    let fileName = writeSampleFile()
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(900, 600)

    let view = hexTestViewer(&host, fileName, 900, 560)
    Swag.require(view.commands.position.width <= 640)
    Swag.require(view.optionsButton.parent == view.commands)
    Swag.require(not view.bigEndian and view.rowWidthIndex == 0)
    Swag.require(view.details == "0x00000000")
    Testing.assertContentFits(view)

    // At the band a window of the host's minimum size leaves, the bytes still hold the clear
    // majority of the surface and the grid still gives whole groups.
    view.resize(640, 320)
    view.applyLayout()
    view.grid.refreshLayout()
    Swag.require(view.grid.clientRect().width > 640 * 0.6)
    Swag.require(view.grid.bytesPerRow >= Hex.MinBytesPerRow)
    Swag.require(view.grid.contentWidth() <= view.grid.clientRect().width)
    var image = host.renderSettled(view.commands)
    image.crop(view.commands.surfaceRect())
    assertScopeImageGolden(&image, "viewer.hex.command-bar")
    discard host.render(view)
}

// Photographed on the palette the application ships on: the header, faint zero bytes, the caret in
// both columns, and a selection.
#[Swag.TestTag("golden")]
#test
{
    let fileName = writePreviewFile()
    defer discard catch File.delete(fileName)

    var host: Testing.HeadlessHost
    host.setup(860, 460)

    with let view = hexTestViewer(&host, fileName, 860, 460)
    {
        .grid.setBytesPerRow(16, false)
        .grid.moveCaret(0x80, false)
        .grid.moveCaret(0x89, true)
    }

    var searchHits: Array'Viewer.SearchMatch
    searchHits.add({offset: 0x15, length: 4})
    searchHits.add({offset: 0x78, length: 6})
    view.grid.setSearchMatches(&searchHits)
    discard view.grid.revealRange(0x78, 6)
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)

    var image = host.render(view)
    assertScopeImageGolden(&image, "viewer.hex.document")
}
