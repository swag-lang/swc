#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Stretching includes separators and padding, and never invents horizontal overflow.
#test
{
    var host: Testing.HeadlessHost
    host.setup(700, 360)
    let list = ListCtrl.createMultiColumns(&host.root, {0, 0, 600, 300})
    list.addColumn("Name", 220)
    list.addColumn("Modified", 110)
    list.addColumn("Size", 72)
    list.updateFlags(.StretchFirstColumn)
    list.header.hide()

    for count in [0, 2, 30, 0]
    {
        list.clear()
        for count do
            discard list.createLine("Folder")
        for width in [600.0, 420.0, 660.0]
        {
            list.resize(width, 300)
            list.computeLayout()
            host.root.applyLayout()
            Swag.require(not list.scrollWnd.showBarH, Format.toString("rows %, width %, content %, viewport %, first %, vertical %", count, width, list.header.contentWidth(), list.listView.position.width, list.header.itemWidthAt(0), list.scrollWnd.showBarV))
            list.scrollWnd.setScrollPos(100, 0)
            Swag.require(list.scrollWnd.scrollPosition().x == 0)
        }
    }
}

var ListCtrlHeadlessSelCount: u32

func listCtrlHeadlessSel(_: *ListCtrl)
{
    ListCtrlHeadlessSelCount += 1
}

#test
{
    var root: ListLine
    Swag.require(not root.canExpand())

    root.forceExpandMark = true
    Swag.require(root.canExpand())

    root.forceExpandMark = false
    let child = root.lines.allocate()
    child.parent = &root
    child.level  = 1
    root.lines.add(child)

    Swag.require(root.canExpand())
    Swag.require(root.isParentOf(child))
    Swag.require(not child.isParentOf(&root))

    let grandChild = child.lines.allocate()
    grandChild.parent = child
    grandChild.level  = 2
    child.lines.add(grandChild)

    Swag.require(root.isParentOf(grandChild))
    Swag.require(child.isParentOf(grandChild))
    Swag.require(not grandChild.isParentOf(child))
}

#test
{
    var line: ListLine
    let item0 = line.setItem(0, "Name")
    Swag.require(line.items.count == 1)
    Swag.require(line.itemAt(0) == item0)
    Swag.require(item0.name == "Name")
    Swag.require(item0.column == 0)

    let item1 = line.setItem(1, "Kind")
    Swag.require(line.items.count == 2)
    Swag.require(line.itemAt(1) == item1)
    Swag.require(item1.name == "Kind")
    Swag.require(item1.column == 1)

    let updated = line.setItem(0, "Renamed")
    Swag.require(updated == item0)
    Swag.require(line.items.count == 2)
    Swag.require(line.itemAt(0).name == "Renamed")
}

#test
{
    var list: ListCtrl

    let root0     = list.createLine("root0")
    let child0    = list.createLine("child0", parentLine: root0)
    let root1     = list.createLine("root1")
    let separator = list.createLine("separator")
    separator.separator = true
    let root2 = list.createLine("root2")

    Swag.require(root0.index == 0)
    Swag.require(child0.index == 1)
    Swag.require(root1.index == 2)
    Swag.require(separator.index == 3)
    Swag.require(root2.index == 4)
    Swag.require(list.lineCount() == 4)
    Swag.require(list.lineAt(0) == root0)
    Swag.require(list.lineAt(1) == root1)
    Swag.require(list.lineAt(2) == separator)
    Swag.require(list.lineAt(3) == root2)
    Swag.require(list.idxLineToIdxList.find(root0.index).value == 0)
    Swag.require(list.idxLineToIdxList.tryFind(child0.index) == null)
    Swag.require(list.idxLineToIdxList.find(root1.index).value == 1)
    Swag.require(list.idxLineToIdxList.find(separator.index).value == 2)
    Swag.require(list.idxLineToIdxList.find(root2.index).value == 3)
}

#test
{
    var list: ListCtrl
    list.setSelectionMode(.Multi)

    let root0       = list.createLine("root0")
    let hiddenChild = list.createLine("hidden", parentLine: root0)
    let root1       = list.createLine("root1")
    let separator   = list.createLine("separator")
    separator.separator = true
    let root2 = list.createLine("root2")

    list.selectLines(3, 0)
    Swag.require(list.isLineSelected(0))
    Swag.require(list.isLineSelected(1))
    Swag.require(not list.isLineSelected(2))
    Swag.require(list.isLineSelected(3))

    let selected = list.selectedLines()
    Swag.require(selected.count == 3)
    Swag.require(selected[0] == root0)
    Swag.require(selected[1] == root1)
    Swag.require(selected[2] == root2)

    list.selModel.select(hiddenChild.index)
    let selectedVisible = list.selectedLines()
    Swag.require(selectedVisible.count == 3)

    root1.canCheck = true
    list.setLineChecked(root1, notify: false)
    list.checkModel.select(hiddenChild.index)
    let checked = list.checkedLines()
    Swag.require(checked.count == 1)
    Swag.require(checked[0] == root1)
}

#test
{
    var list: ListCtrl
    list.setSelectionMode(.Single)

    discard list.createLine("root0")
    discard list.createLine("root1")
    discard list.createLine("root2")

    list.selectLines(0, 2)
    Swag.require(not list.isLineSelected(0))
    Swag.require(not list.isLineSelected(1))
    Swag.require(list.isLineSelected(2))

    list.selectLines(2, 0, false)
    Swag.require(list.selModel.isEmpty())
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 180)
    let list = ListCtrl.createSimple(&host.root, {0, 0, 220, 160})
    list.setVirtualCount(6)
    list.setSelectionMode(.Multi)

    list.selectLines(4, 2)
    Swag.require(not list.isLineSelected(1))
    Swag.require(list.isLineSelected(2))
    Swag.require(list.isLineSelected(3))
    Swag.require(list.isLineSelected(4))
    Swag.require(not list.isLineSelected(5))
    Swag.require(list.selectedLines().isEmpty())

    list.selectLine(3, false)
    Swag.require(not list.isLineSelected(3))

    list.clear()
    Swag.require(not list.isVirtual)
    Swag.require(list.lineCount() == 0)
    Swag.require(list.selModel.isEmpty())

    let line = list.createLine("real")
    Swag.require(line.index == 0)
    Swag.require(list.lineCount() == 1)
}

// A cell reports where its text is drawn, which is what a marker drawn over the list points at.
// The rectangle starts after everything the row puts before its wording, and it is the same walk
// painting makes: the column, the row's margins, its hierarchy indent, its disclosure mark and
// its icon each take their share of the leading edge.
#test
{
    var host: Testing.HeadlessHost
    host.setup(420, 320)

    let list = ListCtrl.createMultiColumns(&host.root, {0, 0, 400, 300})
    list.addColumn("Name", 200)
    list.addColumn("Kind", 180)
    host.root.applyLayout()

    let first = list.createLine("alpha")
    first.setItem(1, "one")
    let second = list.createLine("beta")
    second.setItem(1, "two")

    let name = list.cellTextRect(1, 0)
    let kind = list.cellTextRect(1, 1)
    Swag.require(not name.isEmpty() and not kind.isEmpty())

    // The second row sits one row height down, and the second column starts after the first.
    Swag.require(Math.isEqualEpsilon(name.y, list.lineHeight(), 0.5))
    Swag.require(Math.isEqualEpsilon(name.height, list.lineHeight(), 0.5))
    Swag.require(kind.x >= 200 and kind.x > name.x)

    // A row keeps its wording clear of its own leading edge, and of the icon space it reserves.
    Swag.require(name.x > 0)

    // A nested row starts its wording one indent further in than a row at the root, whatever
    // disclosure mark its parent had to reserve beside it. A child takes its icon margin from
    // its parent, so the parent states it to compare like with like.
    first.iconMargin = true
    discard list.createLine("gamma", parentLine: first)
    list.expand(first)
    let childText = list.cellTextRect(1, 0)
    let rootText  = list.cellTextRect(2, 0)
    Swag.require(Math.isEqualEpsilon(childText.x - rootText.x, list.indentWidth, 0.5))

    // Nothing is laid out beyond the rows, and no column beyond the header.
    Swag.require(list.cellTextRect(list.lineCount(), 0).isEmpty())
    Swag.require(list.cellTextRect(0, 7).isEmpty())
}

// A virtual list has no row object to measure, so the geometry asks the owner to fill one, the
// same way painting does.
#test
{
    var host: Testing.HeadlessHost
    host.setup(420, 320)

    let list = ListCtrl.createSimple(&host.root, {0, 0, 400, 300})
    list.onFillVirtualLine = func(_, line, index)
    {
        if line do
            discard line.setItem(0, Format.toString("row %", index).toString())
    }

    list.setVirtualCount(4)
    host.root.applyLayout()

    let row = list.cellTextRect(2, 0)
    Swag.require(not row.isEmpty())
    Swag.require(Math.isEqualEpsilon(row.y, 2 * list.lineHeight(), 0.5))
}

// Expanding/collapsing a parent line changes the visible line count.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 320)
    let list  = ListCtrl.createSimple(&host.root, {0, 0, 200, 300})
    let root0 = list.createLine("root0")
    list.createLine("childA", parentLine: root0)
    list.createLine("childB", parentLine: root0)
    list.createLine("root1")

    Swag.require(list.lineCount() == 2)
    Swag.require(root0.canExpand())
    Swag.require(not root0.expanded)

    list.expand(root0)
    Swag.require(root0.expanded)
    Swag.require(list.lineCount() == 4)

    list.collapse(root0)
    Swag.require(not root0.expanded)
    Swag.require(list.lineCount() == 2)
}

// Single-selection: selecting another line deselects the previous one.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 320)
    ListCtrlHeadlessSelCount = 0

    let list = ListCtrl.createSimple(&host.root, {0, 0, 200, 300})
    Swag.require(list.iconSize == 16)
    Swag.require(list.lineHeight() >= 24)
    list.sigSelectionChanged += &listCtrlHeadlessSel
    list.createLine("a")
    list.createLine("b")

    Swag.require(list.lineCount() == 2)
    Swag.require(not list.isLineSelected(0))

    list.selectLine(0)
    Swag.require(list.isLineSelected(0))
    Swag.require(not list.isLineSelected(1))

    list.selectLine(1)
    Swag.require(not list.isLineSelected(0))
    Swag.require(list.isLineSelected(1))

    list.unselectAll()
    Swag.require(not list.isLineSelected(1))
    Swag.require(ListCtrlHeadlessSelCount == 3)
}

// clear() removes all lines.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 320)
    let list = ListCtrl.createSimple(&host.root, {0, 0, 200, 300})
    list.createLine("a")
    list.createLine("b")
    list.createLine("c")
    Swag.require(list.lineCount() == 3)

    list.clear()
    Swag.require(list.lineCount() == 0)
}

// Clicking a line selects it; clicking another (Single mode) moves the selection.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 320)
    ListCtrlHeadlessSelCount = 0

    let list = ListCtrl.createSimple(&host.root, {0, 0, 200, 300})
    list.sigSelectionChanged += &listCtrlHeadlessSel
    list.createLine("a")
    list.createLine("b")
    list.createLine("c")

    let lh = list.lineHeight()
    let vs = list.listView.surfaceRect()

    host.click(Math.Point{vs.x + 30, vs.y + lh * 0.5})
    Swag.require(list.isLineSelected(0))
    Swag.require(not list.isLineSelected(1))

    host.click(Math.Point{vs.x + 30, vs.y + lh * 2 + lh * 0.5})
    Swag.require(list.isLineSelected(2))
    Swag.require(not list.isLineSelected(0))
    Swag.require(ListCtrlHeadlessSelCount >= 2)
}

// Multi-selection: Ctrl+click toggles individual lines.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 320)
    let list = ListCtrl.createSimple(&host.root, {0, 0, 200, 300})
    list.setSelectionMode(.Multi)
    list.createLine("a")
    list.createLine("b")
    list.createLine("c")

    let lh = list.lineHeight()
    let vs = list.listView.surfaceRect()

    host.click(Math.Point{vs.x + 30, vs.y + lh * 0.5})
    host.click(Math.Point{vs.x + 30, vs.y + lh * 2 + lh * 0.5}, Input.MouseButton.Left, Input.KeyModifiers.Control)

    Swag.require(list.isLineSelected(0))
    Swag.require(not list.isLineSelected(1))
    Swag.require(list.isLineSelected(2))
}

// Arrow keys move the selection up and down.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 320)
    let list = ListCtrl.createSimple(&host.root, {0, 0, 200, 300})
    list.createLine("a")
    list.createLine("b")
    list.createLine("c")
    host.focus(list.listView)

    host.keyPress(Input.Key.Down)
    Swag.require(list.isLineSelected(0))

    host.keyPress(Input.Key.Down)
    Swag.require(list.isLineSelected(1))
    Swag.require(not list.isLineSelected(0))

    host.keyPress(Input.Key.Up)
    Swag.require(list.isLineSelected(0))
    Swag.require(not list.isLineSelected(1))
}

// A list says where a drop would land, and shows it.
//
// The outer quarter of a row is the gap next to it and the middle half is the row itself, which
// is what makes an insertion and a drop onto a row distinguishable while the pointer moves.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 320)
    let list = ListCtrl.createSimple(&host.root, {0, 0, 200, 300})
    list.createLine("a")
    list.createLine("b")
    list.createLine("c")

    let lh = list.lineHeight()
    let vs = list.listView.surfaceRect()

    let top = list.dropMarkAt(Math.Point{vs.x + 30, vs.y + lh * 0.05})
    Swag.require(top.index == 0 and top.mark == ListDropMark.Before)

    let middle = list.dropMarkAt(Math.Point{vs.x + 30, vs.y + lh * 0.5})
    Swag.require(middle.index == 0 and middle.mark == ListDropMark.On)

    let bottom = list.dropMarkAt(Math.Point{vs.x + 30, vs.y + lh * 0.95})
    Swag.require(bottom.index == 0 and bottom.mark == ListDropMark.After)

    let second = list.dropMarkAt(Math.Point{vs.x + 30, vs.y + lh * 1.5})
    Swag.require(second.index == 1 and second.mark == ListDropMark.On)

    // Past the last row is the gap after it, so a list is appended to by aiming at its empty part.
    let past = list.dropMarkAt(Math.Point{vs.x + 30, vs.y + lh * 10})
    Swag.require(past.index == 2 and past.mark == ListDropMark.After)

    // Outside the rows entirely is no answer at all.
    Swag.require(list.dropMarkAt(Math.Point{vs.x - 20, vs.y + lh * 0.5}).mark == ListDropMark.None)
}

// Showing the mark is what a window does with that answer, and clearing it is what every leave
// and every drop has to do.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 320)
    let list = ListCtrl.createSimple(&host.root, {0, 0, 200, 300})
    list.createLine("a")
    list.createLine("b")

    Swag.require(list.dropMark == ListDropMark.None)
    Swag.require(list.dropMarkIndex == Swag.U32.Max)

    list.setDropMark(1, .Before)
    Swag.require(list.dropMark == ListDropMark.Before)
    Swag.require(list.dropMarkIndex == 1)

    list.clearDropMark()
    Swag.require(list.dropMark == ListDropMark.None)
    Swag.require(list.dropMarkIndex == Swag.U32.Max)

    // A mark of `None` keeps no row, whatever index it was given.
    list.setDropMark(1, .None)
    Swag.require(list.dropMarkIndex == Swag.U32.Max)
}

// An empty list answers the gap before a row that is not there, so a drop still has somewhere
// to say it will land.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 320)
    let list = ListCtrl.createSimple(&host.root, {0, 0, 200, 300})

    let vs   = list.listView.surfaceRect()
    let mark = list.dropMarkAt(Math.Point{vs.x + 30, vs.y + 10})
    Swag.require(mark.index == 0 and mark.mark == ListDropMark.Before)

    // Outside it is still no answer at all, so the two cases stay apart.
    Swag.require(list.dropMarkAt(Math.Point{vs.x - 20, vs.y + 10}).mark == ListDropMark.None)

    // And the mark it is asked to show is drawn against a row that is not there.
    list.setDropMark(mark.index, mark.mark)
    host.pump()
    Swag.require(list.dropMark == ListDropMark.Before)
}

// The selected-row state follows the slight corner carried by the theme's selection tile, and
// fills the row up to its leading edge with no rule along it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 100)
    host.root.backgroundStyle = .View

    let list = ListCtrl.createSimple(&host.root, {20, 20, 180, 60})
    list.setSelectionMode(.Single)
    discard list.createLine("selected")
    list.selectLine(0)
    host.focus(list.listView)
    host.finishAnimations()

    let rect    = list.listView.surfaceRect()
    let image   = host.render()
    let corner  = image.pixelColor(cast(s32, rect.x), cast(s32, rect.y))
    let center  = image.pixelColor(cast(s32, rect.x) + 8, cast(s32, rect.y) + 8)
    let leading = image.pixelColor(cast(s32, rect.x) + 1, cast(s32, (rect.y + list.lineHeight() * 0.5)))
    Swag.require(center != host.theme.colors.view_Bk)
    Swag.require(leading == center)
    Swag.require(corner != center)
}

// The keyboard focus follows its row when rows appear, disappear, or move above it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 180)

    let list  = ListCtrl.createSimple(&host.root, {0, 0, 220, 160})
    let root0 = list.createLine("b-root")
    discard list.createLine("child0", parentLine: root0)
    discard list.createLine("child1", parentLine: root0)
    let root1 = list.createLine("a-root")

    list.setFocusedIndex(1, ensureVisible: false)
    Swag.require(list.focusedLine() == root1)
    list.expand(root0)
    Swag.require(list.focusedLine() == root1)
    list.collapse(root0)
    Swag.require(list.focusedLine() == root1)
    list.sort(0)
    Swag.require(list.focusedLine() == root1)
}
