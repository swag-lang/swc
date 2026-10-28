#global internal

using Core, Gui, Pixel

// How a listing writes an instruction.
enum ListingForm
{
    Readable     // As a reader writes it: `rax = [rcx + 0x8]`.
    Opcodes      // As the backend spells it: its identity, its opcode and its operands.
}

// One row of a [[ListingView]]: a line of a compared listing, or a line of plain compiler text.
struct ListingRow
{
    line:   const *Pipeline.ListingLine?     // The listing line, or null for a plain row.
    plain:  u64     // Index of the plain line, for a plain row.
    mark:   Pipeline.DiffMark
    number: u32 = Swag.U32.Max     // Place of the line in its stage, or `U32.Max` for none.
}

/*
The instructions of one stage, as text on the ground.

Each instruction and label takes a row, with its place in its stage in a faint gutter; the source
lines the compiler interleaves are shown on request, faint. Against the stage before it, a removed
row is struck out and faint, and an added row stands on the Arc selection ground with an Arc rule
at its left; the innermost loop is marked the same way when the view is asked to. A click chooses
a row, `Shift` extends the choice, and `Ctrl C` copies the chosen rows, or all of them.

When the compiler wrote no listing, the view shows its words instead, in their colors, or a faint
hint.
*/
struct ListingView
{
    using wnd: Wnd

    late scroll: *ScrollWnd     // Scrolling frame the view is the content of.

    difference: Pipeline.Difference            // The stage on screen, against the one before it.
    plain:      Array'Pipeline.ColoredText     // Lines of compiler text, shown when no listing is.
    rows:       Array'ListingRow
    hint:       bool     // Whether the plain lines are a hint, in the faint ink.
    form:       ListingForm
    showSource: bool                             // Whether the source lines are shown.
    showMarks:  bool = true                      // Whether removed rows show and added rows are marked.
    markLoop:   bool                             // Whether the innermost loop is marked.
    loopFirst:  const *Pipeline.ListingLine?     // Label opening the marked loop.
    loopLast:   const *Pipeline.ListingLine?     // Jump closing the marked loop.
    note:       String                           // Sentence written under the last row.
    anchor:     u64  = Swag.U64.Max              // Row the choice started from.
    caret:      u64  = Swag.U64.Max              // Row the choice ends on.
    opcodeChars, idChars: u64                    // Widest opcode and identity, in characters.
}

impl ListingView
{
    const Padding     = 4.0      // Air above the first row and under the last one.
    const NoteGap     = 24.0     // Air between the last row and the note.
    const LineSpacing = 8.0      // Air added to the height of the face, as the source editor has it.

    // Creates an empty listing in a scrolling frame of `parent`; the caller places `result.scroll`.
    func create(parent: *Wnd, id: WndId? = null)->*ListingView
    {
        with let scroll = Wnd.create'ScrollWnd(parent, "", {}, id)
        {
            .backgroundStyle = .Transparent
            .updateFlags(.TransparentBars)
        }

        with let result = scroll.createView'ListingView()
        {
            .scroll          = scroll
            .backgroundStyle = .Transparent
            .focusPolicy     = .Click
            .wndFlags        |= .NoScroll
        }

        return result
    }

    // Shows `after`, compared with `before` when there is one.
    mtd showListing(before: const *Pipeline.Snapshot?, after: const *Pipeline.Snapshot)
    {
        .difference = Pipeline.compare(before, after)
        .plain.clear()
        .hint      = false
        .loopFirst = null
        .loopLast  = null
        let loop = after.innermostLoop()
        if loop.first != Swag.U64.Max
        {
            .loopFirst = &after.lines[loop.first]
            .loopLast  = &after.lines[loop.last]
        }

        .rebuild()
    }

    // Shows what the compiler wrote, in its colors.
    mtd showOutput(text: string)
    {
        .clearListing()
        var output: CompilerOutput
        output.parse(text)
        var cursor = 0'u64
        let plain  = output.text.toString()
        var start  = 0'u64
        while start <= plain.count
        {
            var end = Utf8.indexOf(plain, '\n'rune, start)
            if end == Swag.U64.Max do
                end = plain.count
            var stop = end
            if stop > start and plain[stop - 1] == '\r' do
                stop -= 1
            .plain.add({})
            .plain.backPtr().append(&output, start, stop, &cursor)
            start = end + 1
        }

        .rebuild()
    }

    // Shows `text` as a faint hint, one row per line.
    mtd showHint(text: string)
    {
        .clearListing()
        .hint = true
        for line in Tokenize.split(text, '\n'u8, removeEmpty: false)
        {
            .plain.add({})
            .plain.backPtr().appendPlain(line)
        }

        .rebuild()
    }

    // Returns whether the view shows a listing rather than words.
    mtd isListing()->bool => .plain.isEmpty() and not .difference.lines.isEmpty()

    mtd setForm(form: ListingForm)
    {
        .form = form
        .rebuild()
    }

    mtd setShowSource(show: bool)
    {
        .showSource = show
        .rebuild()
    }

    mtd setShowMarks(show: bool)
    {
        .showMarks = show
        .rebuild()
    }

    mtd setMarkLoop(mark: bool)
    {
        .markLoop = mark
        .invalidate()
    }

    mtd setNote(note: string)
    {
        .note = note
        .rebuild()
    }

    // Returns the text of the chosen rows, or of every row when none is chosen, one per line.
    mtd copyText()->String
    {
        var result: #returntype
        var first = 0'u64
        var last  = .rows.count
        if .caret < .rows.count
        {
            first = Math.min(.anchor, .caret)
            last  = Math.max(.anchor, .caret) + 1
        }

        for index in first until last
        {
            result.append(.rowText(&.rows[index]))
            result.append("\n")
        }

        return result
    }

    // Returns the height of one row: the face's and the air the source editor adds to it.
    mtd rowHeight()->f32 => Math.ceil(.face().height + LineSpacing)

    private mtd face()->*Font => unwrap .theme().res.fontDefaultFs.regular

    private mtd clearListing()
    {
        .difference = {}
        .plain.clear()
        .loopFirst = null
        .loopLast  = null
        .hint      = false
    }

    // Lays the rows out again from what the view shows and how it shows it.
    private mtd rebuild()
    {
        .rows.clear()
        .anchor      = Swag.U64.Max
        .caret       = Swag.U64.Max
        .opcodeChars = 0
        .idChars     = 0
        for index in .plain.count do
            .rows.add(ListingRow{plain: index})

        for line in .difference.lines
        {
            if line.line.kind == .Source and not .showSource do
                continue
            if line.mark == .Removed and not .showMarks do
                continue
            .rows.add(ListingRow{line.line, 0, .showMarks ? line.mark : Pipeline.DiffMark.Same, line.number})
            if line.line.kind == .Instruction
            {
                .opcodeChars = Math.max(.opcodeChars, line.line.opcode.text.length)
                .idChars     = Math.max(.idChars, line.line.id.length)
            }
        }

        .measure()
        .invalidate()
    }

    // Gives the scrolling frame the size of everything the rows and the note write.
    private mtd measure()
    {
        let font  = .face()
        var width = 0'f32
        for row in .rows
        {
            let text = .rowText(row)
            width = Math.max(width, .textLeft() + Painter.measureString(text, font).width)
        }

        var height = 2 * Padding + cast(f32, .rows.count) * .rowHeight()
        if not .note.isEmpty() do
            height += NoteGap + .noteFont().height
        .scroll.setScrollSize(Math.ceil(width), Math.ceil(height))
    }

    // Returns the words a row writes, as one string.
    private mtd rowText(row: const *ListingRow)->String
    {
        var result: #returntype
        if not row.line
        {
            result.append(.plain[row.plain].text)
            return result
        }

        if .form == .Opcodes and row.line.kind == .Instruction
        {
            result.append(row.line.id)
            for .idChars + 1 - row.line.id.length do
                result.append(" ")
            result.append(row.line.opcode.text)
            for .opcodeChars + 1 - row.line.opcode.text.length do
                result.append(" ")
            result.append(row.line.operands.text)
            return result
        }

        result.append(row.line.readable.text)
        return result
    }

    private mtd charWidth()->f32  => Painter.measureString("0", .face()).width
    private mtd noteFont()->*Font => .theme().createDefaultFont(.themeMetrics().defaultFontSize)

    // Width of the gutter: the widest place, never fewer than three digits, one blank advance
    // before it and two after, as the source editor numbers its lines.
    private mtd gutterWidth()->f32
    {
        if not .plain.isEmpty() do
            return 0
        var digits = 1'u64
        var last   = Math.max(.rows.count, 1)
        while last >= 10
        {
            last   /= 10
            digits += 1
        }

        return cast(f32, Math.max(digits, 3) + 3) * .charWidth()
    }

    private mtd textLeft()->f32 => .gutterWidth()

    // Returns the row under `pos`, a point of the view, or `U64.Max`.
    private mtd rowAt(pos: Math.Point)->u64
    {
        let y = pos.y + .scrollPos.y - Padding
        if y < 0 do
            return Swag.U64.Max
        let index = cast(u64, y / .rowHeight())
        return index < .rows.count ? index : Swag.U64.Max
    }

    // Returns `color` made readable on the ground of the view, or the text ink for no color.
    private mtd inkOf(color: Color)->Color
    {
        if color.argb == 0 do
            return .themeColors().text
        var result = color
        result.ensureContrast(.themeColors().ground, 4.5)
        return result
    }

    // Writes `text` from `x`, run by run, in `flat` or else in each run's color, and returns where
    // it ends.
    private mtd paintText(painter: *Painter, x, top: f32, text: const *Pipeline.ColoredText, font: *Font, flat: Color)->f32
    {
        let plain = text.text.toString()
        var left  = x
        for run in text.runs
        {
            let piece = plain[run.start until run.end]
            let color = flat.argb != 0 ? flat : .inkOf(run.color)
            painter.drawString(left, top, piece, font, color)
            left += Painter.measureString(piece, font).width
        }

        return left
    }

    // Paints one row whose top is `top`, in the view's own coordinates.
    private mtd paintRow(painter: *Painter, index: u64, top: f32, inLoop: bool)
    {
        let row    = &.rows[index]
        let colors = .themeColors()
        let font   = .face()
        let width  = .clientRect().width
        let height = .rowHeight()
        let rule   = Math.max(2.0'f32, .themeMetrics().separator_HairlineSize * 2)
        let chosen = .caret < .rows.count and
                     index >= Math.min(.anchor, .caret) and
                     index <= Math.max(.anchor, .caret)
        let textTop = top + (height - font.height) * 0.5
        let x       = .textLeft() - .scrollPos.x

        if chosen or row.mark == .Added or inLoop do
            painter.fillRect(Math.Rectangle{0, top, width, height}, colors.selection)
        if row.mark == .Added or inLoop do
            painter.fillRect(Math.Rectangle{0, top, rule, height}, colors.arc)

        if not row.line
        {
            let ink = .hint ? colors.faintText : Color{}
            discard .paintText(painter, x, textTop, &.plain[row.plain], font, ink)
            return
        }

        // The gutter: the place of the row, a removed row's old place after a minus, a plus for an
        // added row.
        let numberRight = .gutterWidth() - 2 * .charWidth()
        if row.mark == .Added
        {
            painter.drawString(numberRight - Painter.measureString("+", font).width, textTop, "+", font, colors.arc)
        }
        elif row.number != Swag.U32.Max
        {
            let number = Format.toString("%", row.number)
            painter.drawString(numberRight - Painter.measureString(number, font).width, textTop, number, font, colors.faintText)
            if row.mark == .Removed do
                painter.drawString(.charWidth(), textTop, "−", font, colors.faintText)
        }

        let removed = row.mark == .Removed
        let flat    = removed ? colors.faintText : Color{}
        var end     = x
        if row.line.kind == .Source
        {
            let italic = unwrap .theme().res.fontDefaultFs.italic
            end = .paintText(painter, x, textTop, &row.line.readable, italic, colors.faintText)
        }
        elif row.line.kind == .Instruction and .form == .Opcodes
        {
            // The identity, the opcode and the operands each take a column.
            let charWidth  = .charWidth()
            let opcodeLeft = x + cast(f32, .idChars + 1) * charWidth
            painter.drawString(x, textTop, row.line.id, font, colors.faintText)
            discard .paintText(painter, opcodeLeft, textTop, &row.line.opcode, font, flat)
            end = .paintText(painter, opcodeLeft + cast(f32, .opcodeChars + 1) * charWidth, textTop, &row.line.operands, font, flat)
        }
        else
        {
            end = .paintText(painter, x, textTop, &row.line.readable, font, flat)
        }

        // A removed row is struck out through the middle of its words.
        if removed
        {
            let middle = painter.snapToDeviceY(top + height * 0.5)
            painter.fillRect(Math.Rectangle{x, middle, end - x, painter.hairline(.themeMetrics().separator_HairlineSize)}, colors.faintText)
        }
    }
}

impl IWnd for ListingView
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let height  = .rowHeight()
        let client  = .clientRect()
        let first   = cast(u64, Math.max(0'f32, (.scrollPos.y - Padding) / height))

        // The loop is marked from its label to its jump back, wherever its rows are.
        var inLoop = false
        if .markLoop and .loopFirst
        {
            for index in Math.min(first, .rows.count)
            {
                if .rows[index].line == .loopFirst do
                    inLoop = true
                if .rows[index].line == .loopLast do
                    inLoop = false
            }
        }

        var index = first
        while index < .rows.count
        {
            let top = Padding + cast(f32, index) * height - .scrollPos.y
            if top > client.bottom() do
                break
            let line = .rows[index].line
            if .markLoop and .loopFirst and line == .loopFirst do
                inLoop = true
            .paintRow(painter, index, top, inLoop)
            if .markLoop and line and line == .loopLast do
                inLoop = false
            index += 1
        }

        if not .note.isEmpty()
        {
            let font = .noteFont()
            let top  = Padding + cast(f32, .rows.count) * height + NoteGap - .scrollPos.y
            painter.drawString(.textLeft() - .scrollPos.x, top, .note, font, .themeColors().softText)
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        if evt.kind != .Pressed or evt.button != .Left
        {
            evt.accepted = false
            return
        }

        let index = .rowAt(.surfaceToLocal(evt.surfacePos))
        if index == Swag.U64.Max
        {
            .anchor = Swag.U64.Max
            .caret  = Swag.U64.Max
        }
        else
        {
            if not evt.modifiers.has(.Shift) or .anchor >= .rows.count do
                .anchor = index
            .caret = index
        }

        .setFocus()
        .invalidate()
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        let control = evt.modifiers.has(.Control)
        let page    = Math.max(1'f32, .clientRect().height - .rowHeight())
        let scroll  = .scroll.scrollPosition()
        switch evt.key
        {
        case .C where control:
            Clipboard.setString(.copyText())

        case .A where control:
            .anchor = 0
            .caret  = .rows.count ? .rows.count - 1 : Swag.U64.Max
            .invalidate()

        case .Up:
            .scroll.setScrollPos(scroll.x, scroll.y - .rowHeight())

        case .Down:
            .scroll.setScrollPos(scroll.x, scroll.y + .rowHeight())

        case .PageUp:
            .scroll.setScrollPos(scroll.x, scroll.y - page)

        case .PageDown:
            .scroll.setScrollPos(scroll.x, scroll.y + page)

        case .Home:
            .scroll.setScrollPos(scroll.x, 0)

        case .End:
            .scroll.setScrollPos(scroll.x, .scroll.scrollSize.y)

        default:
            evt.accepted = false
        }
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .ThemeChanged do
            .measure()
        .wnd.IWnd.onNotifyEvent(evt)
    }
}
