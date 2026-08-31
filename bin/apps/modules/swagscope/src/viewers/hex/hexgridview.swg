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
const HexWheelRows                     = 3'u64
const HexMinBytesPerRow                = 8'u64
const HexMaxBytesPerRow                = 64'u64
const HexMinFontSize                   = 8'u32
const HexMaxFontSize                   = 24'u32
const HexDragScrollRate: Time.Duration = 50'ms

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
    result.reserve(bytes.count * 5)

    var line: Array'u8
    var row = 0'u64
    while row < bytes.count
    {
        line.clear()
        appendHexDigits(&line, baseOffset + row, offsetDigits)
        line.add(' 'u8)
        line.add(' 'u8)

        for column in bytesPerRow
        {
            let index = row + column
            if index < bytes.count do
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
            if index >= bytes.count do
                break
            let value = bytes[index]
            line.add(isHexPrintable(value) ? value : '.'u8)
        }

        result += Swag.makeString(line.buffer!, line.count)
        result += "\n"
        row    += bytesPerRow
    }

    return result
}

// Reads an absolute, percentage, named, or caret-relative offset, and returns `Swag.U64.Max` when
// the text names none. Unprefixed numbers remain hexadecimal; `0d` opts into decimal explicitly.
func parseHexOffset(text: string, caret, fileSize: u64)->u64
{
    let trimmed = Latin1.trim(text)
    let count   = trimmed.count
    if !count or !fileSize do
        return Swag.U64.Max

    var index    = 0'u64
    var relative = 0's32
    if trimmed[index] == '+'u8 or trimmed[index] == '-'u8
    {
        relative = trimmed[index] == '+'u8 ? 1 : -1
        index    += 1
    }

    if index >= count do
        return Swag.U64.Max

    let valueText = cast(string) trimmed[index to]
    if !relative and Utf8.compare(valueText, "caret", .Latin1NoCase) == 0 do
        return caret
    if !relative and Utf8.compare(valueText, "filesize", .Latin1NoCase) == 0 do
        return fileSize - 1

    let percentage = !relative and trimmed[count - 1] == '%'u8
    let end        = percentage ? count - 1 : count
    if index >= end do
        return Swag.U64.Max

    var radix = percentage ? 10'u64 : 16'u64
    if index + 1 < end and trimmed[index] == '0'u8 and (trimmed[index + 1] == 'x'u8 or trimmed[index + 1] == 'X'u8)
    {
        index += 2
    }
    elif index + 1 < end and trimmed[index] == '0'u8 and (trimmed[index + 1] == 'd'u8 or trimmed[index + 1] == 'D'u8)
    {
        radix = 10
        index += 2
    }

    var value  = 0'u64
    var digits = 0'u64
    while index < end
    {
        let c      = trimmed[index]
        var nibble = 16'u8
        if c >= '0'u8 and c <= '9'u8 do
            nibble = c - '0'u8
        elif radix == 16 and c >= 'a'u8 and c <= 'f'u8 do
            nibble = c - 'a'u8 + 10
        elif radix == 16 and c >= 'A'u8 and c <= 'F'u8 do
            nibble = c - 'A'u8 + 10
        elif c == ' 'u8 or c == '_'u8
        {
            index += 1
            continue
        }

        if nibble >= radix do
            return Swag.U64.Max

        // A value wider than the address space is a typing accident, not an offset.
        if value > (Swag.U64.Max - nibble) / radix do
            return Swag.U64.Max
        value  = value * radix + nibble
        digits += 1
        index  += 1
    }

    if !digits do
        return Swag.U64.Max

    if percentage
    {
        if value > 100 do
            return Swag.U64.Max
        let last = fileSize - 1
        return last / 100 * value + last % 100 * value / 100
    }

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

    // Accepted results in file order. Painting binary-searches this list for each visible row, so
    // marking a large result set never makes a scroll proportional to matches outside the screen.
    searchHits: #null *Array'Viewer.SearchMatch

    bytesPerRow  = 16'u64
    offsetDigits = 8'u64
    autoFitRow   = true
    grouping     = HexGrouping.Bytes
    bigEndian: bool

    selecting: bool     // Whether a drag is currently extending the selection.
    layouting: bool     // Guards the resize a scrollbar appearing re-enters.
    syncing:   bool     // Guards the position signal our own scrollbar update raises.

    selectionPoint: Math.Point       // Last local pointer position of an active drag.
    selectionTimer: #null *Timer     // Repeats autoscroll while the pointer stays outside the viewport.

    charWidth:      f32
    rowHeight:      f32
    fontSize:       u32
    sigZoomChanged: SigArray'func||(*HexGridView)

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

    mtd setFontSize(size: u32)
    {
        let next = Math.clamp(size, HexMinFontSize, HexMaxFontSize)
        if .fontSize == next do
            return
        .fontSize = next
        .style.setFont(.theme().createDefaultFontFS(next), .Regular)
        .refreshLayout()
        .sigZoomChanged.call(me)
    }

    mtd adjustFontSize(delta: s32)
    {
        let next = Math.clamp(cast(s32) .fontSize + delta, cast(s32) HexMinFontSize, cast(s32) HexMaxFontSize)
        .setFontSize(cast(u32) next)
    }

    mtd resetFontSize()
    {
        .setFontSize(.themeMetrics().defaultFixedFontSize)
    }

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

    mtd selectionStart()->u64 => Math.min(.caret, .anchor)

    mtd selectionEnd()->u64 => Math.max(.caret, .anchor)

    mtd selectionLength()->u64 => .doc.fileSize ? .selectionEnd() - .selectionStart() + 1 : 0

    mtd hasSelection()->bool => .caret != .anchor

    // Reports the printable lane occupied by the current raw-byte match. The grid also marks the
    // hexadecimal lane for forensic reading; the shared application halo chooses the text lane so
    // one occurrence still has one unmistakable visual anchor.
    mtd matchBounds(result: *Math.Rectangle)->bool
    {
        if !.matchLength or !.doc.fileSize do
            return false

        let matchLast    = Math.min(.matchStart + .matchLength - 1, .lastOffset())
        let visibleFirst = .topRow * .bytesPerRow
        let visibleLast  = Math.min((.topRow + .visibleRows()) * .bytesPerRow - 1, .lastOffset())
        if matchLast < visibleFirst or .matchStart > visibleLast do
            return false

        let first    = Math.max(.matchStart, visibleFirst)
        let last     = Math.min(matchLast, visibleLast)
        let firstRow = first / .bytesPerRow
        let lastRow  = last / .bytesPerRow
        var local: Math.Rectangle
        if firstRow == lastRow
        {
            let column = first % .bytesPerRow
            local = {.textCellX(column) - .scrollPos.x, .rowTop(firstRow), cast(f32) (last - first + 1) * .charWidth, .rowHeight}
        }
        else
        {
            local = {.textColumnLeft() - .scrollPos.x, .rowTop(firstRow), cast(f32) .bytesPerRow * .charWidth,
                     cast(f32) (lastRow - firstRow + 1) * .rowHeight}
        }

        result[] = .localToSurface(local)
        return !result.isEmpty()
    }

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
        if !Swag.isSet(.scroll) do
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
        if .syncing or !Swag.isSet(.scroll) do
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
        let clamped = Math.min(target, .lastOffset())
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
        .caret       = offset
        .anchor      = .matchLength ? offset + .matchLength - 1 : offset
        .ensureCaretVisible(true)
        .sigCaretChanged.call(me)
        .invalidate()
        return true
    }

    mtd clearSearchMatch()
    {
        .matchStart  = 0
        .matchLength = 0
        .searchHits  = null
        .anchor      = .caret
        .invalidate()
    }

    mtd setSearchMatches(matches: #null *Array'Viewer.SearchMatch)
    {
        .searchHits = matches
        .invalidate()
    }

    // Returns the first match whose end reaches `offset`. Search results arrive in file order.
    mtd firstSearchHitAt(offset: u64)->u64
    {
        if !.searchHits do
            return 0
        let hits  = .searchHits!
        var first = 0'u64
        var count = hits.count
        while count
        {
            let step  = count / 2
            let index = first + step
            let match = &hits[index]
            let last  = match.offset + Math.min(match.length - 1, Swag.U64.Max - match.offset)
            if last < offset
            {
                first = index + 1
                count -= step + 1
            }
            else do
                count = step
        }

        return first
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

    // Changes the scalar represented by one visual group without moving the byte-exact caret.
    mtd setGrouping(grouping: HexGrouping)
    {
        if .grouping == grouping do
            return
        .grouping = grouping
        .refreshLayout()
        .sigCaretChanged.call(me)
    }

    mtd stopSelection()
    {
        .selecting = false
        if .selectionTimer
        {
            .removeTimer(.selectionTimer!)
            .selectionTimer = null
        }

        if .mouseCapture() == me do
            .releaseMouse()
    }

    // Extends a drag at `local`, scrolling one row immediately and then on a timer while the
    // pointer remains above or below the byte rows.
    mtd updateDragSelection(local: Math.Point)
    {
        .selectionPoint = local
        let client = .clientRect()
        let above  = local.y < .headerHeight()
        let below  = local.y >= client.bottom()

        if above do
            .scrollByRows(-1)
        elif below do
            .scrollByRows(1)

        var targetPoint = local
        if above do
            targetPoint.y = .headerHeight() + 1
        elif below do
            targetPoint.y = client.bottom() - 1
        let offset = .offsetAt(targetPoint)
        if offset != Swag.U64.Max do
            .moveCaret(offset, true)

        if (above or below) and !.selectionTimer do
            .selectionTimer = .addTimer(HexDragScrollRate)
        elif !above and !below and .selectionTimer
        {
            .removeTimer(.selectionTimer!)
            .selectionTimer = null
        }
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

            Clipboard.addString(Swag.makeString(text.buffer!, text.count))

        case .Text:
            var text: Array'u8
            text.reserve(bytes.count)
            for value in bytes do
                text.add(isHexPrintable(value) ? value : '.'u8)
            Clipboard.addString(Swag.makeString(text.buffer!, text.count))
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
        options.text    = Swag.makeString(current.buffer!, current.count)

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
                for index in text.count
                {
                    target.add(text[index])
                    other.add(' 'u8)
                }

                var written = text.count
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
        painter.drawString(x, y, Swag.makeString(buffer.buffer!, buffer.count), font, color)
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
        case ActionHex.CopyBytes, ActionHex.CopyText, ActionHex.CopyDump, ActionHex.SelectAll, ActionHex.GoTo: return true
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
        }

        return true
    }
}

impl IWnd for HexGridView
{
    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .selectionTimer or !.selecting
        {
            evt.accepted = false
            return
        }

        .updateDragSelection(.selectionPoint)
    }

    mtd impl onResizeEvent(evt: *ResizeEvent)
    {
        discard evt
        .refreshLayout()
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .ThemeChanged do
            .refreshLayout()
        elif evt.kind == .LanguageChanged do
            .invalidate()
        else do
            evt.accepted = false
    }

    mtd impl onFocusEvent(evt: *FocusEvent)
    {
        if evt.kind != .Lost or !.selecting
        {
            evt.accepted = false
            return
        }

        .stopSelection()
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        discard evt
        .stopSelection()
        .doc.close()
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let local = .surfaceToLocal(evt.surfacePos)

        switch evt.kind
        {
        case .Wheel where evt.modifiers.has(.Control):
            if evt.delta.y > 0 do
                .adjustFontSize(1)
            elif evt.delta.y < 0 do
                .adjustFontSize(-1)

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
            .updateDragSelection(local)

        case .Released where .selecting and evt.button == .Left:
            .stopSelection()

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
        let unit    = 1's64
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
                .moveCaret(Math.min(.caret - .caret % .bytesPerRow + .bytesPerRow - 1, .lastOffset()), extend)

        case .C where control:
            .sendCommandEvent(ActionHex.CopyBytes)

        case .A where control:
            .sendCommandEvent(ActionHex.SelectAll)

        case .G where control:
            .sendCommandEvent(ActionHex.GoTo)

        case .Add, .OemPlus:
            if control do
                .adjustFontSize(1)
            else do
                evt.accepted = false

        case .Subtract, .OemMinus:
            if control do
                .adjustFontSize(-1)
            else do
                evt.accepted = false

        case .D0 where control:
            .resetFontSize()

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

        if .doc.readFailed do
            return

        if !.doc.fileSize
        {
            painter.drawString(originX + HexViewInset, client.y + HexViewInset, hexStrings().ui_Empty, font, colors.label_TextLight)
            return
        }

        // Ink of a byte that carries a value, and of one that does not. Zero bytes keep their
        // place and lose their weight, which is what makes padding, alignment and unwritten
        // regions readable as shapes instead of as a wall of digits.
        let strongInk   = colors.label_Text
        let faintInk    = Color.lerp(colors.view_Bk, colors.label_Text, 0.34)
        let headerInk   = colors.label_TextFaint
        let focused     = .hasFocus()
        let selectBk    = focused ? colors.richEdit_SelBk : colors.richEdit_SelBkNoFocus
        let searchHitBk = Color.lerp(colors.view_Bk, colors.searchMatch_Border, 0.12)
        let matchBk     = colors.searchMatch_Bk
        let caretBk     = colors.hilight
        let caretInk    = colors.hilightLightContrast

        let visible = .visibleRows()
        let first   = Math.min(.topRow * .bytesPerRow, .lastOffset())
        let count   = Math.min(visible * .bytesPerRow, .doc.fileSize - first)
        discard .doc.ensure(first, count)

        // Column header. It is the only chrome the grid carries, and one rule under it is all it
        // takes to separate it from the rows.
        let headerY = client.y + 4
        if .headerText.count do
            painter.drawString(originX + HexViewInset + .gutterWidth(), headerY, Swag.makeString(.headerText.buffer!, .headerText.count), font, headerInk)
        painter.drawString(originX + .textColumnLeft(), headerY, hexStrings().ui_TextColumn, font, headerInk)
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

            let hits     = .searchHits
            var hitIndex = .firstSearchHitAt(rowOffset)
            while hits and hitIndex < hits!.count and hits![hitIndex].offset <= rowLast
            {
                let hit     = &hits![hitIndex]
                let hitLast = hit.offset + Math.min(hit.length - 1, Swag.U64.Max - hit.offset)
                .fillRange(painter, Math.max(hit.offset, rowOffset), Math.min(hitLast, rowLast), originX, y, searchHitBk)
                hitIndex += 1
            }

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
                let valueOffset = .groupStart(.caret)
                let column      = valueOffset % .bytesPerRow
                let complete    = valueOffset + .valueSize() <= .doc.fileSize
                let text        = .grouping == .Bytes ? Format.toString("%{X02}", .doc.byteAt(.caret)) : complete ? formatHexScalar(.grouping, .scalarAt(valueOffset)) : String.from("--")
                .caretText.clear()
                for index in text.count do
                    .caretText.add(text[index])

                painter.fillRect(originX + .hexCellX(column) - 1, y, cast(f32) .valueCellChars() * .charWidth + 2, .rowHeight, caretBk)
                painter.drawString(originX + .hexCellX(column), y, Swag.makeString(.caretText.buffer!, .caretText.count), font, caretInk)
                painter.drawRect(originX + .textCellX(.caret % .bytesPerRow), y, .charWidth, .rowHeight, caretBk, 1)
            }
        }
    }
}

impl HexGridView
{
    // Creates an empty grid inside a scroll frame.
    func create(parent: *Wnd)->*HexGridView
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
        result.fontSize    = result.themeMetrics().defaultFixedFontSize
        result.style.setFont(result.theme().createDefaultFontFS(result.fontSize), .Regular)
        scroll.sigScrollPositionChanged += func|view = result|(scrollWnd, oldPosition, newPosition)
        {
            discard scrollWnd
            discard oldPosition
            view.adoptScrollPosition(newPosition.y)
        }

        result.refreshLayout()
        return result
    }

    // Creates the grid and opens the file it reads through.
    func create(parent: *Wnd, fileName: string)->*HexGridView
    {
        let result = HexGridView.create(parent)
        discard result.doc.open(fileName)
        result.refreshLayout()
        return result
    }

    // Publishes a document opened outside the GUI thread.
    mtd exchangeDocument(document: *HexDocument)
    {
        swap(&.doc, document)
        .refreshLayout()
        .invalidate()
    }
}
