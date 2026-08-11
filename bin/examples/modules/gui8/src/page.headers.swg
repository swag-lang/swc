using Core, Gui, Pixel

func createHeaderBand(parent: *Wnd, rect: Math.Rectangle, title: string, round: bool, disabledClick: bool)
{
    let panel  = createPanel(parent, title, "Standalone Header items can be resized, clamped, decorated and marked as sorted.", rect)
    let header = Header.create(panel, {18, 94, rect.width - 36, 34})
    header.form = round ? .Round : .Flat
    if disabledClick do
        header.updateFlags(remove: .Clickable)
    discard header.addColumn("Name", 190, app.theme.icon(.OpenFile, 16))
    header.setItemWidthLimits(0, 120, 260)
    let state = header.addColumn("State", 120, app.theme.icon(.Filter, 16))
    state.isClickable = !disabledClick
    let size = header.addColumn("Size", 92)
    size.isResizable = false
    discard header.addColumn("Owner", Math.max(rect.width - 36 - 190 - 120 - 92, 140.0), app.theme.icon(.Sort, 16))
    header.setSortIndicator(1, round ? .Ascending : .Descending)

    let rowY = 148.0
    for i in 4
    {
        let y    = rowY + i * 34
        let icon = Label.create(panel, "", {34, y, 20, 24})
        icon.setIcon(sampleIcon(i, 16))
        discard createText(panel, Format.toString("Header row %", i + 1), {60, y, 180, 24})
        discard createText(panel, i % 2 == 0 ? "ready" : "waiting", {250, y, 110, 24})
        discard createText(panel, Format.toString("% KB", 24 + i * 9), {370, y, 80, 24})
        discard createText(panel, i % 2 == 0 ? "runtime" : "editor", {470, y, 160, 24})
    }
}

func createHeadersPage(parent: *Wnd)
{
    let layout = getPageLayout(parent)

    createHeaderBand(parent, layout.left, "Round header", true, false)
    createHeaderBand(parent, layout.right, "Flat locked header", false, true)

    let bottom = createPanel(parent, "List-backed header", "ListCtrl owns a Header and keeps it synchronized with scrolling and column resizing.", layout.bottom)
    let list   = ListCtrl.createMultiColumns(bottom, {18, 92, layout.bottom.width - 36, layout.bottom.height - 112})
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
