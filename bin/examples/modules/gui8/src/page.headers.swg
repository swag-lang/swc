using Core, Gui, Pixel

func createHeaderBand(parent: *Wnd, rect: Math.Rectangle, title: string, round: bool, disabledClick: bool)
{
    let panel = createPanel(parent,
                            title,
                            "Standalone Header items can be resized, clamped, decorated and marked as sorted.",
                            rect)
    const Inset = 18.0
    let width  = rect.width - Inset * 2
    let header = Header.create(panel, {Inset, 84, width, 34})
    header.form = round ? .Round : .Flat
    if disabledClick do
        header.updateFlags(remove: .Clickable)

    discard header.addColumn("Name", width * 0.34, app.theme.icon(.OpenFile, 16))
    header.setItemWidthLimits(0, 106, 220)
    discard header.addColumn("State", width * 0.23, app.theme.icon(.Filter, 16))
    let size = header.addColumn("Size", width * 0.16)
    size.isResizable = false
    discard header.addColumn("Owner", width * 0.24)
    header.setSortIndicator(1, round ? .Ascending : .Descending)

    let rows = Wnd.create'Wnd(panel, {Inset, 126, width, 118})
    rows.hookOnEvent = func|header|(view, event)
    {
        if event is PaintEvent as paint
        {
            let painter = paint.paintContext.painter
            let font    = view.theme().createDefaultFont(view.themeMetrics().defaultFontSize)
            let colors  = view.themeColors()

            for row in 4
            {
                let cells = [Format.toString("Sample %", row + 1),
                             String.from(row % 2 == 0 ? "Ready" : "Waiting"),
                             Format.toString("% KB", 24 + row * 9),
                             String.from(row % 2 == 0 ? "Runtime" : "Editor")]

                for text, column in cells
                {
                    let index = cast(u32, column)
                    let x     = header.itemPositionAt(index)
                    let y     = row * 28.0
                    let cell  = Math.Rectangle{x, y, header.itemWidthAt(index), 28}
                    painter.pushClippingRect(cell)
                    painter.drawString(x + 8, y + 5, text.toString(), font, colors.text)
                    painter.popClippingRect()
                }
            }
        }

        return false
    }

    header.sigLayoutChanged += func|rows|(_)
    {
        rows.invalidate()
    }

    header.sigColumnClicked += func|header|(_, column)
    {
        let ascending = header.sortColumn != column or header.sortDirection != .Ascending
        header.setSortIndicator(column, ascending ? .Ascending : .Descending)
    }
}

func createHeadersPage(parent: *Wnd)
{
    let layout = getPageLayout(parent)

    createHeaderBand(parent, layout.left, "Round header", true, false)
    createHeaderBand(parent, layout.right, "Flat locked header", false, true)

    let bottom = createPanel(parent,
                             "List-backed header",
                             "ListCtrl owns a Header and keeps it synchronized with scrolling and column resizing.",
                             layout.bottom)
    let list = ListCtrl.createMultiColumns(bottom,
                                           Math.Rectangle{18, 76, layout.bottom.width - 36, layout.bottom.height - 94})
    list.setFrameForm(.Round)
    list.setSelectionMode(.Single)
    list.setIconSize(16)
    list.addColumn("Component", 220, app.theme.icon(.Options, 16))
    list.addColumn("Kind", 130)
    list.addColumn("Column policy", 180)
    list.addColumn("Interaction", 180, app.theme.icon(.Link, 16))
    list.header.setItemWidthLimits(0, minimum: 160)
    list.header.setItemWidthLimits(1, maximum: 160)
    list.header.itemAt(2).reservesIconSpace = true
    list.header.setSortIndicator(0, .Ascending)
    addListFlags(list)
    for i in 10
    {
        let line = list.createLine(Format.toString("header sample %", i + 1), sampleIcon(i + 1))
        line.setItem(1, i % 2 == 0 ? "table" : "tree")
        line.setItem(2, i % 3 == 0 ? "fixed first column" : "resizable")
        line.setItem(3, i % 2 == 0 ? "click to sort" : "drag separator")
    }

    list.sort(0, false, true)
    list.computeLayout()
}
