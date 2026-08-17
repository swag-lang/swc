#global internal

using Core, Pixel, Gui

// Air along the left and right edges of the grid, and the gap between two columns.
const HexViewInset = 12.0
const HexColumnGap = 14.0

// Bytes one group of the hexadecimal column holds. The extra gap between groups is what lets an
// eye count columns without reading the header.
const HexDefaultGroupSize = 8'u64

// Rows a wheel notch moves, and the range a row is allowed to hold. Automatic fitting aligns the
// chosen count to the active scalar, so a row can use the last available columns without ending in
// the middle of a value.
const HexWheelRows      = 3'u64
const HexMinBytesPerRow = 8'u64
const HexMaxBytesPerRow = 64'u64

// Largest pixel span the vertical scrollbar is given.
//
// A scroll position is an f32, which counts whole numbers exactly only up to 2^24. Mapping the
// bar through a fixed span and converting back through the row count keeps every row reachable
// whatever the file size, instead of losing rows to the precision of a pixel offset.
const HexScrollSpan = 4_194_304.0

// A clipboard operation is the one place bytes are materialized, so it is the one place a bound is
// needed: the grid itself never holds more than one window.
const HexCopyLimit = 1024 * 1024'u64

// What a copy of the current selection produces.
enum HexCopyForm
{
    Bytes     // Hexadecimal byte values separated by spaces.
    Text      // Printable bytes as characters, every other byte as a dot.
    Dump      // The offset, hexadecimal and text columns as the grid itself shows them.
}

// Selects the scalar each visual byte group represents.
enum HexGrouping
{
    Bytes          // Individual hexadecimal bytes, with a larger visual break every eight.
    Unsigned8      // Unsigned 8-bit integers.
    Signed8        // Signed 8-bit integers.
    Hex16          // 16-bit integers written in hexadecimal.
    Unsigned16     // Unsigned 16-bit integers.
    Signed16       // Signed 16-bit integers.
    Hex32          // 32-bit integers written in hexadecimal.
    Unsigned32     // Unsigned 32-bit integers.
    Signed32       // Signed 32-bit integers.
    Float32        // IEEE 754 32-bit floating-point values.
    Hex64          // 64-bit integers written in hexadecimal.
    Unsigned64     // Unsigned 64-bit integers.
    Signed64       // Signed 64-bit integers.
    Float64        // IEEE 754 64-bit floating-point values.
}

func hexGroupingSize(grouping: HexGrouping)->u64
{
    switch grouping
    {
    case .Hex16, .Unsigned16, .Signed16:           return 2
    case .Hex32, .Unsigned32, .Signed32, .Float32: return 4
    case .Hex64, .Unsigned64, .Signed64, .Float64: return 8
    default: return 1
    }
}

// Commands shared by the context menu and keyboard.
struct ActionHex {}

impl ActionHex
{
    newCmdId("CopyBytes")
    newCmdId("CopyText")
    newCmdId("CopyDump")
    newCmdId("SelectAll")
    newCmdId("GoTo")
    newCmdId("RowWidth")
    newCmdId("RowAuto")
    newCmdId("Row8")
    newCmdId("Row16")
    newCmdId("Row32")
    newCmdId("Row64")
}

// Width reserved for one rendered scalar, in fixed-width characters.
func hexGroupingChars(grouping: HexGrouping)->u64
{
    switch grouping
    {
    case .Unsigned8:  return 3
    case .Signed8:    return 4
    case .Hex16:      return 6
    case .Unsigned16: return 5
    case .Hex32:      return 10
    case .Unsigned32: return 10
    case .Hex64:      return 18
    case .Unsigned64: return 20
    case .Signed16:   return 6
    case .Signed32:   return 11
    case .Signed64:   return 20
    case .Float32:    return 15
    case .Float64:    return 24
    default:          return 2
    }
}

// Reinterprets an unsigned scalar as its signed type of the same byte width.
func hexSignedScalar(raw: u64, size: u64)->s64
{
    let bits = size * 8
    if bits >= 64 do
        return cast #bit (s64) raw
    let sign = 1'u64 << (bits - 1)
    if raw & sign do
        return cast #bit (s64) (raw | ~((1'u64 << bits) - 1))
    return cast(s64) raw
}

// Formats one complete scalar in the spelling selected by the value combo.
func formatHexScalar(grouping: HexGrouping, raw: u64)->String
{
    switch grouping
    {
    case .Signed8, .Signed16, .Signed32, .Signed64: return Format.toString("%", hexSignedScalar(raw, hexGroupingSize(grouping)))
    case .Bytes:   return Format.toString("%{X02}", raw)
    case .Hex16:   return Format.toString("0x%{X04}", raw)
    case .Hex32:   return Format.toString("0x%{X08}", raw)
    case .Hex64:   return Format.toString("0x%{X016}", raw)
    case .Float32: return Format.toString("%{g9}", cast #bit (f32) (cast(u32) raw))
    case .Float64: return Format.toString("%{g15}", cast #bit (f64) raw)
    default:       return Format.toString("%", raw)
    }
}

// Appends `value` as `digits` uppercase hexadecimal characters.
func appendHexDigits(buffer: *Array'u8, value: u64, digits: u64)
{
    for index in digits
    {
        let shift  = (digits - 1 - index) * 4
        let nibble = cast(u8) ((value >> shift) & 0xF)
        buffer.add(nibble < 10 ? '0'u8 + nibble : 'A'u8 + nibble - 10)
    }
}

// Returns whether `value` is a byte the text column can show as itself.
func isHexPrintable(value: u8)->bool
{
    return value >= 32 and value < 127
}

// Formats `bytes` as the offset, hexadecimal and text columns the grid draws.
//
// This is what a dump copy produces, so what leaves the viewer through the clipboard is what the
// reader was looking at, at whatever row width the view is currently using.
func formatHexDump(bytes: const [..] u8, baseOffset: u64, bytesPerRow: u64, offsetDigits: u64, groupSize = HexDefaultGroupSize)->String
{
    var result: retval
    if !bytesPerRow do
        return result
    result.reserve(@countof(bytes) * 5)

    var line: Array'u8
    var row = 0'u64
    while row < @countof(bytes)
    {
        line.clear()
        appendHexDigits(&line, baseOffset + row, offsetDigits)
        line.add(' 'u8)
        line.add(' 'u8)

        for column in bytesPerRow
        {
            let index = row + column
            if index < @countof(bytes) do
                appendHexDigits(&line, bytes[index], 2)
            else
            {
                line.add(' 'u8)
                line.add(' 'u8)
            }

            line.add(' 'u8)
            if column % groupSize == groupSize - 1 and column != bytesPerRow - 1 do
                line.add(' 'u8)
        }

        line.add(' 'u8)
        for column in bytesPerRow
        {
            let index = row + column
            if index >= @countof(bytes) do
                break
            let value = bytes[index]
            line.add(isHexPrintable(value) ? value : '.'u8)
        }

        result += @mkstring(line.buffer!, line.count)
        result += "\n"
        row    += bytesPerRow
    }

    return result
}

// Reads an offset typed by a reader, and returns `Swag.U64.Max` when the text names none.
//
// Offsets are hexadecimal because everything else in this view is. A leading sign moves relative
// to `caret` instead, which is how a reader follows a structure field by field.
func parseHexOffset(text: string, caret, fileSize: u64)->u64
{
    var index = 0'u64
    let count = @countof(text)
    while index < count and (text[index] == ' 'u8 or text[index] == '\t'u8) do
        index += 1

    var relative = 0's32
    if index < count and (text[index] == '+'u8 or text[index] == '-'u8)
    {
        relative = text[index] == '+'u8 ? 1 : -1
        index    += 1
    }

    if index + 1 < count and text[index] == '0'u8 and (text[index + 1] == 'x'u8 or text[index + 1] == 'X'u8) do
        index += 2

    var value  = 0'u64
    var digits = 0'u64
    while index < count
    {
        let c      = text[index]
        var nibble = 16'u8
        if c >= '0'u8 and c <= '9'u8 do
            nibble = c - '0'u8
        elif c >= 'a'u8 and c <= 'f'u8 do
            nibble = c - 'a'u8 + 10
        elif c >= 'A'u8 and c <= 'F'u8 do
            nibble = c - 'A'u8 + 10
        elif c == ' 'u8 or c == '_'u8
        {
            index += 1
            continue
        }

        if nibble == 16 do
            return Swag.U64.Max

        // A value wider than the address space is a typing accident, not an offset.
        if value > (Swag.U64.Max - nibble) / 16 do
            return Swag.U64.Max
        value  = value * 16 + nibble
        digits += 1
        index  += 1
    }

    if !digits or !fileSize do
        return Swag.U64.Max

    var target = value
    if relative > 0 do
        target = caret + Math.min(value, Swag.U64.Max - caret)
    elif relative < 0 do
        target = value >= caret ? 0 : caret - value
    return Math.min(target, fileSize - 1)
}

// Hexadecimal grid the file is read in.
//
// The view holds one screen of bytes and two offsets — where the caret is, and where a selection
// started. Every row position is computed from the caret and the file size rather than stored, so
// reaching the end of a ten-gigabyte file costs what reaching the end of a small one costs.
struct HexGridView
{
    using wnd: Wnd

    #[Swag.Late]
    scroll: *ScrollWnd

    doc: HexDocument

    sigCaretChanged: SigArray'func||(*HexGridView)     // Emitted after the caret or the selection moves.

    topRow: u64     // First row the viewport shows.
    caret:  u64     // Byte the caret stands on.
    anchor: u64     // Byte the current selection started from.

    // Range the host's search last revealed. It outlives the selection so the hit stays visible
    // once the reader has moved the caret away from it.
    matchStart:  u64
    matchLength: u64

    bytesPerRow  = 16'u64
    offsetDigits = 8'u64
    autoFitRow   = true
    grouping     = HexGrouping.Bytes
    bigEndian: bool

    selecting: bool     // Whether a drag is currently extending the selection.
    layouting: bool     // Guards the resize a scrollbar appearing re-enters.
    syncing:   bool     // Guards the position signal our own scrollbar update raises.

    charWidth: f32
    rowHeight: f32

    // Row text is rebuilt in place every frame. Bytes that carry a value and bytes that do not are
    // drawn in two passes over the same columns, so one row costs a handful of draws instead of
    // one per byte, and the fixed-width font keeps both passes in their columns.
    rowOffsetText: Array'u8
    rowHexStrong:  Array'u8
    rowHexFaint:   Array'u8
    rowTextStrong: Array'u8
    rowTextFaint:  Array'u8
    caretText:     Array'u8
    headerText:    Array'u8
}

impl HexGridView
{
    mtd lastOffset()->u64 => .doc.fileSize ? .doc.fileSize - 1 : 0

    mtd rowCount()->u64
    {
        if !.doc.fileSize or !.bytesPerRow do
            return 1
        return (.doc.fileSize + .bytesPerRow - 1) / .bytesPerRow
    }

    mtd headerHeight()->f32 => .rowHeight + 8

    mtd visibleRows()->u64
    {
        let height = .clientRect().height - .headerHeight()
        if height <= 0 or .rowHeight <= 0 do
            return 1
        return Math.max(cast(u64) Math.floor(height / .rowHeight), 1)
    }

    mtd maxTopRow()->u64
    {
        let rows    = .rowCount()
        let visible = .visibleRows()
        return rows > visible ? rows - visible : 0
    }

    mtd gutterWidth()->f32 => cast(f32) .offsetDigits * .charWidth + HexColumnGap

    mtd valueSize()->u64 => hexGroupingSize(.grouping)

    mtd displayGroupSize()->u64 => .grouping == .Bytes ? HexDefaultGroupSize : .valueSize()

    mtd valueCellChars()->u64 => hexGroupingChars(.grouping)

    mtd groupStart(offset: u64)->u64 => offset / .valueSize() * .valueSize()

    mtd groupEnd(offset: u64)->u64 => Math.min(.groupStart(offset) + .valueSize() - 1, .lastOffset())

    mtd hexCellX(column: u64)->f32
    {
        if .grouping == .Bytes do
            return HexViewInset + .gutterWidth() + cast(f32) (column * 3 + column / HexDefaultGroupSize) * .charWidth
        return HexViewInset + .gutterWidth() + cast(f32) (column / .valueSize() * (.valueCellChars() + 1)) * .charWidth
    }

    mtd hexColumnWidth(bytesPerRow: u64)->f32
    {
        if .grouping == .Bytes
        {
            let last = bytesPerRow ? bytesPerRow - 1 : 0
            return cast(f32) (last * 3 + last / HexDefaultGroupSize + 2) * .charWidth
        }

        let values = bytesPerRow ? (bytesPerRow + .valueSize() - 1) / .valueSize() : 0
        return values ? cast(f32) (values * (.valueCellChars() + 1) - 1) * .charWidth : 0
    }

    mtd textColumnLeft()->f32 => HexViewInset + .gutterWidth() + .hexColumnWidth(.bytesPerRow) + HexColumnGap

    mtd textCellX(column: u64)->f32 => .textColumnLeft() + cast(f32) column * .charWidth

    mtd contentWidthFor(bytesPerRow: u64)->f32 => HexViewInset + .gutterWidth() + .hexColumnWidth(bytesPerRow) + HexColumnGap + cast(f32) bytesPerRow * .charWidth + HexViewInset

    mtd contentWidth()->f32 => .contentWidthFor(.bytesPerRow)

    // Reads one scalar from the resident document window in the selected byte order.
    mtd scalarAt(offset: u64)->u64
    {
        let size = .valueSize()
        var raw  = 0'u64
        for index in size
        {
            let position = .bigEndian ? index : size - 1 - index
            raw = (raw << 8) | cast(u64) .doc.byteAt(offset + position)
        }

        return raw
    }

    // Returns the top of `row` in view coordinates, taking the difference in signed arithmetic
    // because a row above the viewport is a legitimate question with an unsigned answer of 2^64.
    mtd rowTop(row: u64)->f32 => .headerHeight() + cast(f32) (cast(s64) row - cast(s64) .topRow) * .rowHeight

    mtd selectionStart()->u64 => Math.min(.groupStart(.caret), .groupStart(.anchor))

    mtd selectionEnd()->u64 => .groupEnd(Math.max(.caret, .anchor))

    mtd selectionLength()->u64 => .doc.fileSize ? .selectionEnd() - .selectionStart() + 1 : 0

    mtd hasSelection()->bool => .caret != .anchor or .valueSize() > 1

    // Returns the widest row that still fits, in whole groups.
    //
    // Auto-fitting is what makes the view a window on the file rather than a fixed report: a wide
    // window shows more of every structure, and a narrow one keeps every column readable.
    mtd fitBytesPerRow()->u64
    {
        let available = .clientRect().width
        if available <= 0 or .charWidth <= 0 do
            return HexMinBytesPerRow

        let unit      = .valueSize()
        var candidate = HexMaxBytesPerRow / unit * unit
        while candidate > HexMinBytesPerRow
        {
            if .contentWidthFor(candidate) <= available do
                return candidate
            candidate -= unit
        }

        return Math.max(HexMinBytesPerRow / unit * unit, unit)
    }

    mtd computeMetrics()
    {
        let family   = .font()
        let resolved = family.regular
        if !resolved do
            return

        // The advance a glyph is *drawn* with is snapped to the device pixel grid, and every column
        // here is placed by multiplying that advance. Measuring the unsnapped one instead drifts a
        // fraction of a pixel per column, which by the last column of a row is a whole cell: the
        // caret lands beside its byte and the text column starts inside the hexadecimal one.
        let font = resolved!
        .charWidth    = Math.max(Painter.measureStringSnapped("0", font, deviceScale: .deviceScale()), 1)
        .rowHeight    = Math.max(Math.ceil(font.height), 1)
        .offsetDigits = .doc.fileSize > 0xFFFF_FFFF ? 16 : 8
    }

    // Recomputes everything the window size decides, and republishes the scrollbar.
    mtd refreshLayout()
    {
        if .layouting do
            return
        .layouting = true
        defer .layouting = false

        .computeMetrics()
        if .autoFitRow do
            .bytesPerRow = .fitBytesPerRow()
        .topRow = Math.min(.topRow, .maxTopRow())

        .headerText.clear()
        if .grouping == .Bytes
        {
            for column in .bytesPerRow
            {
                appendHexDigits(&.headerText, column, 2)
                .headerText.add(' 'u8)
                if column % HexDefaultGroupSize == HexDefaultGroupSize - 1 and column != .bytesPerRow - 1 do
                    .headerText.add(' 'u8)
            }
        }
        else
        {
            var column = 0'u64
            while column < .bytesPerRow
            {
                let start = .headerText.count
                .headerText.add('+'u8)
                appendHexDigits(&.headerText, column, 2)
                while .headerText.count - start < .valueCellChars() do
                    .headerText.add(' 'u8)
                .headerText.add(' 'u8)
                column += .valueSize()
            }
        }

        .syncScrollBar()
        .invalidate()
    }

    // Publishes the row range as a pixel span the scrollbar can drive, and places the thumb.
    mtd syncScrollBar()
    {
        if !@isset(.scroll) do
            return

        let span   = Math.min(cast(f32) .rowCount() * .rowHeight, HexScrollSpan)
        let usable = Math.max(span - .clientRect().height, 0)
        let maxTop = .maxTopRow()
        let y      = maxTop ? usable * cast(f32) .topRow / cast(f32) maxTop : 0

        .syncing = true
        defer .syncing = false
        .scroll.setScrollSize(.contentWidth(), span)
        .scroll.setScrollPos(.scroll.scrollPosition().x, y)
    }

    // Adopts the row a scrollbar gesture selected.
    //
    // The bar is a proportional control here, never the authority: the row it names is read back
    // through the row count, so a file with more rows than a span has pixels still reaches all of
    // them.
    mtd adoptScrollPosition(position: f32)
    {
        if .syncing or !@isset(.scroll) do
            return
        let usable = Math.max(.scroll.scrollSize.y - .clientRect().height, 1)
        let ratio  = Math.clamp(position / usable, 0, 1)
        let row    = Math.min(cast(u64) Math.round(ratio * cast(f32) .maxTopRow()), .maxTopRow())
        if row == .topRow do
            return
        .topRow = row
        .invalidate()
    }

    mtd setTopRow(row: u64)
    {
        let clamped = Math.min(row, .maxTopRow())
        if clamped == .topRow do
            return
        .topRow = clamped
        .syncScrollBar()
        .invalidate()
    }

    mtd scrollByRows(delta: s64)
    {
        let target = cast(s64) .topRow + delta
        .setTopRow(target < 0 ? 0 : cast(u64) target)
    }

    mtd ensureCaretVisible(center: bool)
    {
        if !.bytesPerRow do
            return
        let row     = .caret / .bytesPerRow
        let visible = .visibleRows()

        if center
        {
            .setTopRow(row > visible / 2 ? row - visible / 2 : 0)
            return
        }

        if row < .topRow do
            .setTopRow(row)
        elif row >= .topRow + visible do
            .setTopRow(row - visible + 1)
    }

    // Moves the caret to `target`, extending the selection instead of replacing it when asked.
    mtd moveCaret(target: u64, extend: bool, center = false)
    {
        if !.doc.fileSize do
            return
        let clamped = .groupStart(Math.min(target, .lastOffset()))
        .caret = clamped
        if !extend do
            .anchor = clamped
        .ensureCaretVisible(center)
        .sigCaretChanged.call(me)
        .invalidate()
    }

    mtd moveCaretBy(delta: s64, extend: bool)
    {
        if !.doc.fileSize do
            return
        let target = cast(s64) .caret + delta
        if target < 0 do
            .moveCaret(0, extend)
        else do
            .moveCaret(cast(u64) target, extend)
    }

    mtd selectAll()
    {
        if !.doc.fileSize do
            return
        .anchor = 0
        .caret  = .lastOffset()
        .sigCaretChanged.call(me)
        .invalidate()
    }

    // Returns the byte under a point in view coordinates, or `Swag.U64.Max` outside the rows.
    mtd offsetAt(local: Math.Point)->u64
    {
        if .rowHeight <= 0 or .charWidth <= 0 or !.doc.fileSize do
            return Swag.U64.Max

        let x = local.x + .scrollPos.x
        let y = local.y - .headerHeight()
        if y < 0 do
            return Swag.U64.Max

        let row = .topRow + cast(u64) Math.floor(y / .rowHeight)
        if row >= .rowCount() do
            return Swag.U64.Max

        var column = 0'u64
        if x >= .textColumnLeft()
        {
            let cell = Math.floor((x - .textColumnLeft()) / .charWidth)
            column = cell <= 0 ? 0 : Math.min(cast(u64) cell, .bytesPerRow - 1)
        }
        elif x >= HexViewInset + .gutterWidth()
        {
            if .grouping == .Bytes
            {
                column = .bytesPerRow - 1
                for candidate in .bytesPerRow where x < .hexCellX(candidate) + 3 * .charWidth
                {
                    column = candidate
                    break
                }
            }
            else
            {
                let left  = HexViewInset + .gutterWidth()
                let group = cast(u64) Math.max(Math.floor((x - left) / (cast(f32) (.valueCellChars() + 1) * .charWidth)), 0)
                column = Math.min(group * .valueSize(), .bytesPerRow - 1)
            }
        }

        return Math.min(row * .bytesPerRow + column, .lastOffset())
    }

    // Reveals `length` bytes at `offset` and keeps them marked once the caret moves on.
    mtd revealRange(offset, length: u64)->bool
    {
        if offset >= .doc.fileSize do
            return false
        .matchStart  = offset
        .matchLength = Math.min(length, .doc.fileSize - offset)
        .anchor      = offset
        .caret       = .matchLength ? offset + .matchLength - 1 : offset
        .ensureCaretVisible(true)
        .sigCaretChanged.call(me)
        .invalidate()
        return true
    }

    mtd setBytesPerRow(count: u64, auto: bool)
    {
        .autoFitRow = auto
        if !auto do
            .bytesPerRow = Math.clamp(count, HexMinBytesPerRow, HexMaxBytesPerRow)
        .refreshLayout()
        .ensureCaretVisible(false)
        .sigCaretChanged.call(me)
    }

    // Changes the scalar represented by one visual group and aligns the selection to it.
    mtd setGrouping(grouping: HexGrouping)
    {
        if .grouping == grouping do
            return
        .grouping = grouping
        .caret    = .groupStart(.caret)
        .anchor   = .groupStart(.anchor)
        .refreshLayout()
        .sigCaretChanged.call(me)
    }

    mtd setBigEndian(value: bool)
    {
        if .bigEndian == value do
            return
        .bigEndian = value
        .invalidate()
        .sigCaretChanged.call(me)
    }

    // Copies the selection, bounded to `HexCopyLimit` so a select-all over a large file stays a
    // clipboard operation rather than a way to load it.
    mtd copySelection(form: HexCopyForm)
    {
        if !.doc.fileSize do
            return
        let start = .selectionStart()
        let bytes = .doc.read(start, Math.min(.selectionLength(), HexCopyLimit))
        if bytes.isEmpty() do
            return

        switch form
        {
        case .Dump:
            Clipboard.addString(formatHexDump(bytes.toSlice(), start, .bytesPerRow, .offsetDigits, .displayGroupSize()).toString())

        case .Bytes:
            var text: Array'u8
            text.reserve(bytes.count * 3)
            for value, index in bytes
            {
                if index do
                    text.add(' 'u8)
                appendHexDigits(&text, value, 2)
            }

            Clipboard.addString(@mkstring(text.buffer!, text.count))

        case .Text:
            var text: Array'u8
            text.reserve(bytes.count)
            for value in bytes do
                text.add(isHexPrintable(value) ? value : '.'u8)
            Clipboard.addString(@mkstring(text.buffer!, text.count))
        }
    }

    // Asks for an offset and moves there, centered so its neighbourhood is readable.
    mtd promptGoToOffset()
    {
        let surface = .surface
        if !surface or !.doc.fileSize do
            return

        var current: Array'u8
        appendHexDigits(&current, .caret, .offsetDigits)

        var options: EditDlgOptions
        options.title   = hexStrings().ui_GoTo
        options.message = hexStrings().ui_GoToMessage
        options.text    = @mkstring(current.buffer!, current.count)

        let dialog = EditDlg.createSingleLine(surface!, options)
        if dialog.doModal() != Dialog.BtnOk do
            return

        let typed = dialog.text()
        discard .goToTypedOffset(typed.toString())
    }

    // Moves to the offset `text` names, centered so its neighbourhood is readable.
    mtd goToTypedOffset(text: string)->bool
    {
        let target = parseHexOffset(text, .caret, .doc.fileSize)
        if target == Swag.U64.Max do
            return false
        .moveCaret(target, false, center: true)
        return true
    }

    mtd showContextMenu(surfacePos: Math.Point)
    {
        // A copy of the whole of a large file would be the one operation that materializes it, so
        // it is bounded — and the bound is named on the commands it applies to rather than left to
        // be discovered from a clipboard that came back short.
        let menu = MenuCtrl.createPopup(me, owner: me)
        menu.addItem(ActionHex.CopyBytes)
        menu.addItem(ActionHex.CopyText)
        menu.addItem(ActionHex.CopyDump)
        menu.addSeparator()
        menu.addItem(ActionHex.SelectAll)
        menu.addItem(ActionHex.GoTo)
        menu.addSeparator()

        let widths = MenuCtrl.createPopup(menu, owner: me)
        widths.addItem(ActionHex.RowAuto)
        widths.addItem(ActionHex.Row8)
        widths.addItem(ActionHex.Row16)
        widths.addItem(ActionHex.Row32)
        widths.addItem(ActionHex.Row64)
        menu.addPopup(widths, ActionHex.RowWidth)
        discard menu.doModal(surfacePos, .TopLeft, autoDestroy: true)
    }

    // Rebuilds the five reusable buffers one row is drawn from.
    mtd buildRow(rowOffset: u64)
    {
        .rowOffsetText.clear()
        .rowHexStrong.clear()
        .rowHexFaint.clear()
        .rowTextStrong.clear()
        .rowTextFaint.clear()
        appendHexDigits(&.rowOffsetText, rowOffset, .offsetDigits)

        if .grouping == .Bytes
        {
            for column in .bytesPerRow
            {
                let offset = rowOffset + column
                if offset >= .doc.fileSize do
                    break

                let value = .doc.byteAt(offset)
                let faint = value == 0
                appendHexDigits(faint ? &.rowHexFaint : &.rowHexStrong, value, 2)
                let other = faint ? &.rowHexStrong : &.rowHexFaint
                other.add(' 'u8)
                other.add(' 'u8)

                .rowHexStrong.add(' 'u8)
                .rowHexFaint.add(' 'u8)
                if column % HexDefaultGroupSize == HexDefaultGroupSize - 1
                {
                    .rowHexStrong.add(' 'u8)
                    .rowHexFaint.add(' 'u8)
                }
            }
        }
        else
        {
            var column = 0'u64
            while column < .bytesPerRow
            {
                let offset   = rowOffset + column
                let complete = offset + .valueSize() <= .doc.fileSize
                let raw      = complete ? .scalarAt(offset) : 0
                let text     = complete ? formatHexScalar(.grouping, raw) : String.from("--")
                let faint    = complete and raw == 0
                let target   = faint ? &.rowHexFaint : &.rowHexStrong
                let other    = faint ? &.rowHexStrong : &.rowHexFaint
                for index in @countof(text)
                {
                    target.add(text[index])
                    other.add(' 'u8)
                }

                var written = @countof(text)
                while written < .valueCellChars()
                {
                    target.add(' 'u8)
                    other.add(' 'u8)
                    written += 1
                }

                target.add(' 'u8)
                other.add(' 'u8)
                column += .valueSize()
            }
        }

        for column in .bytesPerRow
        {
            let offset = rowOffset + column
            if offset >= .doc.fileSize do
                break
            let value     = .doc.byteAt(offset)
            let printable = isHexPrintable(value)
            .rowTextStrong.add(printable ? value : ' 'u8)
            .rowTextFaint.add(printable ? ' 'u8 : '.'u8)
        }
    }

    mtd drawBuffer(painter: *Painter, buffer: *Array'u8, x, y: f32, font: *Font, color: Color)
    {
        if !buffer.count do
            return
        painter.drawString(x, y, @mkstring(buffer.buffer!, buffer.count), font, color)
    }

    // Fills the cells of `[first, last]` in both columns.
    mtd fillRange(painter: *Painter, first, last: u64, originX, y: f32, color: Color)
    {
        let firstColumn = first % .bytesPerRow
        let lastColumn  = last % .bytesPerRow
        let hexLeft     = originX + .hexCellX(firstColumn)
        let hexRight    = originX + .hexCellX(lastColumn) + cast(f32) .valueCellChars() * .charWidth
        painter.fillRect(hexLeft - 1, y, hexRight - hexLeft + 2, .rowHeight, color)

        let textLeft = originX + .textCellX(firstColumn)
        painter.fillRect(textLeft, y, cast(f32) (lastColumn - firstColumn + 1) * .charWidth, .rowHeight, color)
    }
}

impl IActionUI for ActionHex
{
    mtd impl accept(cxt: ActionContext)->bool
    {
        switch cxt.id
        {
        case ActionHex.CopyBytes, ActionHex.CopyText, ActionHex.CopyDump, ActionHex.SelectAll, ActionHex.GoTo, ActionHex.RowWidth, ActionHex.RowAuto, ActionHex.Row8, ActionHex.Row16, ActionHex.Row32, ActionHex.Row64: return true
        }

        return false
    }

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let grid    = cast(*HexGridView) cxt.wnd!
        let bounded = grid.selectionLength() > HexCopyLimit
        let limit   = StrConv.toDisplaySize(HexCopyLimit)

        switch cxt.id
        {
        case ActionHex.CopyBytes:
            evt.updatedFields |= .Name | .Shortcut
            evt.name          = bounded ? Format.toString(hexStrings().ui_CopyBytesMax, limit) : String.from(hexStrings().ui_CopyBytes)
            evt.shortcut      = "Ctrl+C"

        case ActionHex.CopyText:
            evt.updatedFields |= .Name
            evt.name          = bounded ? Format.toString(hexStrings().ui_CopyTextMax, limit) : String.from(hexStrings().ui_CopyText)

        case ActionHex.CopyDump:
            evt.updatedFields |= .Name
            evt.name          = bounded ? Format.toString(hexStrings().ui_CopyDumpMax, limit) : String.from(hexStrings().ui_CopyDump)

        case ActionHex.SelectAll:
            evt.updatedFields |= .Name | .Shortcut
            evt.name          = hexStrings().ui_SelectAll
            evt.shortcut      = "Ctrl+A"

        case ActionHex.GoTo:
            evt.updatedFields |= .Name | .Shortcut
            evt.name          = hexStrings().ui_GoTo
            evt.shortcut      = "Ctrl+G"

        case ActionHex.RowWidth:
            evt.updatedFields |= .Name
            evt.name          = hexStrings().ui_RowWidth

        case ActionHex.RowAuto:
            evt.updatedFields |= .Name | .Checked | .RenderingHint
            evt.name          = hexStrings().ui_RowAuto
            evt.checked       = grid.autoFitRow
            evt.renderingHint = .ExclusiveGroup

        case ActionHex.Row8, ActionHex.Row16, ActionHex.Row32, ActionHex.Row64:
            let width = cxt.id == ActionHex.Row8 ? 8'u64 : cxt.id == ActionHex.Row16 ? 16'u64 : cxt.id == ActionHex.Row32 ? 32'u64 : 64'u64
            evt.updatedFields |= .Name | .Checked | .RenderingHint
            evt.name          = Format.toString("%", width)
            evt.checked       = !grid.autoFitRow and grid.bytesPerRow == width
            evt.renderingHint = .ExclusiveGroup
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let grid = cast(*HexGridView) cxt.wnd!
        switch cxt.id
        {
        case ActionHex.CopyBytes: grid.copySelection(.Bytes)
        case ActionHex.CopyText:  grid.copySelection(.Text)
        case ActionHex.CopyDump:  grid.copySelection(.Dump)
        case ActionHex.SelectAll: grid.selectAll()
        case ActionHex.GoTo:      grid.promptGoToOffset()
        case ActionHex.RowAuto:   grid.setBytesPerRow(0, true)
        case ActionHex.Row8:      grid.setBytesPerRow(8, false)
        case ActionHex.Row16:     grid.setBytesPerRow(16, false)
        case ActionHex.Row32:     grid.setBytesPerRow(32, false)
        case ActionHex.Row64:     grid.setBytesPerRow(64, false)
        case ActionHex.RowWidth:  return false
        }

        return true
    }
}

impl IWnd for HexGridView
{
    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        discard evt
        .refreshLayout()
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .ThemeChanged do
            .refreshLayout()
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        discard evt
        .doc.close()
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let local = .surfaceToLocal(evt.surfacePos)

        switch evt.kind
        {
        case .Wheel where evt.modifiers.has(.Shift):
            evt.accepted = false

        case .Wheel:
            if evt.delta.y > 0 do
                .scrollByRows(-cast(s64) HexWheelRows)
            elif evt.delta.y < 0 do
                .scrollByRows(cast(s64) HexWheelRows)

        case .Pressed where evt.button == .Right:
            let offset = .offsetAt(local)
            if offset != Swag.U64.Max and !(offset >= .selectionStart() and offset <= .selectionEnd()) do
                .moveCaret(offset, false)
            .setFocus()
            .showContextMenu(evt.surfacePos)

        case .Pressed where evt.button == .Left:
            let offset = .offsetAt(local)
            if offset == Swag.U64.Max
            {
                evt.accepted = false
                return
            }

            .setFocus()
            .moveCaret(offset, evt.modifiers.has(.Shift))
            .selecting = true
            .captureMouse()

        case .Move where .selecting:
            let offset = .offsetAt(local)
            if offset != Swag.U64.Max do
                .moveCaret(offset, true)

        case .Released where .selecting and evt.button == .Left:
            .selecting = false
            .releaseMouse()

        default:
            evt.accepted = false
        }
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        let extend  = evt.modifiers.has(.Shift)
        let control = evt.modifiers.has(.Control)
        let unit    = cast(s64) .valueSize()
        let stride  = cast(s64) .bytesPerRow
        let page    = cast(s64) (.visibleRows() * .bytesPerRow)

        switch evt.key
        {
        case .Left:
            .moveCaretBy(-unit, extend)

        case .Right:
            .moveCaretBy(unit, extend)

        case .Up:
            .moveCaretBy(-stride, extend)

        case .Down:
            .moveCaretBy(stride, extend)

        case .PageUp:
            .moveCaretBy(-page, extend)

        case .PageDown:
            .moveCaretBy(page, extend)

        case .Home:
            if control do
                .moveCaret(0, extend)
            else do
                .moveCaret(.caret - .caret % .bytesPerRow, extend)

        case .End:
            if control do
                .moveCaret(.lastOffset(), extend)
            else do
                .moveCaret(.caret - .caret % .bytesPerRow + .bytesPerRow - .valueSize(), extend)

        case .C where control:
            .sendCommandEvent(ActionHex.CopyBytes)

        case .A where control:
            .sendCommandEvent(ActionHex.SelectAll)

        case .G where control:
            .sendCommandEvent(ActionHex.GoTo)

        default:
            evt.accepted = false
        }
    }

    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter  = evt.paintContext.painter
        let family   = .font()
        let resolved = family.regular
        if !resolved or .rowHeight <= 0 do
            return

        let font    = resolved!
        let colors  = .themeColors()
        let client  = .clientRect()
        let originX = -.scrollPos.x

        if !.doc.fileSize
        {
            let message = .doc.readFailed ? "This file could not be read." : "This file is empty."
            painter.drawString(originX + HexViewInset, client.y + HexViewInset, message, font, colors.label_TextLight)
            return
        }

        // Ink of a byte that carries a value, and of one that does not. Zero bytes keep their
        // place and lose their weight, which is what makes padding, alignment and unwritten
        // regions readable as shapes instead of as a wall of digits.
        let strongInk = colors.label_Text
        let faintInk  = Color.lerp(colors.view_Bk, colors.label_Text, 0.34)
        let headerInk = colors.label_TextFaint
        let focused   = .hasFocus()
        let selectBk  = focused ? colors.richEdit_SelBk : colors.richEdit_SelBkNoFocus
        let matchBk   = Color.lerp(colors.view_Bk, colors.hilight, 0.28)
        let caretBk   = colors.hilight
        let caretInk  = colors.hilightLightContrast

        let visible = .visibleRows()
        let first   = Math.min(.topRow * .bytesPerRow, .lastOffset())
        let count   = Math.min(visible * .bytesPerRow, .doc.fileSize - first)
        discard .doc.ensure(first, count)

        // Column header. It is the only chrome the grid carries, and one rule under it is all it
        // takes to separate it from the rows.
        let headerY = client.y + 4
        if .headerText.count do
            painter.drawString(originX + HexViewInset + .gutterWidth(), headerY, @mkstring(.headerText.buffer!, .headerText.count), font, headerInk)
        painter.drawString(originX + .textColumnLeft(), headerY, "text", font, headerInk)
        painter.drawLine(client.x, client.y + .headerHeight() - 2, client.right(), client.y + .headerHeight() - 2, colors.border, 1)

        let selectFirst = .selectionStart()
        let selectLast  = .selectionEnd()
        let matchLast   = .matchLength ? .matchStart + .matchLength - 1 : 0

        for row in visible
        {
            let rowOffset = (.topRow + row) * .bytesPerRow
            if rowOffset >= .doc.fileSize do
                break
            let rowLast = Math.min(rowOffset + .bytesPerRow - 1, .lastOffset())
            let y       = .rowTop(.topRow + row)

            if .matchLength and .matchStart <= rowLast and matchLast >= rowOffset do
                .fillRange(painter, Math.max(.matchStart, rowOffset), Math.min(matchLast, rowLast), originX, y, matchBk)
            if .hasSelection() and selectFirst <= rowLast and selectLast >= rowOffset do
                .fillRange(painter, Math.max(selectFirst, rowOffset), Math.min(selectLast, rowLast), originX, y, selectBk)

            .buildRow(rowOffset)
            .drawBuffer(painter, &.rowOffsetText, originX + HexViewInset, y, font, headerInk)
            .drawBuffer(painter, &.rowHexStrong, originX + HexViewInset + .gutterWidth(), y, font, strongInk)
            .drawBuffer(painter, &.rowHexFaint, originX + HexViewInset + .gutterWidth(), y, font, faintInk)
            .drawBuffer(painter, &.rowTextStrong, originX + .textColumnLeft(), y, font, strongInk)
            .drawBuffer(painter, &.rowTextFaint, originX + .textColumnLeft(), y, font, faintInk)

            // The caret is a filled cell in the column being read and an outline in the other, so
            // one glance says both which byte and which character it stands on.
            if .caret >= rowOffset and .caret <= rowLast
            {
                let column   = .caret % .bytesPerRow
                let complete = .caret + .valueSize() <= .doc.fileSize
                let text     = .grouping == .Bytes ? Format.toString("%{X02}", .doc.byteAt(.caret)) : complete ? formatHexScalar(.grouping, .scalarAt(.caret)) : String.from("--")
                .caretText.clear()
                for index in @countof(text) do
                    .caretText.add(text[index])

                painter.fillRect(originX + .hexCellX(column) - 1, y, cast(f32) .valueCellChars() * .charWidth + 2, .rowHeight, caretBk)
                painter.drawString(originX + .hexCellX(column), y, @mkstring(.caretText.buffer!, .caretText.count), font, caretInk)
                painter.drawRect(originX + .textCellX(column), y, cast(f32) (.groupEnd(.caret) - .caret + 1) * .charWidth, .rowHeight, caretBk, 1)
            }
        }
    }
}

impl HexGridView
{
    // Creates the grid inside a scroll frame, and opens the file it reads through.
    func create(parent: *Wnd, fileName: string)->*HexGridView
    {
        let scroll = Wnd.create'ScrollWnd(parent, "", {})
        scroll.dockStyle = .Center

        let result = scroll.createView'HexGridView()
        result.scroll          = scroll
        result.backgroundStyle = .View
        result.registerAction'ActionHex()
        result.focusPolicy = .Tab
        result.wndFlags    |= WndFlags.NoScroll | WndFlags.NoFocusRing | WndFlags.ClipChildren
        result.cursor      = Cursor.from(CursorShape.IBeam)
        result.style.setFont(result.theme().createDefaultFontFS(result.themeMetrics().defaultFixedFontSize), .Regular)
        discard result.doc.open(fileName)

        scroll.sigScrollPositionChanged += func|view = result|(scrollWnd, oldPosition, newPosition)
        {
            discard scrollWnd
            discard oldPosition
            view.adoptScrollPosition(newPosition.y)
        }

        result.refreshLayout()
        return result
    }
}
