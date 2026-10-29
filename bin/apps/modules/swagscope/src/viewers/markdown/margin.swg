#global internal
#global namespace Viewers.MarkdownText

using Core, Gui

// The current Markdown section in the left margin of a wide reading column.
//
// The margin lists the first two heading levels, with the section being read on an Arc rule over
// the faint rule of the list. It goes away when the margin is too narrow to hold it.
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
    // The air between the margin and the edge of the reading column.
    const Inset = 48.0

    func create(view: *Markdown.View, outline: *DocumentOutline)->*ReadingMargin
    {
        with let result = Wnd.create'ReadingMargin(view, Math.Rectangle{0, 0, 0, 0}, "scope.markdown.margin")
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
