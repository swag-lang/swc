#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

// Payload every streaming test reads. It is larger than one resident window, so a test that walks
// to its end proves the window moved instead of proving the file was small.
const StreamedFileSize = HexWindowSize * 32 + 1234'u64

// Writes readable content at exact offsets. A checked-in fixture would carry whatever line endings
// the checkout gave it, which moves every offset an assertion names.
func writeSampleFile()->String
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("viewer_hex_sample_%.bin", Guid64.random()).toString())
    let content       = "Swag Scope hex fixture\nASCII text and symbols: 00 FF 42.\n"
    discard expect File.writeAllBytes(fileName.toString(), Swag.makeSlice(cast(const [*] u8) content.buffer, content.count))
    return fileName
}

// Writes a deterministic file whose byte at `offset` is that offset truncated to eight bits, so an
// assertion about a distant byte states an exact expected value.
func writeStreamedFile(size: u64)->String
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("viewer_hex_stream_%.bin", Guid64.random()).toString())

    var payload: Array'u8
    payload.resize(size)
    for index in size do
        payload[index] = cast(u8) (index & 0xFF)
    discard expect File.writeAllBytes(fileName.toString(), payload.toSlice())
    return fileName
}

// Content the picture is judged on: a readable header, a run of zeros, high bytes, and a line of
// text. Each of those is drawn differently, and the golden is what says they still are.
func writePreviewFile()->String
{
    let fileName = Gui.Testing.tempFilePath("viewer-hex-preview-", ".bin")

    var payload: Array'u8
    let header = "Swag Scope hex preview"
    for index in header.count do
        payload.add(header[index])
    for 42 do
        payload.add(0)
    for index in 64 do
        payload.add(cast(u8) (0xC0 + index % 0x40))
    let text = "name=value; the text column stays readable"
    for index in text.count do
        payload.add(text[index])
    for index in 128 do
        payload.add(index % 3 == 0 ? 0'u8 : cast(u8) ((index * 7) & 0xFF))

    discard expect File.writeAllBytes(fileName.toString(), payload.toSlice())
    return fileName
}

func createTestViewer(host: *Testing.HeadlessHost, fileName: string, width, height: f32)->*HexViewer
{
    registerHexStrings(&host.app)
    let commands      = Wnd.create'Wnd(&host.root, {0, 0, 640, 36})
    var viewerSession = openTestViewer(hexViewerPlugin(), &host.root, fileName, commandParent: commands, infoParent: commands)
    let view          = cast(*HexViewer) viewerSession.view!
    completeViewerBackgroundLoad(host, &view.load, view.loadTimer)
    view.dockStyle = .Center
    view.resize(width, height)
    view.applyLayout()
    view.grid.refreshLayout()
    return view
}

func completeHexViewerSearch(host: *Testing.HeadlessHost, window: *ViewerWindow)
{
    var steps = 0'u32
    while window.searchTimer and steps < 128
    {
        host.fireTimer(window.searchTimer)
        steps += 1
    }

    Swag.assert(window.searchTimer == null)
}

func completeHexViewerOpen(host: *Testing.HeadlessHost, window: *ViewerWindow)
{
    completeViewerWindowClassification(host, window)
    var steps = 0'u32
    while window.activeChoiceIndex < window.instances.count and steps < 4_096
    {
        let instance = &window.instances[window.activeChoiceIndex]
        if !instance.view or !instance.isLoading or !instance.isLoading!(instance.view!) do
            break
        Threading.Thread.sleep(1'ms)
        host.fireTimers()
        steps += 1
    }
}

func completeHexViewerAnalysis(host: *Testing.HeadlessHost, view: *HexViewer)
{
    var steps = 0'u32
    while view.analysisTimer and steps < 4_096
    {
        Threading.Thread.sleep(1'ms)
        host.fireTimer(view.analysisTimer)
        steps += 1
    }

    Swag.assert(view.analysisTimer == null)
}

// A file-open error crosses the viewer boundary instead of appearing as an empty byte grid.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 420)
    defer host.shutdown()

    var result = openTestViewer(hexViewerPlugin(), &host.root, "this-file-does-not-exist.bin", commandParent: &host.root, infoParent: &host.root)
    Swag.assert(result.view != null and result.commands != null)
    let view = cast(*HexViewer) result.view!
    completeViewerBackgroundLoad(&host, &view.load, view.loadTimer)
    Swag.assert(!view.failureReason.isEmpty())
}

// Typed grouping changes scalar presentation without taking byte-exact movement and selection away.
#test
{
    let fileName = writeStreamedFile(4096)
    defer discard catch File.delete(fileName.toString())

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()

    let view = createTestViewer(&host, fileName.toString(), 900, 560)
    let grid = view.grid
    grid.setGrouping(.Unsigned32)
    Swag.assert(grid.valueSize() == 4 and grid.displayGroupSize() == 4)
    Swag.assert(grid.selectionStart() == 0 and grid.selectionLength() == 1)

    host.focus(grid)
    host.keyPress(.Right)
    Swag.assert(grid.caret == 1 and grid.selectionStart() == 1 and grid.selectionLength() == 1)
    host.keyPress(.Right, .Shift)
    Swag.assert(grid.caret == 2 and grid.selectionStart() == 1 and grid.selectionLength() == 2)

    grid.setGrouping(.Float64)
    Swag.assert(grid.valueSize() == 8 and grid.selectionStart() == 1 and grid.selectionLength() == 2)
    grid.setGrouping(.Bytes)
    Swag.assert(grid.selectionLength() == 2 and grid.hasSelection())

    // Width and spelling are independent controls. Float appears only where the selected width
    // has a corresponding representation.
    view.widthCombo.setSelectedIndex(1)
    view.formatCombo.setSelectedIndex(1)
    Swag.assert(grid.grouping == .Unsigned16)
    view.widthCombo.setSelectedIndex(3)
    view.formatCombo.setSelectedIndex(3)
    Swag.assert(grid.grouping == .Float64 and grid.valueSize() == 8)
    view.widthCombo.setSelectedIndex(0)
    Swag.assert(view.formatCombo.items.count == 3 and grid.grouping == .Bytes)
}

// The dump copy is the view in text form: the offset, the grouped bytes, and the text column.
#test
{
    let text = formatHexDump([0'u8, 1'u8, 0x20'u8, 0x41'u8, 0xFF'u8], 0x20, 16, 16)
    Swag.assert(Utf8.contains(text.toSlice(), "0000000000000020"))
    Swag.assert(Utf8.contains(text.toSlice(), "00 01 20 41 FF"))
    Swag.assert(Utf8.contains(text.toSlice(), ".. A."))

    let narrow = formatHexDump([0xAA'u8, 0xBB'u8, 0xCC'u8], 0, 2, 8)
    Swag.assert(Utf8.contains(narrow.toSlice(), "00000000  AA BB"))
    Swag.assert(Utf8.contains(narrow.toSlice(), "00000002  CC"))
}

// Go To keeps bare values hexadecimal, and accepts explicit decimal, percentage, named, and
// caret-relative positions.
#test
{
    Swag.assert(parseHexOffset("1F", 0, 1000) == 0x1F)
    Swag.assert(parseHexOffset("  0x1f  ", 0, 1000) == 0x1F)
    Swag.assert(parseHexOffset("00 1F", 0, 1000) == 0x1F)
    Swag.assert(parseHexOffset("0d31", 0, 1000) == 31)
    Swag.assert(parseHexOffset("50%", 0, 1000) == 499)
    Swag.assert(parseHexOffset("caret", 0x20, 1000) == 0x20)
    Swag.assert(parseHexOffset("FileSize", 0, 1000) == 999)
    Swag.assert(parseHexOffset("+10", 0x20, 1000) == 0x30)
    Swag.assert(parseHexOffset("-10", 0x20, 1000) == 0x10)
    Swag.assert(parseHexOffset("-1000", 0x20, 1000) == 0)
    Swag.assert(parseHexOffset("FFFFFF", 0, 1000) == 999)
    Swag.assert(parseHexOffset("101%", 0, 1000) == Swag.U64.Max)
    Swag.assert(parseHexOffset("0dG", 0, 1000) == Swag.U64.Max)
    Swag.assert(parseHexOffset("zz", 0, 1000) == Swag.U64.Max)
    Swag.assert(parseHexOffset("", 0, 1000) == Swag.U64.Max)
    Swag.assert(parseHexOffset("10", 0, 0) == Swag.U64.Max)
}

// Binary queries preserve their exact byte span: pairs can carry nibble wildcards, text is UTF-8,
// and an active scalar follows both the selected representation and byte order.
#test
{
    let wildcard = parseHexSearch("hex: 4D 5? ?? A?", .Bytes, false)
    Swag.assert(wildcard.state == .Valid and wildcard.pattern.length() == 4)
    Swag.assert(wildcard.pattern.values[0] == 0x4D and wildcard.pattern.masks[0] == 0xFF)
    Swag.assert(wildcard.pattern.values[1] == 0x50 and wildcard.pattern.masks[1] == 0xF0)
    Swag.assert(wildcard.pattern.values[2] == 0 and wildcard.pattern.masks[2] == 0)
    Swag.assert(wildcard.pattern.values[3] == 0xA0 and wildcard.pattern.masks[3] == 0xF0)

    let text = parseHexSearch("text: café", .Bytes, false)
    Swag.assert(text.state == .Valid and text.pattern.length() == ("café").count)
    Swag.assert(text.pattern.values[text.pattern.length() - 2] == 0xC3 and text.pattern.values[text.pattern.length() - 1] == 0xA9)

    let little = parseHexSearch("value: 305419896", .Unsigned32, false)
    let big    = parseHexSearch("value: 305419896", .Unsigned32, true)
    Swag.assert(little.state == .Valid and little.pattern.values[0] == 0x78 and little.pattern.values[3] == 0x12)
    Swag.assert(big.state == .Valid and big.pattern.values[0] == 0x12 and big.pattern.values[3] == 0x78)

    let signed = parseHexSearch("value: -2", .Signed16, false)
    Swag.assert(signed.state == .Valid and signed.pattern.values[0] == 0xFE and signed.pattern.values[1] == 0xFF)
    let real = parseHexSearch("value: 1", .Float32, false)
    Swag.assert(real.state == .Valid and real.pattern.values[0] == 0 and real.pattern.values[2] == 0x80 and real.pattern.values[3] == 0x3F)

    Swag.assert(parseHexSearch("4", .Bytes, false).state == .Incomplete)
    Swag.assert(parseHexSearch("4G", .Bytes, false).error == .Pattern)
    Swag.assert(parseHexSearch("value: 70000", .Unsigned16, false).error == .Value)
}

// Range analysis streams fixed byte counts and keeps inferred strings tied to their source bytes.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-hex-analysis-", ".bin")
    defer discard catch File.delete(fileName)

    var payload: Array'u8
    payload.resize(256)
    let ascii = "HELLO-WORLD"
    for value, index in ascii do
        payload[16 + index] = value
    let little = "WideLE"
    for value, index in little
    {
        payload[64 + index * 2]     = value
        payload[64 + index * 2 + 1] = 0
    }

    let big = "WideBE"
    for value, index in big
    {
        payload[96 + index * 2]     = 0
        payload[96 + index * 2 + 1] = value
    }

    payload[200] = 0xFF
    expect File.writeAllBytes(fileName, payload.toSlice())

    var operation: HexAnalysisOperation
    operation.start(fileName, {0, payload.count})
    Jobs.wait(&operation.job)
    let result = operation.finish()
    Swag.assert(result.failureReason.isEmpty() and !result.cancelled and result.scanned == payload.count)
    Swag.assert(result.histogram[0xFF] == 1 and result.histogram[cast(u8) 'H'] == 1)
    Swag.assert(result.zeroCount > 200 and result.printableCount == ascii.count + little.count + big.count)
    Swag.assert(result.entropy > 0 and result.entropy < 8)

    var foundAscii:  bool
    var foundLittle: bool
    var foundBig:    bool
    for one in result.strings
    {
        if one.kind == .Ascii and one.offset == 16 and one.length == ascii.count do
            foundAscii = one.text.toString() == ascii
        if one.kind == .Utf16Little and one.offset == 64 and one.length == little.count * 2 do
            foundLittle = one.text.toString() == little
        if one.kind == .Utf16Big and one.offset == 96 and one.length == big.count * 2 do
            foundBig = one.text.toString() == big
    }

    Swag.assert(foundAscii and foundLittle and foundBig)

    var cancelled = 1'u32
    let stopped   = analyzeHexRange(fileName, {0, payload.count}, &cancelled)
    Swag.assert(stopped.cancelled and !stopped.scanned)
}

// The host keeps a viewer-specific pattern intact across scanner chunks, publishes every exact
// byte range, and gives invalid input an explanation without opening a file scan.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-hex-search-", ".bin")
    defer discard catch File.delete(fileName)

    var payload: Array'u8
    payload.resize(ViewerSearchChunkSize + 256)
    let first  = ViewerSearchChunkSize - 2
    let second = ViewerSearchChunkSize + 80
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
    defer host.shutdown()
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(fileName)
    completeHexViewerOpen(&host, window)

    var hexIndex = Swag.U32.Max
    for choice, index in window.choices where choice.key == "hex" do
        hexIndex = cast(u32) index
    Swag.assert(hexIndex != Swag.U32.Max)
    window.selectViewer(hexIndex)
    completeHexViewerOpen(&host, window)
    let view = cast(*HexViewer) window.currentView!

    window.searchBox.setText("DE AD ?E EF")
    completeHexViewerSearch(&host, window)
    Swag.assert(window.searchMatches.count == 2 and window.searchMatches[0].offset == first and window.searchMatches[1].offset == second)
    Swag.assert(window.searchMatches[0].length == 4 and view.grid.searchHits and view.grid.searchHits!.count == 2)
    Swag.assert(view.grid.matchStart == first and view.grid.matchLength == 4)
    Swag.assert(window.searchBox.name.raw == hexStrings().ui_SearchPlaceholder)
    Swag.assert(!window.searchOptionsButton.isLocallyVisible())

    view.widthCombo.setSelectedIndex(2)
    view.formatCombo.setSelectedIndex(1)
    Swag.assert(view.grid.grouping == .Unsigned32)
    window.searchBox.setText("value: 4022250974")
    completeHexViewerSearch(&host, window)
    Swag.assert(window.searchMatches.count == 2 and window.searchMatches[0].offset == first)

    // The temporary path has a random suffix; keep the visual contract focused on the viewer.
    window.infoNameLabel.setText("scope-hex-search.bin")
    window.infoNameLabel.toolTip = "scope-hex-search.bin"
    window.layoutFileInfo()
    window.resize(960, 680)
    window.applyLayout()
    host.moveMouse({-1, -1})
    host.settleAnimations(window, 4)
    var image = host.render(window)
    Pixel.Testing.assertImageGolden(&image, "viewer.hex.search-inspector")

    window.searchBox.setText("4G")
    Swag.assert(window.searchComplete)
    Swag.assert(window.searchMatches.isEmpty())
    Swag.assert(window.searchCountLabel.text() == "!")
    Swag.assert(window.searchCountLabel.toolTip == hexStrings().ui_SearchPatternError and !window.searchBox.isValid())

    view.grid.moveCaret(first, false)
    Swag.assert(view.inspectorLabel != null and Utf8.contains(view.inspectorLabel!.text(), "@0003FFFE"))
    Swag.assert(Utf8.contains(view.inspectorLabel!.text(), "%"))
    Swag.assert(Utf8.contains(view.inspectorLabel!.toolTip.toSlice(), "u32 4022250974"))
    Swag.assert(Utf8.contains(view.inspectorLabel!.toolTip.toSlice(), "b8 0b11011110"))
    Swag.assert(Utf8.contains(view.inspectorLabel!.toolTip.toSlice(), "o8 0o336 · bool true"))
}

// The analysis panel turns an unfamiliar file into exact byte evidence, and every inferred string
// remains a navigation target rather than detached report text.
#test
{
    let fileName = writePreviewFile()
    defer discard catch File.delete(fileName.toString())

    var host: Testing.HeadlessHost
    host.setup(1_100, 700)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    // Use the shipped window rather than a viewer-only approximation: the integration contract
    // includes the information panel above, the viewer bar below, and the host-owned toggle at
    // the right edge of that information panel.
    let index  = createViewerPluginRegistry()
    let window = ViewerWindow.create(&host.surfaceWnd, #move index)
    window.openFile(fileName.toString())
    completeHexViewerOpen(&host, window)

    var hexIndex = Swag.U32.Max
    for choice, index in window.choices where choice.key == "hex" do
        hexIndex = cast(u32) index
    Swag.assert(hexIndex != Swag.U32.Max)
    window.selectViewer(hexIndex)
    completeHexViewerOpen(&host, window)
    let view = cast(*HexViewer) window.currentView!
    Swag.assert(window.currentInfo != null)
    Swag.assert(view.analysisButton.position.x - window.currentInfo!.position.right() == ViewerInfoSideButtonSpacing)

    view.analysisButton.setChecked(true)
    view.analysisButton.sigCheckedChanged.call(view.analysisButton)
    completeHexViewerAnalysis(&host, view)

    Swag.assert(view.analysisView.isLocallyVisible() and view.analysisView.result.scanned == view.grid.doc.fileSize)
    Swag.assert(view.analysisView.result.entropy > 0 and view.analysisView.histogram.total == view.grid.doc.fileSize)
    Swag.assert(view.analysisView.stringsList.virtualCount == view.analysisView.result.strings.count)
    Swag.assert(view.analysisView.result.strings.count >= 2)

    let first = &view.analysisView.result.strings[0]
    view.analysisView.stringsList.selectLine(0)
    Swag.assert(view.grid.selectionStart() == first.offset and view.grid.selectionLength() == first.length)

    // Re-running analysis derives its range from the live grid selection. It does not replay the
    // stale whole-file range that originally populated the panel.
    let selectedStart  = view.grid.selectionStart()
    let selectedLength = view.grid.selectionLength()
    view.analysisView.analyzeButton.sigPressed.call(cast(*Button) view.analysisView.analyzeButton)
    completeHexViewerAnalysis(&host, view)
    Swag.assert(view.analysisView.selection and view.analysisView.result.range.offset == selectedStart)
    Swag.assert(view.analysisView.result.range.length == selectedLength)
    Swag.assert(!view.analysisView.stringsList.header.flags.has(.Separators))

    window.infoNameLabel.setText("scope-hex-analysis.bin")
    window.infoNameLabel.toolTip = "scope-hex-analysis.bin"
    window.layoutFileInfo()
    window.resize(1_100, 700)
    window.applyLayout()
    host.moveMouse({-1, -1})
    host.settleAnimations(window, 4)
    var image = host.render(window)
    Pixel.Testing.assertImageGolden(&image, "viewer.hex.analysis")

    view.closeAnalysis()
    view.grid.moveCaret(0x80, false)
    view.grid.moveCaret(0x89, true)
    let selectionStart  = view.grid.selectionStart()
    let selectionLength = view.grid.selectionLength()
    view.analysisButton.setChecked(true)
    view.analysisButton.sigCheckedChanged.call(view.analysisButton)
    completeHexViewerAnalysis(&host, view)
    Swag.assert(view.analysisView.selection and view.analysisView.result.range.offset == selectionStart)
    Swag.assert(view.analysisView.result.range.length == selectionLength and view.analysisView.result.scanned == selectionLength)
}

// The document never holds more than one window, wherever the reader is standing.
#test
{
    let fileName = writeStreamedFile(StreamedFileSize)
    defer discard catch File.delete(fileName.toString())
    let allocator = Swag.defaultAllocator()
    let baseline  = allocator.stats()

    var doc: HexDocument
    defer doc.close()
    Swag.assert(doc.open(fileName.toString()))
    Swag.assert(doc.fileSize == StreamedFileSize)

    Swag.assert(doc.ensure(0, 64))
    Swag.assert(doc.byteAt(5) == 5)
    Swag.assert(doc.window.count <= HexWindowSize)

    let last = StreamedFileSize - 1
    Swag.assert(doc.ensure(last - 31, 32))
    Swag.assert(doc.byteAt(last) == cast(u8) (last & 0xFF))
    Swag.assert(doc.window.count <= HexWindowSize)
    Swag.assert(doc.windowStart > 0)
    Swag.assert(!doc.isResident(0))

    // A bounded read reaches anywhere without moving what is on screen.
    let windowStart = doc.windowStart
    let bytes       = doc.read(1000, 4)
    Swag.assert(bytes.count == 4 and bytes[0] == 0xE8 and bytes[3] == 0xEB)
    Swag.assert(doc.windowStart == windowStart)
    Swag.assert(doc.read(StreamedFileSize, 16).isEmpty())

    let resident = allocator.stats()
    Swag.assert(resident.sizeAlloc < baseline.sizeAlloc + 2 * 1024 * 1024)
}

// Walking a file larger than one window keeps the resident bytes bounded, and the end is one key
// away rather than one key away per page.
#test
{
    let fileName = writeStreamedFile(StreamedFileSize)
    defer discard catch File.delete(fileName.toString())

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()

    let view = createTestViewer(&host, fileName.toString(), 900, 560)
    Swag.assert(view.grid.doc.fileSize == StreamedFileSize)
    Swag.assert(view.grid.topRow == 0 and view.grid.caret == 0)
    discard host.render(view)
    Swag.assert(view.grid.doc.window.count <= HexWindowSize)

    host.focus(view.grid)
    host.keyPress(.End, .Control)
    Swag.assert(view.grid.caret == StreamedFileSize - 1)
    Swag.assert(view.grid.topRow == view.grid.maxTopRow())
    discard host.render(view)
    Swag.assert(view.grid.doc.window.count <= HexWindowSize)
    Swag.assert(view.grid.doc.byteAt(view.grid.caret) == cast(u8) ((StreamedFileSize - 1) & 0xFF))

    host.keyPress(.Home, .Control)
    Swag.assert(view.grid.caret == 0 and view.grid.topRow == 0)

    // The scrollbar spans the whole file and stays inside what an f32 counts exactly.
    Swag.assert(view.grid.scroll.scrollSize.y > view.grid.clientRect().height)
    Swag.assert(view.grid.scroll.scrollSize.y <= HexScrollSpan)
}

// The bar is a proportional control: the row it names comes back through the row count, so every
// row stays reachable in a file with more rows than the span has pixels.
#test
{
    let fileName = writeStreamedFile(StreamedFileSize)
    defer discard catch File.delete(fileName.toString())

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()

    let view = createTestViewer(&host, fileName.toString(), 900, 560)
    let grid = view.grid
    let span = grid.scroll.scrollSize.y

    grid.scroll.setScrollPos(0, span)
    Swag.assert(grid.topRow == grid.maxTopRow())

    grid.scroll.setScrollPos(0, 0)
    Swag.assert(grid.topRow == 0)

    grid.setTopRow(grid.maxTopRow() / 2)
    Swag.assert(grid.scroll.scrollPosition().y > 0)
    Swag.assert(grid.scroll.scrollPosition().y < span)
}

// Caret movement, selection, and the row width the window fits.
#test
{
    let fileName = writeStreamedFile(4096)
    defer discard catch File.delete(fileName.toString())

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()

    let view = createTestViewer(&host, fileName.toString(), 900, 560)
    let grid = view.grid
    let wide = grid.bytesPerRow
    Swag.assert(wide >= HexMinBytesPerRow and wide % grid.valueSize() == 0)

    host.focus(grid)
    host.keyPress(.Right)
    host.keyPress(.Down)
    Swag.assert(grid.caret == 1 + wide)
    Swag.assert(!grid.hasSelection() and grid.selectionLength() == 1)

    host.keyPress(.Right, .Shift)
    host.keyPress(.Right, .Shift)
    Swag.assert(grid.hasSelection())
    Swag.assert(grid.selectionStart() == 1 + wide and grid.selectionLength() == 3)

    host.keyPress(.A, .Control)
    Swag.assert(grid.selectionStart() == 0 and grid.selectionLength() == 4096)

    // A narrow window gives up columns rather than the readability of the ones it keeps.
    grid.setBytesPerRow(0, true)
    view.resize(560, 560)
    view.applyLayout()
    grid.refreshLayout()
    Swag.assert(grid.bytesPerRow <= wide)
    Swag.assert(grid.contentWidth() <= grid.clientRect().width or grid.bytesPerRow == HexMinBytesPerRow)

    grid.setBytesPerRow(32, false)
    Swag.assert(grid.bytesPerRow == 32 and !grid.autoFitRow)
}

// A point lands on the byte it names, in either column, and on nothing above the first row.
#test
{
    let fileName = writeStreamedFile(4096)
    defer discard catch File.delete(fileName.toString())

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()

    let view = createTestViewer(&host, fileName.toString(), 900, 560)
    let grid = view.grid
    grid.setBytesPerRow(16, false)

    let row    = 3'u64
    let column = 5'u64
    Swag.assert(grid.offsetAt({grid.hexCellX(column) + 1, grid.rowTop(row) + 2}) == row * 16 + column)
    Swag.assert(grid.offsetAt({grid.textCellX(column) + 1, grid.rowTop(row) + 2}) == row * 16 + column)
    Swag.assert(grid.offsetAt({4, 2}) == Swag.U64.Max)
}

// Byte order is an action-bar option and immediately changes multi-byte decoding.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("viewer_hex_values_%.bin", Guid64.random()).toString())
    defer discard catch File.delete(fileName.toString())
    discard expect File.writeAllBytes(fileName.toString(), [0x78'u8, 0x56'u8, 0x34'u8, 0x12'u8, 0'u8, 0'u8, 0'u8, 0x80'u8, 0x41'u8])

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()

    let view = createTestViewer(&host, fileName.toString(), 900, 560)
    Swag.assert(view.byteOrderCombo.selectedIndex == 0)
    Swag.assert(!view.grid.bigEndian)

    // The combo changes the values drawn by the grid, not only the distance between bytes.
    view.grid.setGrouping(.Unsigned32)
    Swag.assert(view.grid.doc.ensure(0, view.grid.doc.fileSize))
    view.grid.buildRow(0)
    Swag.assert(view.grid.scalarAt(0) == 0x12345678)
    Swag.assert(formatHexScalar(.Unsigned32, view.grid.scalarAt(0)) == "305419896")
    Swag.assert(Utf8.contains(view.grid.rowHexStrong.toSlice(), "305419896"))

    view.byteOrderCombo.setSelectedIndex(1)
    Swag.assert(view.grid.bigEndian)
    view.grid.buildRow(0)
    Swag.assert(Utf8.contains(view.grid.rowHexStrong.toSlice(), "2018915346"))
}

// What leaves through the clipboard is what the reader selected, in the form asked for.
#test
{
    if !Clipboard.isFake() do
        return

    let fileName = writeStreamedFile(4096)
    defer discard catch File.delete(fileName.toString())

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()

    let view = createTestViewer(&host, fileName.toString(), 900, 560)
    let grid = view.grid
    grid.setBytesPerRow(16, false)
    grid.moveCaret(0x41, false)
    grid.moveCaret(0x44, true)

    grid.copySelection(.Bytes)
    Swag.assert(Clipboard.getString() == "41 42 43 44")

    grid.copySelection(.Text)
    Swag.assert(Clipboard.getString() == "ABCD")

    grid.copySelection(.Dump)
    let dump = Clipboard.getString()
    Swag.assert(Utf8.contains(dump.toSlice(), "00000041  41 42 43 44"))
    Swag.assert(Utf8.contains(dump.toSlice(), "ABCD"))

    // Scalar presentation never widens an exact byte selection or its clipboard payload.
    grid.setGrouping(.Unsigned32)
    grid.moveCaret(1, false)
    grid.moveCaret(4, true)
    Swag.assert(grid.selectionStart() == 1 and grid.selectionLength() == 4)
    grid.copySelection(.Bytes)
    Swag.assert(Clipboard.getString() == "01 02 03 04")

    // A selection wider than the clipboard bound is copied up to it, and never materializes more.
    grid.selectAll()
    grid.copySelection(.Text)
    Swag.assert(Clipboard.getString().length == 4096)
    Swag.assert(grid.doc.window.count <= HexWindowSize)
}

// The context menu reaches the same commands the keyboard does, the global row-width selector is
// independent from it, and the go-to box closes without leaving a modal behind.
#test
{
    let fileName = writeStreamedFile(4096)
    defer discard catch File.delete(fileName.toString())

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()

    let view = createTestViewer(&host, fileName.toString(), 900, 560)
    let grid = view.grid

    host.clickPopupMenuItemWhenShown(ActionHex.SelectAll)
    grid.showContextMenu({120, 120})
    host.pump()
    Swag.assert(grid.selectionStart() == 0 and grid.selectionLength() == 4096)

    view.rowCombo.setSelectedIndex(3)
    Swag.assert(grid.bytesPerRow == 32 and !grid.autoFitRow)

    grid.moveCaret(0x123, false)
    host.clickModalButtonWhenShown(Dialog.BtnCancel)
    grid.promptGoToOffset()
    Swag.assert(grid.caret == 0x123)

    // The offset a reader types is read the same way whatever opened the box.
    Swag.assert(grid.goToTypedOffset("0x800"))
    Swag.assert(grid.caret == 0x800)
    Swag.assert(grid.topRow > 0 and grid.topRow < 0x800 / grid.bytesPerRow)
    Swag.assert(grid.goToTypedOffset("50%"))
    Swag.assert(grid.caret == (grid.doc.fileSize - 1) / 2)
    Swag.assert(grid.goToTypedOffset("0d1024"))
    Swag.assert(grid.caret == 1024)
    Swag.assert(grid.goToTypedOffset("-100"))
    Swag.assert(grid.caret == 0x300)
    Swag.assert(!grid.goToTypedOffset("nowhere"))
    Swag.assert(grid.caret == 0x300)

    let defaultFontSize = grid.fontSize
    host.mouseWheel(grid.surfaceRect().center(), 120, .Control)
    Swag.assert(grid.fontSize == defaultFontSize + 1)
    host.focus(grid)
    host.keyPress(.D0, .Control)
    Swag.assert(grid.fontSize == defaultFontSize)
}

// A search hit is revealed at the offset the host found, and stays marked once the caret moves on.
#test
{
    let fileName = writeSampleFile()
    defer discard catch File.delete(fileName.toString())

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()

    let view = createTestViewer(&host, fileName.toString(), 900, 560)
    Swag.assert(view.revealOffset(11, 5))
    Swag.assert(view.grid.matchStart == 11 and view.grid.matchLength == 5)
    Swag.assert(view.grid.selectionStart() == 11 and view.grid.selectionLength() == 5)
    discard host.render(view)
    Swag.assert(view.grid.doc.byteAt(11) == 'h'u8)

    view.grid.moveCaret(0, false)
    Swag.assert(view.grid.matchStart == 11 and view.grid.matchLength == 5)
    Swag.assert(!view.revealOffset(view.grid.doc.fileSize, 5))
}

// Multi-gigabyte geometry is synthetic: the test needs the address domain, not a multi-gigabyte
// fixture. Every operation below stays outside painting, so no byte beyond the real fixture is read.
#test
{
    let fileName = writeSampleFile()
    defer discard catch File.delete(fileName.toString())

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()

    let view = createTestViewer(&host, fileName.toString(), 900, 560)
    let grid = view.grid
    grid.doc.fileSize = 0x1_0000_1234
    grid.refreshLayout()

    Swag.assert(grid.offsetDigits == 16)
    Swag.assert(grid.doc.fileSize > Swag.U32.Max)
    Swag.assert(grid.rowCount() == (grid.doc.fileSize + grid.bytesPerRow - 1) / grid.bytesPerRow)
    Swag.assert(grid.scroll.scrollSize.y <= HexScrollSpan)
    host.focus(grid)
    host.keyPress(.End, .Control)
    Swag.assert(grid.caret == 0x1_0000_1233 and grid.topRow == grid.maxTopRow())

    let dump = formatHexDump([0xAB'u8], 0x1_0000_0000, 16, grid.offsetDigits)
    Swag.assert(Utf8.contains(dump.toSlice(), "0000000100000000"))
}

// A stream that returns fewer bytes than the size snapshot stops the document with one stable
// explanation instead of exposing stale or zero-filled bytes as file content.
#test
{
    let fileName = writeSampleFile()
    defer discard catch File.delete(fileName.toString())

    var doc: HexDocument
    defer doc.close()
    Swag.assert(doc.open(fileName.toString()))
    doc.fileSize += 4096
    Swag.assert(!doc.ensure(0, doc.fileSize))
    Swag.assert(doc.readFailed and doc.window.isEmpty())
    Swag.assert(doc.failureReason == "file ends before its reported size")
    Swag.assert(!doc.ensure(0, 1) and doc.read(0, 1).isEmpty())
}

// A drag beyond the viewport autoscrolls on a timer, and losing focus ends it with no capture or
// timer left to receive a later gesture that belongs to another control.
#test
{
    let fileName = writeStreamedFile(4096)
    defer discard catch File.delete(fileName.toString())

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()

    let view = createTestViewer(&host, fileName.toString(), 900, 560)
    let grid = view.grid
    grid.setBytesPerRow(16, false)
    let point = grid.localToSurface(Math.Point{grid.hexCellX(2) + 1, grid.rowTop(0) + 2})
    host.mouseDown(point)
    Swag.assert(grid.selecting and grid.mouseCapture() == grid)

    let outside = grid.localToSurface(Math.Point{grid.textCellX(4), grid.clientRect().bottom() + 20})
    host.moveMouse(outside)
    Swag.assert(grid.selectionTimer != null and grid.topRow > 0)
    let firstTop = grid.topRow
    host.fireTimer(grid.selectionTimer)
    Swag.assert(grid.topRow > firstTop and grid.selectionLength() > 1)

    let other = Wnd.create'Wnd(&host.root, "hex.capture.other", {0, 0, 40, 20})
    other.focusPolicy = .Tab
    other.setFocus()
    Swag.assert(!grid.selecting and grid.selectionTimer == null and grid.mouseCapture() == null)
}

// Snapped fixed-width metrics keep the hit geometry and fitted rows coherent at fractional DPI.
#test
{
    let fileName = writeStreamedFile(4096)
    defer discard catch File.delete(fileName.toString())

    var host: Testing.HeadlessHost
    host.setup(900, 600, dpiScale: 1.5)
    defer host.shutdown()

    let view = createTestViewer(&host, fileName.toString(), 900, 560)
    let grid = view.grid
    grid.setBytesPerRow(16, false)
    let row    = 2'u64
    let column = 13'u64
    Swag.assert(grid.deviceScale() == 1.5)
    Swag.assert(grid.offsetAt({grid.textCellX(column) + 1, grid.rowTop(row) + 2}) == row * 16 + column)
    Swag.assert(grid.contentWidth() <= grid.clientRect().width)
    discard host.render(view)
}

// Every painted and interactive hexadecimal string follows the live application language.
#test
{
    let fileName = Gui.Testing.tempFilePath("scope-hex-empty-", ".bin")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, cast(const [..] u8) "")

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()
    defer discard catch host.app.setLanguage(ReferenceLanguage)

    let view = createTestViewer(&host, fileName, 900, 560)
    Swag.assert(hexStrings().ui_TextColumn == "text" and hexStrings().ui_Empty == "This file is empty.")
    Swag.assert(view.widthCombo.selectedItem()!.name.raw == "8-bit" and view.byteOrderCombo.selectedItem()!.name.raw == "Little endian")
    discard host.render(view)

    expect host.app.setLanguage("fr")
    host.notify(.LanguageChanged)
    Swag.assert(hexStrings().ui_TextColumn == "texte")
    Swag.assert(hexStrings().ui_Empty == "Ce fichier est vide.")
    Swag.assert(view.widthCombo.selectedItem()!.name.raw == "8 bits" and view.byteOrderCombo.selectedItem()!.name.raw == "Little endian")
    Swag.assert(view.widthCombo.toolTip == "Largeur des valeurs")
    Swag.assert(view.rowCombo.selectedItem()!.name.raw == "Auto" and view.rowCombo.toolTip == "Octets par ligne")
    Swag.assert(view.analysisButton.toolTip == "Analyser la sélection, ou le fichier entier lorsqu’un seul octet est sélectionné")
    Swag.assert(view.analysisView.analyzeButton.toolTip == "Analyser la sélection actuelle, ou le fichier entier lorsqu’un seul octet est sélectionné")
    Swag.assert(view.analysisView.titleLabel.text() == "Analyse" and view.analysisView.stringsList.header.itemAt(1).name.raw == "Encodage")
    discard host.render(view)
    Testing.assertContentFits(view.commands)
}

// The clipboard contract names and enforces its exact bound before a large selection is copied.
#test
{
    if !Clipboard.isFake() do
        return

    let fileName = writeStreamedFile(HexCopyLimit + 37)
    defer discard catch File.delete(fileName.toString())

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()

    let view = createTestViewer(&host, fileName.toString(), 900, 560)
    let grid = view.grid
    grid.selectAll()

    let state = grid.sendComputeCommandStateEvent(ActionHex.CopyText)
    Swag.assert(state.name == Format.toString(hexStrings().ui_CopyTextMax, StrConv.toDisplaySize(HexCopyLimit)))
    grid.copySelection(.Text)
    Swag.assert(Clipboard.getString().length == HexCopyLimit)
    Swag.assert(grid.doc.window.count <= HexWindowSize)
}

// The compact typed command group keeps every rendering option visible without a duplicated menu.
#test
{
    let fileName = writeSampleFile()
    defer discard catch File.delete(fileName.toString())

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()

    let view = createTestViewer(&host, fileName.toString(), 900, 560)
    Swag.assert(view.commands.position.width == 436)
    Swag.assert(view.byteOrderCombo.parent == view.commands and view.byteOrderCombo.selectedIndex == 0)
    Swag.assert(view.rowCombo.parent == view.commands and view.rowCombo.selectedIndex == 0)
    Swag.assert(view.byteOrderCombo.position.right() <= view.rowCombo.position.x)
    Swag.assert(view.rowCombo.position.right() <= view.commands.clientRect().right())
    Testing.assertContentFits(view)

    // At the band a window of the host's minimum size leaves, the bytes still hold the clear
    // majority of the surface and the grid still gives whole groups.
    view.resize(640, 320)
    view.applyLayout()
    view.grid.refreshLayout()
    Swag.assert(view.grid.clientRect().width > 640 * 0.6)
    Swag.assert(view.grid.bytesPerRow >= HexMinBytesPerRow)
    Swag.assert(view.grid.contentWidth() <= view.grid.clientRect().width)
    discard host.render(view)
}

// Photographed on the palette the application ships on: the header, faint zero bytes, the caret in
// both columns, and a selection.
#test
{
    let fileName = writePreviewFile()
    defer discard catch File.delete(fileName.toString())

    var host: Testing.HeadlessHost
    host.setup(860, 460)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)

    let view = createTestViewer(&host, fileName.toString(), 860, 460)
    view.grid.setBytesPerRow(16, false)
    view.grid.moveCaret(0x80, false)
    view.grid.moveCaret(0x89, true)
    var searchHits: Array'Viewer.SearchMatch
    searchHits.add({offset: 0x15, length: 4})
    searchHits.add({offset: 0x78, length: 6})
    view.grid.setSearchMatches(&searchHits)
    discard view.grid.revealRange(0x78, 6)
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)

    var image = host.render(view)
    Pixel.Testing.assertImageGolden(&image, "viewer.hex.document")
}
