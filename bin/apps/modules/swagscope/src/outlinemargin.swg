#global internal

using Core, Gui, Pixel

// The table of contents standing in a margin beside a document.
//
// An optional section label, then one entry per part, the one being read in the text ink on an
// Arc rule, the others faint; one faint rule may hold the entries together. It does not scroll
// with the document and never takes the keyboard. Choosing an entry emits `sigChosen` with its
// index. Markdown, PDF and HTML documents stand their outline in it.
struct OutlineMargin
{
    using wnd: Wnd

    titles:    Array'String
    label:     String     // Section label over the entries, or empty for none.
    rule:      bool       // Whether one faint rule holds the entries together.
    active:    u64 = Swag.U64.Max
    hot:       u64 = Swag.U64.Max
    sigChosen: SigArray'func||(*OutlineMargin, u64)
}

impl OutlineMargin
{
    // The narrowest room the margin shows in, the widest it gets, the pitch of an entry, the
    // height of the label and the weight of the rules.
    const MinWidth    = 160.0
    const MaxWidth    = 240.0
    const EntryPitch  = 32.0
    const LabelHeight = 32.0
    const RuleWeight  = 2.0

    func create(parent: *Wnd, id: WndId)->*OutlineMargin
    {
        with let result = Wnd.create'OutlineMargin(parent, id)
        {
            .backgroundStyle = .Transparent
            .focusPolicy     = .None
            .hide()
        }

        return result
    }

    // Returns the height the label and the entries take.
    mtd contentHeight()->f32 => (.label.isEmpty() ? 0 : LabelHeight) + cast(f32, .titles.count) * EntryPitch

    // Stands the margin at `x`, `y` over at most `room` of width, or hides it when the room is too
    // narrow or there is nothing to list.
    mtd place(x, y, room: f32)
    {
        let width = Math.min(room, MaxWidth)
        if width < MinWidth or .titles.isEmpty()
        {
            .hide()
            return
        }

        .setPosition(Math.Rectangle{Math.round(x), Math.round(y), Math.floor(width), .contentHeight()}, computeLayout: false)
        .show()
        .bringToFront()
        .invalidate()
    }

    // Marks the entry being read.
    mtd setActive(index: u64)
    {
        if index == .active do
            return
        .active = index
        .invalidate()
    }

    private mtd entryAt(pos: Math.Point)->u64
    {
        let top = .label.isEmpty() ? 0 : LabelHeight
        if pos.x < 0 or pos.y < top do
            return Swag.U64.Max
        let row = cast(u64, (pos.y - top) / EntryPitch)
        return row < .titles.count ? row : Swag.U64.Max
    }
}

impl IWnd for OutlineMargin
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let metrics = .themeMetrics()
        let client  = .clientRect()
        let font    = .theme().createDefaultFont(13)

        var top = 0.0'f32
        if not .label.isEmpty()
        {
            // The label in faint spaced capitals, as every section label of the charter.
            SectionLabel.paint(me, painter, Math.Rectangle{12, 0, Math.max(client.width - 12, 0), LabelHeight}, .label.toString())
            top = LabelHeight
        }

        if .rule do
            painter.fillRect(Math.Rectangle{0, top, metrics.separator_HairlineSize, client.height - top}, colors.line)
        for title, row in .titles
        {
            let rect = Math.Rectangle{0, top + cast(f32, row) * EntryPitch, client.width, EntryPitch}
            if row == .active do
                painter.fillRect(Math.Rectangle{0, rect.y, RuleWeight, rect.height}, colors.arc)
            let color = row == .active ? colors.text : (row == .hot ? colors.softText : colors.faintText)
            painter.pushClippingRect(rect)
            painter.drawString(12, font.opticalLineTop(rect.vertCenter()), title.toString(), font, color)
            painter.popClippingRect()
        }
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let row = .entryAt(.surfaceToLocal(evt.surfacePos))
        switch evt.kind
        {
        case .Move, .Enter:
            if row != .hot
            {
                .hot = row
                .invalidate()
            }

        case .Leave:
            .hot = Swag.U64.Max
            .invalidate()

        case .Pressed where evt.button == .Left and row < .titles.count:
            .sigChosen.call(me, row)

        default:
            evt.accepted = false
        }
    }
}
