#global internal
#global namespace Viewers.MarkdownText

using Core, Gui, Pixel

// The reading progress of a document as an Arc thread along the top edge of the window, and its
// table of contents in the left margin of a wide window.
//
// The thread is as long as the share of the document already read; the margin lists the headings
// of the first two levels, the one being read on an Arc rule over the faint rule of the list, and
// goes away when the margin is too narrow to hold it. Neither scrolls with the document.
struct ReadingMargin
{
    using wnd: Wnd

    late
    {
        view:    *Markdown.View
        outline: *DocumentOutline
        list:    *OutlineMargin
    }

    entries: Array'u64     // Indices of the headings the margin lists.
}

impl ReadingMargin
{
    // The air between the margin and the edge of the window, and the weight of the thread.
    const Inset      = 48.0
    const RuleWeight = 2.0

    func create(view: *Markdown.View, outline: *DocumentOutline)->*ReadingMargin
    {
        with let result = Wnd.create'ReadingMargin(view, Math.Rectangle{0, 0, 0, RuleWeight}, "scope.markdown.progress")
        {
            .view            = view
            .outline         = outline
            .backgroundStyle = .Transparent
            .wndFlags.add(.Disabled)
            .hide()
        }

        with result.list = OutlineMargin.create(view, "scope.markdown.margin")
        {
            .rule      = true
            .sigChosen += func|margin = result|(_, row)
            {
                if row < margin.entries.count
                {
                    discard margin.view.revealHeading(margin.outline.headings[margin.entries[row]].sourceOffset)
                    margin.follow()
                }
            }
        }

        view.sigScrolled += func|margin = result|(_) { margin.follow() }
        return result
    }

    // Places the thread and the margin for the size, the scroll and the headings in force.
    mtd follow()
    {
        let view     = .view
        let client   = view.clientRect()
        let geometry = view.columnGeometry()

        // The thread: the share of the document already read.
        let progress = view.readingProgress()
        .setPosition(Math.Rectangle{0, 0, Math.round(client.width * progress), RuleWeight}, computeLayout: false)
        .show(progress > 0)
        .bringToFront()
        .invalidate()

        .entries.clear()
        .list.titles.clear()
        for heading, index in .outline.headings where heading.level <= 2
        {
            .entries.add(index)
            .list.titles.add(heading.title)
        }

        // The heading being read is the last one starting above the top of the window.
        let offset = view.readingOffset()
        var active = Swag.U64.Max
        if offset != Swag.U64.Max
        {
            for index, row in .entries where .outline.headings[index].sourceOffset <= offset do
                active = row
        }

        .list.setActive(active)
        .list.place(Inset, client.y + view.documentStyle.topInset + 16, geometry.x - 2 * Inset + 24)
    }
}

impl IWnd for ReadingMargin
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        evt.paintContext.painter.fillRect(.clientRect(), .themeColors().arc)
    }
}
