using Core, Gui, Pixel

func createGridCell(parent: *Wnd, text: string, icon: ThemeIcons)->*Label
{
    with let label = Label.create(parent, text, {0, 0, 120, 42}, null, .WordWrap)
    {
        .setIcon(app.theme.icon(icon, 16))
        .setIconHorizontalAlignment(.Left)
        .setTextHorizontalAlignment(.Left)
        .setIconPadding({10, 0, 0, 0})
        .setTextPadding({34, 0, 10, 0})
    }

    raiseRegion(label)

    return label
}

func createWrapTile(parent: *Wnd, text: string, icon: ThemeIcons)
{
    let btn = PushButton.create(parent, text, {})
    btn.setForm(.Flat)
    btn.setIcon(app.theme.icon(icon, 16))
}

func createGridWrapPage(parent: *Wnd)
{
    let layout = getPageLayout(parent)

    let left = createPanel(parent,
                           "GridLayoutCtrl",
                           "Cells can span columns and rows while the grid recomputes direct child windows.",
                           layout.left)
    let grid = GridLayoutCtrl.create(left,
                                     4,
                                     3,
                                     Math.Rectangle{
                                         SectionInset,
                                         88,
                                         Math.max(layout.left.width - 2 * SectionInset, 320.0),
                                         Math.max(layout.left.height - 88, 180.0)})
    grid.backgroundStyle = .Transparent
    grid.flags.add(.EqualColumnWidths)
    grid.flags.add(.EqualRowHeights)
    grid.horizontalSpacing = 10
    grid.verticalSpacing   = 10
    grid.padding           = 4

    let timeline = createGridCell(grid, "Timeline span 2", .Sort)
    grid.setCell(timeline, 0, 0, 2, 1)
    let preview = createGridCell(grid, "Preview span 2x2", .Search)
    grid.setCell(preview, 2, 0, 2, 2)
    let props = createGridCell(grid, "Properties tall", .Options)
    grid.setCell(props, 0, 1, 1, 2)
    let notes = createGridCell(grid, "Notes", .Edit)
    grid.setCell(notes, 1, 1, 1, 1)
    let logs = createGridCell(grid, "Logs span 3", .Download)
    grid.setCell(logs, 1, 2, 3, 1)
    grid.computeLayout()

    let right = createPanel(parent,
                            "WrapLayoutCtrl",
                            "Tiles wrap to the next row as the pane narrows.",
                            layout.right)
    let wrap = WrapLayoutCtrl.create(right, Math.Rectangle{SectionInset, 88, layout.right.width - 2 * SectionInset, layout.right.height - 88})
    wrap.itemWidth  = 128
    wrap.itemHeight = 38
    wrap.spacing    = 10
    wrap.padding    = 4
    createWrapTile(wrap, "Search", .Search)
    createWrapTile(wrap, "Edit", .Edit)
    createWrapTile(wrap, "Picker", .Picker)
    createWrapTile(wrap, "Filter", .Filter)
    createWrapTile(wrap, "Copy", .Copy)
    createWrapTile(wrap, "Paste", .Paste)
    createWrapTile(wrap, "Export", .Export)
    createWrapTile(wrap, "Download", .Download)
    createWrapTile(wrap, "Link", .Link)
    createWrapTile(wrap, "Remove", .Remove)
    wrap.computeLayout()

    let bottom = createPanel(parent,
                             "Combined layouts",
                             "A grid is useful for stable dashboards; wrap is better for tool groups whose count or width changes.",
                             layout.bottom)
    let center = StackLayoutCtrl.create(bottom, .Center, Math.Rectangle{SectionInset, 88, layout.bottom.width - 2 * SectionInset, layout.bottom.height - 88})
    center.spacing = 14
    discard createChip(center, "Grid", .Sort)
    discard createChip(center, "Wrap", .Options)
    discard createChip(center, "Resize", .Update)
    center.computeLayout()
}
