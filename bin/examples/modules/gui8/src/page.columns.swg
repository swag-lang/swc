using Core, Gui, Pixel

func createColumnsPage(parent: *Wnd)
{
    let layout = getPageLayout(parent)

    let left = createPanel(parent, "File table", "Resizable columns, icon margins, alternating rows and stable first-column sizing.", layout.left)
    let files = ListCtrl.createMultiColumns(left, {18, 92, layout.left.width - 36, layout.left.height - 112})
    files.setFrameForm(.Round)
    files.frameFlags.add(.FocusBorder)
    files.selectionMode = .Multi
    files.iconSize      = 16
    addListFlags(files)
    files.addColumn("Name", 190, app.theme.getIcon24(.OpenFile, 16))
    files.addColumn("Kind", 110)
    files.addColumn("Owner", 120)
    files.addColumn("Changed", 110, app.theme.getIcon24(.Sort, 16))
    files.header.getItem(0).minWidth   = 130
    files.header.getItem(0).sizeable   = false
    files.header.getItem(3).iconMargin = true
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

    let right = createPanel(parent, "Sorted work queue", "Clicking headers changes sort order; the example opens on the priority column.", layout.right)
    let queue = ListCtrl.createMultiColumns(right, {18, 92, layout.right.width - 36, layout.right.height - 112})
    queue.setFrameForm(.Round)
    queue.selectionMode = .Single
    queue.iconSize      = 16
    queue.listFlags.add(.AlternateLines)
    queue.addColumn("Task", 180, app.theme.getIcon24(.Edit, 16))
    queue.addColumn("State", 110)
    queue.addColumn("Priority", 90, app.theme.getIcon24(.SortArrowDown, 16))
    queue.addColumn("Assignee", 120)
    for i in 16
    {
        let prio = 9 - (i % 9)
        let line = queue.createLine(Format.toString("review batch %", i + 1), sampleIcon(i + 3))
        line.setItem(1, i % 4 == 0 ? "blocked" : "ready")
        line.setItem(2, Format.toString("P%", prio))
        line.getItem(2).sortKey = Format.toString("%", prio)
        line.setItem(3, i % 2 == 0 ? "Ada" : "Mika")
    }
    queue.sort(2, false, true)
    queue.computeLayout()

    let bottom = createPanel(parent, "Wide columns", "Horizontal scrolling keeps the header and list content aligned.", layout.bottom)
    let wide = ListCtrl.createMultiColumns(bottom, {18, 92, layout.bottom.width - 36, layout.bottom.height - 112})
    wide.setFrameForm(.Square)
    wide.selectionMode = .Multi
    wide.iconSize      = 16
    wide.addColumn("Package", 180)
    wide.addColumn("Version", 120)
    wide.addColumn("Platform", 140)
    wide.addColumn("Artifacts", 220)
    wide.addColumn("Notes", 360)
    wide.horizontalExtent = 1020
    wide.listFlags.add(.HorzLines)
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
