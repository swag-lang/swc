using Core, Gui, Pixel

func createColumnsPage(parent: *Wnd)
{
    let layout = getPageLayout(parent)

    let left  = createPanel(parent, "File table", "Resizable columns, icon margins, alternating rows and stable first-column sizing.", layout.left)
    let files = ListCtrl.createMultiColumns(left, {18, 92, layout.left.width - 36, layout.left.height - 112})
    files.setFrameForm(.Round)
    files.frameFlags.add(.FocusBorder)
    files.setSelectionMode(.Multi)
    files.setIconSize(16)
    addListFlags(files)
    files.addColumn("Name", 190, app.theme.icon(.OpenFile, 16))
    files.addColumn("Kind", 110)
    files.addColumn("Owner", 120)
    files.addColumn("Changed", 110, app.theme.icon(.Sort, 16))
    files.header.setItemWidthLimits(0, minimum: 130)
    files.header.itemAt(0).isResizable       = false
    files.header.itemAt(3).reservesIconSpace = true
    for i in 18
    {
        let line = files.createLine(Format.toString("asset_%.swg", i + 1), sampleIcon(i))
        line.setItem(1, i % 3 == 0 ? "source" : "resource")
        line.setItem(2, i % 2 == 0 ? "design" : "runtime")
        line.setItem(3, Format.toString("2026-06-%", 10 + (i % 12)))
        if i % 5 == 0 do
            line.canCheck = true
    }

    files.computeLayout()

    let right      = createPanel(parent, "Sorted work queue", "Clicking headers changes sort order; the example opens on the priority column.", layout.right)
    with let queue = ListCtrl.createMultiColumns(right, {18, 92, layout.right.width - 36, layout.right.height - 112})
    {
        .setFrameForm(.Round)
        .setSelectionMode(.Single)
        .setIconSize(16)
        .updateFlags(.AlternateLines)
        .addColumn("Task", 180, app.theme.icon(.Edit, 16))
        .addColumn("State", 110)
        .addColumn("Priority", 90, app.theme.icon(.ChevronDown, 16))
        .addColumn("Assignee", 120)
    }

    for i in 16
    {
        let prio = 9 - (i % 9)
        let line = queue.createLine(Format.toString("review batch %", i + 1), sampleIcon(i + 3))
        line.setItem(1, i % 4 == 0 ? "blocked" : "ready")
        line.setItem(2, Format.toString("P%", prio))
        line.itemAt(2).sortKey = Format.toString("%", prio)
        line.setItem(3, i % 2 == 0 ? "Ada" : "Mika")
    }

    queue.sort(2, false, true)
    queue.computeLayout()

    let bottom    = createPanel(parent, "Wide columns", "Horizontal scrolling keeps the header and list content aligned.", layout.bottom)
    with let wide = ListCtrl.createMultiColumns(bottom, {18, 92, layout.bottom.width - 36, layout.bottom.height - 112})
    {
        .setFrameForm(.Square)
        .setSelectionMode(.Multi)
        .setIconSize(16)
        .addColumn("Package", 180)
        .addColumn("Version", 120)
        .addColumn("Platform", 140)
        .addColumn("Artifacts", 220)
        .addColumn("Notes", 360)
        .setHorizontalExtent(1020)
        .updateFlags(.HorizontalLines)
    }

    for i in 12
    {
        let line = wide.createLine(Format.toString("module.%", i + 1), sampleIcon(i + 5))
        line.setItem(1, Format.toString("1.%.%", i % 5, i % 9))
        line.setItem(2, i % 2 == 0 ? "x86_64 windows" : "x86_64 linux")
        line.setItem(3, "dll, pdb, import lib")
        line.setItem(4, "long metadata column used to exercise header scrolling")
    }

    wide.computeLayout()
}
