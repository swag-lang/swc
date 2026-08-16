#global internal

using Core, Pixel, Gui

// Width the panel is docked at, the air inside it, and the column its readings start in.
const HexInspectorWidth     = 232.0
const HexInspectorInset     = 12.0
const HexInspectorNameWidth = 68.0

// Size the panel reads its names and values at. The values are the widest thing here — an unsigned
// 64-bit integer spells twenty digits — so the panel is sized on those and not on its names.
const HexInspectorFontSize = 12'u32

// Bytes the panel decodes at the caret. Every reading it offers fits in eight.
const HexInspectorReach = 8'u64

// Placeholder for a reading the file has too few bytes left to give.
private const HexInspectorNoValue = "--"

// One line of the panel. An empty name is the blank line between two blocks.
struct HexInspectorLine
{
    name:  String
    value: String
}

// Values the bytes under the caret spell in every reading a binary format is written in.
//
// This is what separates reading a file from looking at one: the same four bytes are a length, a
// tag, or a float depending on the structure around them, and the panel shows every reading at
// once instead of leaving the reader to assemble one by hand.
struct HexInspectorView
{
    using wnd: Wnd

    #[Swag.Late]
    {
        grid:        *HexGridView
        orderButton: *PushButton
    }

    lines:     Array'HexInspectorLine
    bytes:     Array'u8
    bigEndian: bool
}

impl HexInspectorView
{
    // Assembles the first `size` bytes under the caret in the current byte order.
    mtd scalar(size: u64)->u64
    {
        var raw = 0'u64
        for index in size
        {
            let position = .bigEndian ? index : size - 1 - index
            raw = (raw << 8) | cast(u64) .bytes[position]
        }

        return raw
    }

    // Reinterprets `raw` as a signed integer of `size` bytes.
    mtd signed(raw: u64, size: u64)->s64
    {
        let bits = size * 8
        if bits >= 64 do
            return cast #bit (s64) raw
        let sign = 1'u64 << (bits - 1)
        if raw & sign do
            return cast #bit (s64) (raw | ~((1'u64 << bits) - 1))
        return cast(s64) raw
    }

    mtd addLine(name, value: string)
    {
        var line: HexInspectorLine
        line.name  = name
        line.value = value
        .lines.add(#move line)
    }

    mtd addBlank()
    {
        var line: HexInspectorLine
        .lines.add(#move line)
    }

    mtd groupingName()->string
    {
        switch .grid.grouping
        {
        case .Unsigned16: return "uint16"
        case .Unsigned32: return "uint32"
        case .Unsigned64: return "uint64"
        case .Signed16:   return "int16"
        case .Signed32:   return "int32"
        case .Signed64:   return "int64"
        case .Float32:    return "float32"
        case .Float64:    return "float64"
        default:          return "byte"
        }
    }

    // Formats the scalar selected by the grid's grouping mode.
    mtd groupingValue()->String
    {
        let size = .grid.valueSize()
        if .bytes.count < size do
            return String.from(HexInspectorNoValue)
        let raw = .scalar(size)
        switch .grid.grouping
        {
        case .Signed16, .Signed32, .Signed64: return Format.toString("%", .signed(raw, size))
        case .Float32: return Format.toString("%{g9}", cast #bit (f32) (cast(u32) raw))
        case .Float64: return Format.toString("%{g15}", cast #bit (f64) raw)
        default:       return Format.toString("%", raw)
        }
    }

    // Adds the signed and unsigned readings of an integer of `size` bytes, or a placeholder for
    // each when the file ends before the caret has that many bytes left.
    mtd addInteger(size: u64)
    {
        let signedName   = Format.toString("int%", size * 8)
        let unsignedName = Format.toString("uint%", size * 8)
        if .bytes.count < size
        {
            .addLine(signedName.toString(), HexInspectorNoValue)
            .addLine(unsignedName.toString(), HexInspectorNoValue)
            return
        }

        let raw          = .scalar(size)
        let signedText   = Format.toString("%", .signed(raw, size))
        let unsignedText = Format.toString("%", raw)
        .addLine(signedName.toString(), signedText.toString())
        .addLine(unsignedName.toString(), unsignedText.toString())
    }

    // Rebuilds every line from the caret. Called when the caret moves, never while painting.
    mtd refresh()
    {
        .lines.clear()
        .bytes.clear()

        let grid = .grid
        if !grid.doc.fileSize
        {
            .invalidate()
            return
        }

        .bytes = grid.doc.read(grid.selectionStart(), HexInspectorReach)

        var offsetText: Array'u8
        offsetText.add('0'u8)
        offsetText.add('x'u8)
        appendHexDigits(&offsetText, grid.caret, grid.offsetDigits)
        .addLine("offset", @mkstring(offsetText.buffer!, offsetText.count))

        let length       = grid.selectionLength()
        let selectedText = Format.toString("% byte%", length, length == 1 ? "" : "s")
        .addLine("selection", selectedText.toString())
        let grouped = .groupingValue()
        .addLine(.groupingName(), grouped.toString())
        .addBlank()

        if .bytes.isEmpty()
        {
            .addLine("value", HexInspectorNoValue)
            .invalidate()
            return
        }

        .addInteger(1)
        .addInteger(2)
        .addInteger(4)
        .addInteger(8)
        .addBlank()

        // Nine and fifteen significant digits: enough to recognize a value in a file, and short
        // enough that the reading fits its column instead of being cut in half by it.
        if .bytes.count >= 4
        {
            let text = Format.toString("%{g9}", cast #bit (f32) (cast(u32) .scalar(4)))
            .addLine("float32", text.toString())
        }
        else do
            .addLine("float32", HexInspectorNoValue)

        if .bytes.count >= 8
        {
            let text = Format.toString("%{g15}", cast #bit (f64) .scalar(8))
            .addLine("float64", text.toString())
        }
        else do
            .addLine("float64", HexInspectorNoValue)

        .addBlank()
        let binaryText = Format.toString("%{B08}", .bytes[0])
        .addLine("binary", binaryText.toString())
        .invalidate()
    }

    mtd toggleByteOrder()
    {
        .bigEndian = !.bigEndian
        .orderButton.setText(.bigEndian ? "Big endian" : "Little endian")
        .refresh()
    }
}

impl IWnd for HexInspectorView
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter  = evt.paintContext.painter
        let family   = .font()
        let resolved = family.regular
        if !resolved do
            return

        let font   = resolved!
        let colors = .themeColors()
        let client = .clientRect()
        let step   = Math.ceil(font.height) + 2
        var y      = client.y + HexInspectorInset
        if @isset(.orderButton) do
            y = .orderButton.position.bottom() + HexInspectorInset

        for line in .lines
        {
            if y + step > client.bottom() do
                break
            if line.name.isEmpty()
            {
                y += step * 0.5
                continue
            }

            painter.drawString(client.x + HexInspectorInset, y, line.name.toString(), font, colors.label_TextFaint)
            painter.drawString(client.x + HexInspectorInset + HexInspectorNameWidth, y, line.value.toString(), font, colors.label_Text)
            y += step
        }
    }
}

impl HexInspectorView
{
    // Creates the value panel beside the grid it reads.
    func create(parent: *Wnd, grid: *HexGridView)->*HexInspectorView
    {
        let result = Wnd.create'HexInspectorView(parent, "sFileScope.hex.inspector", {0, 0, HexInspectorWidth, 0})
        result.dockStyle       = .Right
        result.backgroundStyle = .Window
        result.wndFlags        |= WndFlags.ClipChildren
        result.grid            = grid
        result.style.setFont(result.theme().createDefaultFontFS(HexInspectorFontSize), .Regular)

        // The byte order sits above the readings it decides, not under them: it is a mode the whole
        // panel is read in, and a control that qualifies everything below it belongs before it.
        with result.orderButton = PushButton.create(result, "Little endian", {0, 0, 0, 32})
        {
            .dockStyle  = .Top
            .margin     = {HexInspectorInset, HexInspectorInset, HexInspectorInset, 0}
            .toolTip    = "Read multi-byte values in the other byte order"
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.toggleByteOrder()
            }
        }

        result.refresh()
        return result
    }
}
