#global internal
#global namespace Viewers.MarkdownText

using Core, Gui, Pixel

// The table of contents in the left margin of a wide window, and the reading progress as an Arc
// thread along the top edge of the document.
//
// Both stand over the document without scrolling with it: the margin lists the headings of the
// first two levels, the one being read on an Arc rule over the faint rule of the list, and goes
// away when the margin is too narrow to hold it; the thread is as long as the share of the
// document already read.
struct ReadingMargin
{
    using wnd: Wnd

    late
    {
        view:    *Markdown.View
        outline: *DocumentOutline
        thread:  *Wnd
    }

    entries: Array'u64     // Indices of the headings the margin lists.
    active:  u64 = Swag.U64.Max
    hot:     u64 = Swag.U64.Max
}

impl ReadingMargin
{
    // The width the margin needs before it shows, the widest it gets, its air from the edge of
    // the window, the pitch of an entry and the weight of the threads.
    const MinWidth   = 180.0
    const MaxWidth   = 240.0
    const Inset      = 48.0
    const EntryPitch = 32.0
    const RuleWeight = 2.0

    func create(view: *Markdown.View, outline: *DocumentOutline)->*ReadingMargin
    {
        with let result = Wnd.create'ReadingMargin(view, "scope.markdown.margin")
        {
            .view            = view
            .outline         = outline
            .backgroundStyle = .Transparent
            .hide()
        }

        with result.thread = Wnd.create'Wnd(view, Math.Rectangle{0, 0, 0, RuleWeight}, "scope.markdown.progress")
        {
            .backgroundStyle = .Transparent
            .wndFlags.add(.Disabled)
            .hookOnEvent     = func|margin = result|(wnd, evt)->bool
            {
                if evt is PaintEvent as paint
                {
                    paint.paintContext.painter.fillRect(wnd.clientRect(), margin.themeColors().arc)
                    return true
                }

                return false
            }
        }

        view.sigScrolled += func|margin = result|(_) { margin.follow() }
        return result
    }

    // Places the margin and the thread for the size, the scroll and the headings in force.
    mtd follow()
    {
        let view     = .view
        let client   = view.clientRect()
        let geometry = view.columnGeometry()

        // The thread: the share of the document already read.
        let progress = view.readingProgress()
        .thread.setPosition(Math.Rectangle{0, 0, Math.round(client.width * progress), RuleWeight}, computeLayout: false)
        .thread.show(progress > 0)
        .thread.bringToFront()
        .thread.invalidate()

        .entries.clear()
        for heading, index in .outline.headings where heading.level <= 2 do
            .entries.add(index)

        let width = Math.min(geometry.x - 2 * Inset + 24, MaxWidth)
        if width < MinWidth or .entries.isEmpty()
        {
            .hide()
            return
        }

        // The heading being read is the last one starting above the top of the window.
        let offset = view.readingOffset()
        .active = Swag.U64.Max
        if offset != Swag.U64.Max
        {
            for index, row in .entries where .outline.headings[index].sourceOffset <= offset do
                .active = row
        }

        let height = cast(f32, .entries.count) * EntryPitch
        .setPosition(Math.Rectangle{Inset, client.y + view.documentStyle.topInset + 16, width, height}, computeLayout: false)
        .show()
        .bringToFront()
        .invalidate()
    }

    private mtd entryAt(pos: Math.Point)->u64
    {
        if pos.x < 0 or pos.y < 0 do
            return Swag.U64.Max
        let row = cast(u64, pos.y / EntryPitch)
        return row < .entries.count ? row : Swag.U64.Max
    }
}

impl IWnd for ReadingMargin
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let painter = evt.paintContext.painter
        let colors  = .themeColors()
        let client  = .clientRect()
        let font    = .theme().createDefaultFont(13)

        // One faint rule holds the list together; the entry being read takes it in Arc.
        painter.fillRect(Math.Rectangle{0, 0, .themeMetrics().separator_HairlineSize, client.height}, colors.line)
        for index, row in .entries
        {
            let rect = Math.Rectangle{0, cast(f32, row) * EntryPitch, client.width, EntryPitch}
            if row == .active do
                painter.fillRect(Math.Rectangle{0, rect.y, RuleWeight, rect.height}, colors.arc)
            let heading = &.outline.headings[index]
            let color   = row == .active ? colors.text : (row == .hot ? colors.softText : colors.faintText)
            painter.pushClippingRect(rect)
            painter.drawString(14, font.opticalLineTop(rect.vertCenter()), heading.title, font, color)
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

        case .Pressed where evt.button == .Left and row < .entries.count:
            discard .view.revealHeading(.outline.headings[.entries[row]].sourceOffset)
            .follow()

        default:
            evt.accepted = false
        }
    }
}
