using Core, Gui, Pixel

func createHeaderBand(parent: *Wnd, rect: Math.Rectangle, title: string, round: bool, disabledClick: bool)
{
    let panel = createPanel(parent, title, "Standalone Header items can be resized, clamped, decorated and marked as sorted.", rect)
    let header = Header.create(panel, {18, 94, rect.width - 36, 34})
    header.form = round ? .Round : .Flat
    if disabledClick do
        header.headerFlags.remove(.Clickable)
    let name = header.addItem("Name", 190, app.theme.getIcon24(.OpenFile, 16))
    name.minWidth = 120
    name.maxWidth = 260
    let state = header.addItem("State", 120, app.theme.getIcon24(.Filter, 16))
    state.clickable = !disabledClick
    let size = header.addItem("Size", 92)
    size.sizeable = false
    discard header.addItem("Owner", Math.max(rect.width - 36 - 190 - 120 - 92, 140.0), app.theme.getIcon24(.Sort, 16))
    header.sortColumn = 1
    header.sortMark = round ? 1 : -1

    let rowY = 148.0
    for i in 4
    {
        let y = rowY + i * 34
        let icon = Label.create(panel, "", {34, y, 20, 24})
        icon.icon = sampleIcon(i, 16)
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
    let list = ListCtrl.createMultiColumns(bottom, {18, 92, layout.bottom.width - 36, layout.bottom.height - 112})
    list.setFrameForm(.Round)
    list.selectionMode = .Single
    list.iconSize = 16
    list.addColumn("Component", 220, app.theme.getIcon24(.Options, 16))
    list.addColumn("Kind", 130)
    list.addColumn("Column policy", 180)
    list.addColumn("Interaction", 180, app.theme.getIcon24(.Link, 16))
    list.header.getItem(0).minWidth = 160
    list.header.getItem(1).maxWidth = 160
    list.header.getItem(2).iconMargin = true
    list.header.sortColumn = 0
    list.header.sortMark = 1
    addListFlags(list)
    for i in 10
    {
        let line = list.createLine(Format.toString("header sample %", i + 1), sampleIcon(i + 1))
        line.setItem(1, i % 2 == 0 ? "table" : "tree")
        line.setItem(2, i % 3 == 0 ? "fixed first column" : "resizable")
        line.setItem(3, i % 2 == 0 ? "click to sort" : "drag separator")
    }
    list.sort(0, false, true)
    list.selectLine(0)
    list.computeLayout()
}
