using Core, Gui, Pixel

func createGridCell(parent: *Wnd, text: string, icon: ThemeIcons24)->*Label
{
    let label = Label.create(parent, text, {0, 0, 120, 42}, null, .WordWrap)
    label.backgroundStyle = .Window
    label.icon = app.theme.getIcon24(icon, 16)
    label.horzAlignmentIcon = .Left
    label.horzAlignmentText = .Left
    label.paddingIcon = {10, 0, 0, 0}
    label.paddingText = {34, 0, 10, 0}
    return label
}

func createWrapTile(parent: *Wnd, text: string, icon: ThemeIcons24)
{
    let btn = PushButton.create(parent, text, {})
    btn.form = .Flat
    btn.icon = app.theme.getIcon24(icon, 16)
}

func createGridWrapPage(parent: *Wnd)
{
    let layout = getPageLayout(parent)

    let left = createPanel(parent, "GridLayoutCtrl", "Cells can span columns and rows while the grid recomputes direct child windows.", layout.left)
    let grid = GridLayoutCtrl.create(left, 4, 3, {18, 92, Math.max(layout.left.width - 36, 320.0), Math.max(layout.left.height - 112, 180.0)})
    grid.backgroundStyle = .Dialog
    grid.gridLayoutFlags.add(.AdaptColWidth)
    grid.gridLayoutFlags.add(.AdaptRowHeight)
    grid.spacingHorz = 10
    grid.spacingVert = 10
    grid.padding = 4

    let timeline = createGridCell(grid, "Timeline span 2", .Sort)
    grid.setColRowChild(timeline, 0, 0, 2, 1)
    let preview = createGridCell(grid, "Preview span 2x2", .Search)
    grid.setColRowChild(preview, 2, 0, 2, 2)
    let props = createGridCell(grid, "Properties tall", .Options)
    grid.setColRowChild(props, 0, 1, 1, 2)
    let notes = createGridCell(grid, "Notes", .Edit)
    grid.setColRowChild(notes, 1, 1, 1, 1)
    let logs = createGridCell(grid, "Logs span 3", .Download)
    grid.setColRowChild(logs, 1, 2, 3, 1)
    grid.computeLayout()

    let right = createPanel(parent, "WrapLayoutCtrl", "Tiles wrap to the next row as the pane narrows.", layout.right)
    let wrap = WrapLayoutCtrl.create(right, {18, 92, layout.right.width - 36, layout.right.height - 112})
    wrap.wrapWidth = 128
    wrap.wrapHeight = 38
    wrap.spacing = 10
    wrap.padding = 4
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

    let bottom = createPanel(parent, "Combined layouts", "A grid is useful for stable dashboards; wrap is better for tool groups whose count or width changes.", layout.bottom)
    let center = StackLayoutCtrl.create(bottom, .HorzCenterVertCenter, {18, 92, layout.bottom.width - 36, layout.bottom.height - 112})
    center.spacing = 14
    discard createChip(center, "Grid", .Sort)
    discard createChip(center, "Wrap", .Options)
    discard createChip(center, "Resize", .Update)
    center.computeLayout()
}
