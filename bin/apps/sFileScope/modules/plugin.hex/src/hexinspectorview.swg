#global internal

using Core, Pixel, Gui

// Width the panel is docked at, the air inside it, and the column its readings start in.
const HexInspectorWidth     = 232.0
const HexInspectorInset     = 12.0
const HexInspectorNameWidth = 68.0

// Size the panel reads its names and values at. The values are the widest thing here — an unsigned
// 64-bit integer spells twenty digits — so the panel is sized on those and not on its names.
const HexInspectorFontSize = 12'u32

// Placeholder for a reading the file has too few bytes left to give.
private const HexInspectorNoValue = "--"

// One line of the panel. An empty name is the blank line between two blocks.
struct HexInspectorLine
{
    name:  String
    value: String
}

// Values the scalar under the caret spells at the width selected by the grid.
//
// Keeping this panel on the same width as the document prevents unrelated 32- and 64-bit readings
// from crowding a view whose reader explicitly chose 8- or 16-bit values.
struct HexInspectorView
{
    using wnd: Wnd

    #[Swag.Late]
    {
        grid:        *HexGridView
        orderButton: *PushButton
    }

    lines: Array'HexInspectorLine
    bytes: Array'u8
}

impl HexInspectorView
{
    // Assembles the first `size` bytes under the caret in the current byte order.
    mtd scalar(size: u64)->u64
    {
        var raw = 0'u64
        for index in size
        {
            let position = .grid.bigEndian ? index : size - 1 - index
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

    mtd addCurrentWidthValues()
    {
        let size = .grid.valueSize()
        let bits = size * 8
        let hexName = Format.toString("hex%", bits)
        let unsignedName = Format.toString("uint%", bits)
        let signedName = Format.toString("int%", bits)
        if .bytes.count < size
        {
            .addLine(hexName.toString(), HexInspectorNoValue)
            .addLine(unsignedName.toString(), HexInspectorNoValue)
            .addLine(signedName.toString(), HexInspectorNoValue)
            if size == 4 or size == 8
            {
                let floatName = Format.toString("float%", bits)
                .addLine(floatName.toString(), HexInspectorNoValue)
            }

            return
        }

        let raw = .scalar(size)
        let hexGrouping = size == 1 ? HexGrouping.Bytes : (size == 2 ? HexGrouping.Hex16 : (size == 4 ? HexGrouping.Hex32 : HexGrouping.Hex64))
        let signedText   = Format.toString("%", .signed(raw, size))
        let unsignedText = Format.toString("%", raw)
        let hexText      = formatHexScalar(hexGrouping, raw)
        .addLine(hexName.toString(), hexText.toString())
        .addLine(unsignedName.toString(), unsignedText.toString())
        .addLine(signedName.toString(), signedText.toString())

        if size == 4
        {
            let floatText = Format.toString("%{g9}", cast #bit (f32) (cast(u32) raw))
            .addLine("float32", floatText.toString())
        }
        elif size == 8
        {
            let floatText = Format.toString("%{g15}", cast #bit (f64) raw)
            .addLine("float64", floatText.toString())
        }

        if size <= 2
        {
            let binaryText = size == 1 ? Format.toString("%{B08}", raw) : Format.toString("%{B016}", raw)
            .addLine("binary", binaryText.toString())
        }
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

        let size  = grid.valueSize()
        let start = grid.groupStart(grid.caret)
        .bytes = grid.doc.read(start, size)

        var offsetText: Array'u8
        offsetText.add('0'u8)
        offsetText.add('x'u8)
        appendHexDigits(&offsetText, grid.caret, grid.offsetDigits)
        .addLine("offset", @mkstring(offsetText.buffer!, offsetText.count))

        let length       = grid.selectionLength()
        let selectedText = Format.toString("% byte%", length, length == 1 ? "" : "s")
        .addLine("selection", selectedText.toString())
        .addBlank()

        if .bytes.isEmpty()
        {
            .addLine("value", HexInspectorNoValue)
            .invalidate()
            return
        }

        .addCurrentWidthValues()
        .invalidate()
    }

    mtd toggleByteOrder()
    {
        .grid.setBigEndian(!.grid.bigEndian)
        .orderButton.setText(.grid.bigEndian ? "Big endian" : "Little endian")
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
