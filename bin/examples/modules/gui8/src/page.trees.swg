using Core, Gui, Pixel

func addSimpleTreeBranch(tree: *ListCtrl, rootName: string, rootIcon: ThemeIcons24, childCount: s32)->*ListLine
{
    let root = tree.createLine(rootName, app.theme.getIcon24(rootIcon, 16))
    for i in childCount
    {
        let child = tree.createLine(Format.toString("node %.%", rootName, i + 1), sampleIcon(i), parentLine: root)
        for j in 3 do
            discard tree.createLine(Format.toString("leaf %.%.%", rootName, i + 1, j + 1), sampleIcon(j + i), parentLine: child)
    }
    return root
}

func createTreesPage(parent: *Wnd)
{
    let layout = getPageLayout(parent)

    let left = createPanel(parent, "Simple tree", "A ListCtrl with child lines becomes a compact tree view.", layout.left)
    let tree = ListCtrl.createSimple(left, {18, 92, layout.left.width - 36, layout.left.height - 112})
    tree.setFrameForm(.Round)
    tree.frameFlags.add(.FocusBorder)
    tree.selectionMode = .Single
    tree.iconSize      = 16
    let docs = addSimpleTreeBranch(tree, "Documents", .OpenFile, 4)
    let assets = addSimpleTreeBranch(tree, "Assets", .Picker, 3)
    discard addSimpleTreeBranch(tree, "Build", .Options, 3)
    tree.expand(docs)
    tree.expand(assets)
    tree.computeLayout()

    let right = createPanel(parent, "Tree table", "Nested rows can still carry column data and sortable headers.", layout.right)
    let table = ListCtrl.createMultiColumns(right, {18, 92, layout.right.width - 36, layout.right.height - 112})
    table.setFrameForm(.Round)
    table.selectionMode      = .Multi
    table.iconSize           = 16
    table.iconMarginFirstCol = false
    addListFlags(table)
    table.addColumn("Item", 210, app.theme.getIcon24(.SortArrowRight, 16))
    table.addColumn("State", 110)
    table.addColumn("Size", 90)
    table.addColumn("Owner", 100)
    for i in 5
    {
        let root = table.createLine(Format.toString("folder %", i + 1), sampleIcon(i))
        root.setItem(1, "open")
        root.setItem(2, Format.toString("% KB", 40 + i * 7))
        root.setItem(3, i % 2 == 0 ? "core" : "tools")
        for j in 4
        {
            let child = table.createLine(Format.toString("file %.%", i + 1, j + 1), sampleIcon(i + j), parentLine: root)
            child.setItem(1, j % 2 == 0 ? "ready" : "dirty")
            child.setItem(2, Format.toString("% KB", 12 + j * 3))
            child.setItem(3, j % 2 == 0 ? "api" : "ui")
            child.canCheck = true
        }
        if i < 3 do
            table.expand(root)
    }
    table.sort(0, false, true)
    table.computeLayout()

    let bottom = createPanel(parent, "Collapsed branch states", "Tree controls preserve expansion, selection and check state independently.", layout.bottom)
    let stateTree = ListCtrl.createSimple(bottom, {18, 92, layout.bottom.width - 36, layout.bottom.height - 112})
    stateTree.setFrameForm(.Square)
    stateTree.selectionMode = .Multi
    stateTree.iconSize      = 16
    stateTree.listFlags.add(.ForceMarginExpandMark)
    let openRoot = addSimpleTreeBranch(stateTree, "Expanded branch", .Plus, 2)
    let closedRoot = addSimpleTreeBranch(stateTree, "Collapsed branch", .Minimize, 2)
    stateTree.expand(openRoot)
    openRoot.canCheck   = true
    closedRoot.canCheck = true
    stateTree.checkModel.select(openRoot.index, true)
    stateTree.computeLayout()
}
