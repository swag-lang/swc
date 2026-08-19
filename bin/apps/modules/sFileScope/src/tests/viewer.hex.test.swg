#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

// Payload every streaming test reads. It is larger than one resident window, so a test that walks
// to its end proves the window moved instead of proving the file was small.
const StreamedFileSize = HexWindowSize * 3 + 1234'u64

// Writes readable content at exact offsets. A checked-in fixture would carry whatever line endings
// the checkout gave it, which moves every offset an assertion names.
func writeSampleFile()->String
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("viewer_hex_sample_%.bin", Guid64.random()).toString())
    let content       = "sFileScope hex fixture\nASCII text and symbols: 00 FF 42.\n"
    discard expect File.writeAllBytes(fileName.toString(), @mkslice(cast(const [*] u8) @dataof(content), @countof(content)))
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
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), "viewer.hex.preview.bin")

    var payload: Array'u8
    let header = "sFileScope hex preview"
    for index in @countof(header) do
        payload.add(header[index])
    for 42 do
        payload.add(0)
    for index in 64 do
        payload.add(cast(u8) (0xC0 + index % 0x40))
    let text = "name=value; the text column stays readable"
    for index in @countof(text) do
        payload.add(text[index])
    for index in 128 do
        payload.add(index % 3 == 0 ? 0'u8 : cast(u8) ((index * 7) & 0xFF))

    discard expect File.writeAllBytes(fileName.toString(), payload.toSlice())
    return fileName
}

func createTestViewer(host: *Testing.HeadlessHost, fileName: string, width, height: f32)->*HexViewer
{
    let commands = Wnd.create'Wnd(&host.root, {0, 0, 388, 36})
    let view     = HexViewer.create(&host.root, commands, fileName)
    view.dockStyle = .Center
    view.resize(width, height)
    view.applyLayout()
    view.grid.refreshLayout()
    return view
}

// A file-open error crosses the viewer boundary instead of appearing as an empty byte grid.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 420)
    defer host.shutdown()

    let request = ViewerRequest{&host.root, &host.root, "this-file-does-not-exist.bin"}
    var result: ViewerResult
    createHexViewer(&request, &result)
    @assert(result.view == null and result.commands == null)
    @assert(!result.failureReason.isEmpty())
}

// Typed grouping moves, selects, spaces, and decodes one complete scalar at a time.
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
    @assert(grid.valueSize() == 4 and grid.displayGroupSize() == 4)
    @assert(grid.selectionStart() == 0 and grid.selectionLength() == 4)

    host.focus(grid)
    host.keyPress(.Right)
    @assert(grid.caret == 4 and grid.selectionStart() == 4 and grid.selectionLength() == 4)

    grid.setGrouping(.Float64)
    @assert(grid.valueSize() == 8 and grid.selectionStart() == 0 and grid.selectionLength() == 8)
    grid.setGrouping(.Bytes)
    @assert(grid.selectionLength() == 1 and !grid.hasSelection())

    // Width and spelling are independent controls. Float appears only where the selected width
    // has a corresponding representation.
    view.widthCombo.setSelectedIndex(1)
    view.formatCombo.setSelectedIndex(1)
    @assert(grid.grouping == .Unsigned16)
    view.widthCombo.setSelectedIndex(3)
    view.formatCombo.setSelectedIndex(3)
    @assert(grid.grouping == .Float64 and grid.valueSize() == 8)
    view.widthCombo.setSelectedIndex(0)
    @assert(view.formatCombo.items.count == 3 and grid.grouping == .Bytes)
}

// The dump copy is the view in text form: the offset, the grouped bytes, and the text column.
#test
{
    let text = formatHexDump([0'u8, 1'u8, 0x20'u8, 0x41'u8, 0xFF'u8], 0x20, 16, 16)
    @assert(Utf8.contains(text.toSlice(), "0000000000000020"))
    @assert(Utf8.contains(text.toSlice(), "00 01 20 41 FF"))
    @assert(Utf8.contains(text.toSlice(), ".. A."))

    let narrow = formatHexDump([0xAA'u8, 0xBB'u8, 0xCC'u8], 0, 2, 8)
    @assert(Utf8.contains(narrow.toSlice(), "00000000  AA BB"))
    @assert(Utf8.contains(narrow.toSlice(), "00000002  CC"))
}

// An offset is read in hexadecimal, and a signed one moves relative to the caret.
#test
{
    @assert(parseHexOffset("1F", 0, 1000) == 0x1F)
    @assert(parseHexOffset("  0x1f  ", 0, 1000) == 0x1F)
    @assert(parseHexOffset("00 1F", 0, 1000) == 0x1F)
    @assert(parseHexOffset("+10", 0x20, 1000) == 0x30)
    @assert(parseHexOffset("-10", 0x20, 1000) == 0x10)
    @assert(parseHexOffset("-1000", 0x20, 1000) == 0)
    @assert(parseHexOffset("FFFFFF", 0, 1000) == 999)
    @assert(parseHexOffset("zz", 0, 1000) == Swag.U64.Max)
    @assert(parseHexOffset("", 0, 1000) == Swag.U64.Max)
    @assert(parseHexOffset("10", 0, 0) == Swag.U64.Max)
}

// The document never holds more than one window, wherever the reader is standing.
#test
{
    let fileName = writeStreamedFile(StreamedFileSize)
    defer discard catch File.delete(fileName.toString())

    var doc: HexDocument
    defer doc.close()
    @assert(doc.open(fileName.toString()))
    @assert(doc.fileSize == StreamedFileSize)

    @assert(doc.ensure(0, 64))
    @assert(doc.byteAt(5) == 5)
    @assert(doc.window.count <= HexWindowSize)

    let last = StreamedFileSize - 1
    @assert(doc.ensure(last - 31, 32))
    @assert(doc.byteAt(last) == cast(u8) (last & 0xFF))
    @assert(doc.window.count <= HexWindowSize)
    @assert(doc.windowStart > 0)
    @assert(!doc.isResident(0))

    // A bounded read reaches anywhere without moving what is on screen.
    let windowStart = doc.windowStart
    let bytes       = doc.read(1000, 4)
    @assert(bytes.count == 4 and bytes[0] == 0xE8 and bytes[3] == 0xEB)
    @assert(doc.windowStart == windowStart)
    @assert(doc.read(StreamedFileSize, 16).isEmpty())
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
    @assert(view.grid.doc.fileSize == StreamedFileSize)
    @assert(view.grid.topRow == 0 and view.grid.caret == 0)
    discard host.render(view)
    @assert(view.grid.doc.window.count <= HexWindowSize)

    host.focus(view.grid)
    host.keyPress(.End, .Control)
    @assert(view.grid.caret == StreamedFileSize - 1)
    @assert(view.grid.topRow == view.grid.maxTopRow())
    discard host.render(view)
    @assert(view.grid.doc.window.count <= HexWindowSize)
    @assert(view.grid.doc.byteAt(view.grid.caret) == cast(u8) ((StreamedFileSize - 1) & 0xFF))

    host.keyPress(.Home, .Control)
    @assert(view.grid.caret == 0 and view.grid.topRow == 0)

    // The scrollbar spans the whole file and stays inside what an f32 counts exactly.
    @assert(view.grid.scroll.scrollSize.y > view.grid.clientRect().height)
    @assert(view.grid.scroll.scrollSize.y <= HexScrollSpan)
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
    @assert(grid.topRow == grid.maxTopRow())

    grid.scroll.setScrollPos(0, 0)
    @assert(grid.topRow == 0)

    grid.setTopRow(grid.maxTopRow() / 2)
    @assert(grid.scroll.scrollPosition().y > 0)
    @assert(grid.scroll.scrollPosition().y < span)
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
    @assert(wide >= HexMinBytesPerRow and wide % grid.valueSize() == 0)

    host.focus(grid)
    host.keyPress(.Right)
    host.keyPress(.Down)
    @assert(grid.caret == 1 + wide)
    @assert(!grid.hasSelection() and grid.selectionLength() == 1)

    host.keyPress(.Right, .Shift)
    host.keyPress(.Right, .Shift)
    @assert(grid.hasSelection())
    @assert(grid.selectionStart() == 1 + wide and grid.selectionLength() == 3)

    host.keyPress(.A, .Control)
    @assert(grid.selectionStart() == 0 and grid.selectionLength() == 4096)

    // A narrow window gives up columns rather than the readability of the ones it keeps.
    grid.setBytesPerRow(0, true)
    view.resize(560, 560)
    view.applyLayout()
    grid.refreshLayout()
    @assert(grid.bytesPerRow <= wide)
    @assert(grid.contentWidth() <= grid.clientRect().width or grid.bytesPerRow == HexMinBytesPerRow)

    grid.setBytesPerRow(32, false)
    @assert(grid.bytesPerRow == 32 and !grid.autoFitRow)
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
    @assert(grid.offsetAt({grid.hexCellX(column) + 1, grid.rowTop(row) + 2}) == row * 16 + column)
    @assert(grid.offsetAt({grid.textCellX(column) + 1, grid.rowTop(row) + 2}) == row * 16 + column)
    @assert(grid.offsetAt({4, 2}) == Swag.U64.Max)
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
    @assert(view.byteOrder.isChecked())
    @assert(!view.grid.bigEndian)

    // The combo changes the values drawn by the grid, not only the distance between bytes.
    view.grid.setGrouping(.Unsigned32)
    @assert(view.grid.doc.ensure(0, view.grid.doc.fileSize))
    view.grid.buildRow(0)
    @assert(view.grid.scalarAt(0) == 0x12345678)
    @assert(formatHexScalar(.Unsigned32, view.grid.scalarAt(0)) == "305419896")
    @assert(Utf8.contains(view.grid.rowHexStrong.toSlice(), "305419896"))

    view.byteOrder.setState(.Unchecked)
    view.grid.setBigEndian(!view.byteOrder.isChecked())
    @assert(view.grid.bigEndian)
    view.grid.buildRow(0)
    @assert(Utf8.contains(view.grid.rowHexStrong.toSlice(), "2018915346"))
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
    @assert(Clipboard.getString() == "41 42 43 44")

    grid.copySelection(.Text)
    @assert(Clipboard.getString() == "ABCD")

    grid.copySelection(.Dump)
    let dump = Clipboard.getString()
    @assert(Utf8.contains(dump.toSlice(), "00000041  41 42 43 44"))
    @assert(Utf8.contains(dump.toSlice(), "ABCD"))

    // A selection wider than the clipboard bound is copied up to it, and never materializes more.
    grid.selectAll()
    grid.copySelection(.Text)
    @assert(Clipboard.getString().length == 4096)
    @assert(grid.doc.window.count <= HexWindowSize)
}

// The context menu reaches the same commands the keyboard does, and the go-to box opens and closes
// from inside the viewer without leaving a modal behind.
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
    @assert(grid.selectionStart() == 0 and grid.selectionLength() == 4096)

    host.openPopupSubMenuWhenShown("Bytes per row")
    host.thenClickPopupMenuItem(ActionHex.Row32)
    grid.showContextMenu({120, 120})
    host.pump()
    @assert(grid.bytesPerRow == 32 and !grid.autoFitRow)

    grid.moveCaret(0x123, false)
    host.clickModalButtonWhenShown(Dialog.BtnCancel)
    grid.promptGoToOffset()
    @assert(grid.caret == 0x123)

    // The offset a reader types is read the same way whatever opened the box.
    @assert(grid.goToTypedOffset("0x800"))
    @assert(grid.caret == 0x800)
    @assert(grid.topRow > 0 and grid.topRow < 0x800 / grid.bytesPerRow)
    @assert(grid.goToTypedOffset("-100"))
    @assert(grid.caret == 0x700)
    @assert(!grid.goToTypedOffset("nowhere"))
    @assert(grid.caret == 0x700)
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
    @assert(view.revealOffset(11, "hex"))
    @assert(view.grid.matchStart == 11 and view.grid.matchLength == 3)
    @assert(view.grid.selectionStart() == 11 and view.grid.selectionLength() == 3)
    discard host.render(view)
    @assert(view.grid.doc.byteAt(11) == 'h'u8)

    view.grid.moveCaret(0, false)
    @assert(view.grid.matchStart == 11 and view.grid.matchLength == 3)
    @assert(!view.revealOffset(view.grid.doc.fileSize, "hex"))
}

// The typed command group stays bounded and keeps byte order beside the representation controls.
#test
{
    let fileName = writeSampleFile()
    defer discard catch File.delete(fileName.toString())

    var host: Testing.HeadlessHost
    host.setup(900, 600)
    defer host.shutdown()

    let view = createTestViewer(&host, fileName.toString(), 900, 560)
    @assert(view.commands.position.width <= 400)
    @assert(view.byteOrder.parent == view.commands and view.byteOrder.isChecked())
    @assert(view.details == "hex and text · streamed")
    Testing.assertContentFits(view)

    // At the band a window of the host's minimum size leaves, the bytes still hold the clear
    // majority of the surface and the grid still gives whole groups.
    view.resize(640, 320)
    view.applyLayout()
    view.grid.refreshLayout()
    @assert(view.grid.clientRect().width > 640 * 0.6)
    @assert(view.grid.bytesPerRow >= HexMinBytesPerRow)
    @assert(view.grid.contentWidth() <= view.grid.clientRect().width)
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
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)

    var image = host.render(view)
    Pixel.Testing.assertImageGolden(&image, "viewer.hex.document")
}
