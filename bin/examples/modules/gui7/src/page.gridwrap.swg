using Core, Gui, Pixel

func createGridCell(parent: *Wnd, text: string)->*FrameWnd
{
    let frame = Wnd.create'FrameWnd(parent, {})
    frame.setFrameForm(.Round)
    frame.setFrameFlags(.Borders)
    let view = frame.createView'Wnd()
    let label = createText(view, text, {10, 8, 160, 24})
    label.icon = app.theme.getIcon24(.Sort, 16)
    label.horzAlignmentIcon = .Left
    label.horzAlignmentText = .Left
    label.paddingText.x = 22
    discard createHelpText(view, "span-aware cell", {10, 36, 180, 40})
    return frame
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

    let left = createPanel(parent, "GridLayoutCtrl", "Cells can span columns and rows while the grid adapts row and column sizes to its rectangle.", layout.left)
    let grid = GridLayoutCtrl.create(left, 4, 3, {18, 92, layout.left.width - 36, layout.left.height - 112})
    grid.gridLayoutFlags |= .AdaptColWidth | .AdaptRowHeight
    grid.spacingHorz = 10
    grid.spacingVert = 10
    grid.padding = 4

    let timeline = createGridCell(grid, "Timeline")
    grid.setColRowChild(timeline, 0, 0, 2, 1)
    let preview = createGridCell(grid, "Preview")
    grid.setColRowChild(preview, 2, 0, 2, 2)
    let props = createGridCell(grid, "Properties")
    grid.setColRowChild(props, 0, 1, 1, 2)
    let notes = createGridCell(grid, "Notes")
    grid.setColRowChild(notes, 1, 1, 1, 1)
    let logs = createGridCell(grid, "Logs")
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
