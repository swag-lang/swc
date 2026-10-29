#global internal
#global namespace Viewers.MarkdownText

using Core, Gui

// The current Markdown section in the left margin of a wide reading column.
//
// The first two heading levels follow the current section. Long outlines scroll inside the
// available margin; the document keeps its full reading height.
struct ReadingMargin
{
    using wnd: Wnd

    late
    {
        view:    *Markdown.View
        outline: *DocumentOutline
        list:    *OutlineMargin
        scroll:  *ScrollWnd
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
            .dockStyle       = .Float
            .focusPolicy     = .Tab
            .hide()
        }

        with result.scroll = Wnd.create'ScrollWnd(result)
        {
            .dockStyle       = .Center
            .backgroundStyle = .Transparent
            .updateFlags(.DisableHorizontal | .TransparentBars)
        }

        with result.list = result.scroll.createView'OutlineMargin()
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

        view.sigScrolled += func|margin = result|(_)
        {
            margin.follow()
        }

        result.hookOnChildEvent = func|margin = result|(_, evt)
        {
            if evt is MouseEvent as mouse where mouse.kind == .Move or mouse.kind == .Enter do
                margin.scroll.revealScrollBars()
            return false
        }

        return result
    }

    // Keeps the active section visible without resetting a reader's independent outline scroll.
    mtd follow()
    {
        let view     = .view
        let client   = view.clientRect()
        let geometry = view.columnGeometry()

        if .entries.isEmpty() and not .outline.headings.isEmpty()
        {
            for heading, index in .outline.headings where heading.level <= 2
            {
                .entries.add(index)
                .list.titles.add(heading.title)
            }
        }

        // The heading being read is the last one starting above the top of the window.
        let offset = view.readingOffset()
        var active = Swag.U64.Max
        if offset != Swag.U64.Max
        {
            for index, row in .entries where .outline.headings[index].sourceOffset <= offset do
                active = row
        }

        if not .entries.isEmpty() and not view.hasUnloadedSource() and view.readingProgress() >= 1 do
            active = .entries.count - 1

        let changed = active != .list.active
        .list.setActive(active)
        let inset = view.themeMetrics().floating_Inset
        let top   = view.padding.y + view.documentStyle.topInset + inset
        let width = Math.min(geometry.x - 2 * Inset + inset, OutlineMargin.MaxWidth)
        .show(width >= OutlineMargin.MinWidth and not .entries.isEmpty())
        if not .isLocallyVisible() do
            return

        .setPosition(Math.Rectangle{Inset, top, width, Math.max(client.height - top - inset, 0)}, computeLayout: false)
        .applyLayout()
        .scroll.setScrollSize(0, .list.contentHeight())
        if changed and active < .entries.count
        {
            let y        = cast(f32, active) * OutlineMargin.EntryPitch
            let position = .scroll.scrollPosition().y
            if y < position do
                .scroll.setScrollPos(0, y)
            elif y + OutlineMargin.EntryPitch > position + .scroll.clientRect().height do
                .scroll.setScrollPos(0, y + OutlineMargin.EntryPitch - .scroll.clientRect().height)
        }

        .bringToFront()
    }
}

impl IWnd for ReadingMargin
{
    mtd impl onLayout() { .follow() }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed or evt.modifiers != .None or .entries.isEmpty()
        {
            evt.accepted = false
            return
        }

        let last = .entries.count - 1
        var row  = Math.min(.list.active, last)
        switch evt.key
        {
        case .Up:
            row = row ? row - 1 : 0

        case .Down:
            row = Math.min(row + 1, last)

        case .Home:
            row = 0

        case .End:
            row = last

        default:
            evt.accepted = false
            return
        }

        .list.sigChosen.call(.list, row)
        .scroll.revealScrollBars()
    }
}
