#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

var ListCtrlHeadlessSelCount: u32

func listCtrlHeadlessSel(list: *ListCtrl)
{
    discard list
    ListCtrlHeadlessSelCount += 1
}

#test
{
    var root: ListLine
    Swag.assert(!root.canExpand())

    root.forceExpandMark = true
    Swag.assert(root.canExpand())

    root.forceExpandMark = false
    let child = root.lines.allocate()
    child.parent = &root
    child.level  = 1
    root.lines.add(child)

    Swag.assert(root.canExpand())
    Swag.assert(root.isParentOf(child))
    Swag.assert(!child.isParentOf(&root))

    let grandChild = child.lines.allocate()
    grandChild.parent = child
    grandChild.level  = 2
    child.lines.add(grandChild)

    Swag.assert(root.isParentOf(grandChild))
    Swag.assert(child.isParentOf(grandChild))
    Swag.assert(!grandChild.isParentOf(child))
}

#test
{
    var line: ListLine
    let item0 = line.setItem(0, "Name")
    Swag.assert(line.items.count == 1)
    Swag.assert(line.itemAt(0) == item0)
    Swag.assert(item0.name == "Name")
    Swag.assert(item0.column == 0)

    let item1 = line.setItem(1, "Kind")
    Swag.assert(line.items.count == 2)
    Swag.assert(line.itemAt(1) == item1)
    Swag.assert(item1.name == "Kind")
    Swag.assert(item1.column == 1)

    let updated = line.setItem(0, "Renamed")
    Swag.assert(updated == item0)
    Swag.assert(line.items.count == 2)
    Swag.assert(line.itemAt(0).name == "Renamed")
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

    Swag.assert(root0.index == 0)
    Swag.assert(child0.index == 1)
    Swag.assert(root1.index == 2)
    Swag.assert(separator.index == 3)
    Swag.assert(root2.index == 4)
    Swag.assert(list.lineCount() == 4)
    Swag.assert(list.lineAt(0) == root0)
    Swag.assert(list.lineAt(1) == root1)
    Swag.assert(list.lineAt(2) == separator)
    Swag.assert(list.lineAt(3) == root2)
    Swag.assert(list.idxLineToIdxList.find(root0.index).value == 0)
    Swag.assert(list.idxLineToIdxList.tryFind(child0.index) == null)
    Swag.assert(list.idxLineToIdxList.find(root1.index).value == 1)
    Swag.assert(list.idxLineToIdxList.find(separator.index).value == 2)
    Swag.assert(list.idxLineToIdxList.find(root2.index).value == 3)
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
    Swag.assert(list.isLineSelected(0))
    Swag.assert(list.isLineSelected(1))
    Swag.assert(!list.isLineSelected(2))
    Swag.assert(list.isLineSelected(3))

    let selected = list.selectedLines()
    Swag.assert(selected.count == 3)
    Swag.assert(selected[0] == root0)
    Swag.assert(selected[1] == root1)
    Swag.assert(selected[2] == root2)

    list.selModel.select(hiddenChild.index)
    let selectedVisible = list.selectedLines()
    Swag.assert(selectedVisible.count == 3)

    root1.canCheck = true
    list.setLineChecked(root1, notify: false)
    list.checkModel.select(hiddenChild.index)
    let checked = list.checkedLines()
    Swag.assert(checked.count == 1)
    Swag.assert(checked[0] == root1)
}

#test
{
    var list: ListCtrl
    list.setSelectionMode(.Single)

    discard list.createLine("root0")
    discard list.createLine("root1")
    discard list.createLine("root2")

    list.selectLines(0, 2)
    Swag.assert(!list.isLineSelected(0))
    Swag.assert(!list.isLineSelected(1))
    Swag.assert(list.isLineSelected(2))

    list.selectLines(2, 0, false)
    Swag.assert(list.selModel.isEmpty())
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 180)
    defer host.shutdown()
    let list = ListCtrl.createSimple(&host.root, {0, 0, 220, 160})
    list.setVirtualCount(6)
    list.setSelectionMode(.Multi)

    list.selectLines(4, 2)
    Swag.assert(!list.isLineSelected(1))
    Swag.assert(list.isLineSelected(2))
    Swag.assert(list.isLineSelected(3))
    Swag.assert(list.isLineSelected(4))
    Swag.assert(!list.isLineSelected(5))
    Swag.assert(list.selectedLines().isEmpty())

    list.selectLine(3, false)
    Swag.assert(!list.isLineSelected(3))

    list.clear()
    Swag.assert(!list.isVirtual)
    Swag.assert(list.lineCount() == 0)
    Swag.assert(list.selModel.isEmpty())

    let line = list.createLine("real")
    Swag.assert(line.index == 0)
    Swag.assert(list.lineCount() == 1)
}

// A cell reports where its text is drawn, which is what a marker drawn over the list points at.
// The rectangle starts after everything the row puts before its wording, and it is the same walk
// painting makes: the column, the row's margins, its hierarchy indent, its disclosure mark and
// its icon each take their share of the leading edge.
#test
{
    var host: Testing.HeadlessHost
    host.setup(420, 320)
    defer host.shutdown()

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
    Swag.assert(!name.isEmpty() and !kind.isEmpty())

    // The second row sits one row height down, and the second column starts after the first.
    Swag.assert(Math.isEqualEpsilon(name.y, list.lineHeight(), 0.5))
    Swag.assert(Math.isEqualEpsilon(name.height, list.lineHeight(), 0.5))
    Swag.assert(kind.x >= 200 and kind.x > name.x)

    // A row keeps its wording clear of its own leading edge, and of the icon space it reserves.
    Swag.assert(name.x > 0)

    // A nested row starts its wording one indent further in than a row at the root, whatever
    // disclosure mark its parent had to reserve beside it. A child takes its icon margin from
    // its parent, so the parent states it to compare like with like.
    first.iconMargin = true
    discard list.createLine("gamma", parentLine: first)
    list.expand(first)
    let childText = list.cellTextRect(1, 0)
    let rootText  = list.cellTextRect(2, 0)
    Swag.assert(Math.isEqualEpsilon(childText.x - rootText.x, list.indentWidth, 0.5))

    // Nothing is laid out beyond the rows, and no column beyond the header.
    Swag.assert(list.cellTextRect(list.lineCount(), 0).isEmpty())
    Swag.assert(list.cellTextRect(0, 7).isEmpty())
}

// A virtual list has no row object to measure, so the geometry asks the owner to fill one, the
// same way painting does.
#test
{
    var host: Testing.HeadlessHost
    host.setup(420, 320)
    defer host.shutdown()

    let list = ListCtrl.createSimple(&host.root, {0, 0, 400, 300})
    list.onFillVirtualLine = func(owner, line, index)
    {
        discard owner
        if line do
            discard line.setItem(0, Format.toString("row %", index).toString())
    }

    list.setVirtualCount(4)
    host.root.applyLayout()

    let row = list.cellTextRect(2, 0)
    Swag.assert(!row.isEmpty())
    Swag.assert(Math.isEqualEpsilon(row.y, 2 * list.lineHeight(), 0.5))
}

// Expanding/collapsing a parent line changes the visible line count.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 320)
    defer host.shutdown()
    let list  = ListCtrl.createSimple(&host.root, {0, 0, 200, 300})
    let root0 = list.createLine("root0")
    list.createLine("childA", parentLine: root0)
    list.createLine("childB", parentLine: root0)
    list.createLine("root1")

    Swag.assert(list.lineCount() == 2)
    Swag.assert(root0.canExpand())
    Swag.assert(!root0.expanded)

    list.expand(root0)
    Swag.assert(root0.expanded)
    Swag.assert(list.lineCount() == 4)

    list.collapse(root0)
    Swag.assert(!root0.expanded)
    Swag.assert(list.lineCount() == 2)
}

// Single-selection: selecting another line deselects the previous one.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 320)
    defer host.shutdown()
    ListCtrlHeadlessSelCount = 0

    let list = ListCtrl.createSimple(&host.root, {0, 0, 200, 300})
    Swag.assert(list.iconSize == 16)
    Swag.assert(list.lineHeight() >= 24)
    list.sigSelectionChanged += &listCtrlHeadlessSel
    list.createLine("a")
    list.createLine("b")

    Swag.assert(list.lineCount() == 2)
    Swag.assert(!list.isLineSelected(0))

    list.selectLine(0)
    Swag.assert(list.isLineSelected(0))
    Swag.assert(!list.isLineSelected(1))

    list.selectLine(1)
    Swag.assert(!list.isLineSelected(0))
    Swag.assert(list.isLineSelected(1))

    list.unselectAll()
    Swag.assert(!list.isLineSelected(1))
    Swag.assert(ListCtrlHeadlessSelCount == 3)
}

// clear() removes all lines.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 320)
    defer host.shutdown()
    let list = ListCtrl.createSimple(&host.root, {0, 0, 200, 300})
    list.createLine("a")
    list.createLine("b")
    list.createLine("c")
    Swag.assert(list.lineCount() == 3)

    list.clear()
    Swag.assert(list.lineCount() == 0)
}

// Clicking a line selects it; clicking another (Single mode) moves the selection.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 320)
    defer host.shutdown()
    ListCtrlHeadlessSelCount = 0

    let list = ListCtrl.createSimple(&host.root, {0, 0, 200, 300})
    list.sigSelectionChanged += &listCtrlHeadlessSel
    list.createLine("a")
    list.createLine("b")
    list.createLine("c")

    let lh = list.lineHeight()
    let vs = list.listView.surfaceRect()

    host.click({vs.x + 30, vs.y + lh * 0.5})
    Swag.assert(list.isLineSelected(0))
    Swag.assert(!list.isLineSelected(1))

    host.click({vs.x + 30, vs.y + lh * 2 + lh * 0.5})
    Swag.assert(list.isLineSelected(2))
    Swag.assert(!list.isLineSelected(0))
    Swag.assert(ListCtrlHeadlessSelCount >= 2)
}

// Multi-selection: Ctrl+click toggles individual lines.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 320)
    defer host.shutdown()
    let list = ListCtrl.createSimple(&host.root, {0, 0, 200, 300})
    list.setSelectionMode(.Multi)
    list.createLine("a")
    list.createLine("b")
    list.createLine("c")

    let lh = list.lineHeight()
    let vs = list.listView.surfaceRect()

    host.click({vs.x + 30, vs.y + lh * 0.5})
    host.click({vs.x + 30, vs.y + lh * 2 + lh * 0.5}, Input.MouseButton.Left, Input.KeyModifiers.Control)

    Swag.assert(list.isLineSelected(0))
    Swag.assert(!list.isLineSelected(1))
    Swag.assert(list.isLineSelected(2))
}

// Arrow keys move the selection up and down.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 320)
    defer host.shutdown()
    let list = ListCtrl.createSimple(&host.root, {0, 0, 200, 300})
    list.createLine("a")
    list.createLine("b")
    list.createLine("c")
    host.focus(list.listView!)

    host.keyPress(Input.Key.Down)
    Swag.assert(list.isLineSelected(0))

    host.keyPress(Input.Key.Down)
    Swag.assert(list.isLineSelected(1))
    Swag.assert(!list.isLineSelected(0))

    host.keyPress(Input.Key.Up)
    Swag.assert(list.isLineSelected(0))
    Swag.assert(!list.isLineSelected(1))
}

// A list says where a drop would land, and shows it.
//
// The outer quarter of a row is the gap next to it and the middle half is the row itself, which
// is what makes an insertion and a drop onto a row distinguishable while the pointer moves.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 320)
    defer host.shutdown()
    let list = ListCtrl.createSimple(&host.root, {0, 0, 200, 300})
    list.createLine("a")
    list.createLine("b")
    list.createLine("c")

    let lh = list.lineHeight()
    let vs = list.listView.surfaceRect()

    let top = list.dropMarkAt({vs.x + 30, vs.y + lh * 0.05})
    Swag.assert(top.index == 0 and top.mark == ListDropMark.Before)

    let middle = list.dropMarkAt({vs.x + 30, vs.y + lh * 0.5})
    Swag.assert(middle.index == 0 and middle.mark == ListDropMark.On)

    let bottom = list.dropMarkAt({vs.x + 30, vs.y + lh * 0.95})
    Swag.assert(bottom.index == 0 and bottom.mark == ListDropMark.After)

    let second = list.dropMarkAt({vs.x + 30, vs.y + lh * 1.5})
    Swag.assert(second.index == 1 and second.mark == ListDropMark.On)

    // Past the last row is the gap after it, so a list is appended to by aiming at its empty part.
    let past = list.dropMarkAt({vs.x + 30, vs.y + lh * 10})
    Swag.assert(past.index == 2 and past.mark == ListDropMark.After)

    // Outside the rows entirely is no answer at all.
    Swag.assert(list.dropMarkAt({vs.x - 20, vs.y + lh * 0.5}).mark == ListDropMark.None)
}

// Showing the mark is what a window does with that answer, and clearing it is what every leave
// and every drop has to do.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 320)
    defer host.shutdown()
    let list = ListCtrl.createSimple(&host.root, {0, 0, 200, 300})
    list.createLine("a")
    list.createLine("b")

    Swag.assert(list.dropMark == ListDropMark.None)
    Swag.assert(list.dropMarkIndex == Swag.U32.Max)

    list.setDropMark(1, .Before)
    Swag.assert(list.dropMark == ListDropMark.Before)
    Swag.assert(list.dropMarkIndex == 1)

    list.clearDropMark()
    Swag.assert(list.dropMark == ListDropMark.None)
    Swag.assert(list.dropMarkIndex == Swag.U32.Max)

    // A mark of `None` keeps no row, whatever index it was given.
    list.setDropMark(1, .None)
    Swag.assert(list.dropMarkIndex == Swag.U32.Max)
}

// An empty list answers the gap before a row that is not there, so a drop still has somewhere
// to say it will land.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 320)
    defer host.shutdown()
    let list = ListCtrl.createSimple(&host.root, {0, 0, 200, 300})

    let vs   = list.listView.surfaceRect()
    let mark = list.dropMarkAt({vs.x + 30, vs.y + 10})
    Swag.assert(mark.index == 0 and mark.mark == ListDropMark.Before)

    // Outside it is still no answer at all, so the two cases stay apart.
    Swag.assert(list.dropMarkAt({vs.x - 20, vs.y + 10}).mark == ListDropMark.None)

    // And the mark it is asked to show is drawn against a row that is not there.
    list.setDropMark(mark.index, mark.mark)
    host.pump()
    Swag.assert(list.dropMark == ListDropMark.Before)
}

// The selected-row state follows the slight corner carried by the theme's selection tile.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 100)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.root.backgroundStyle = .View
    host.notify(.ThemeChanged)

    let list = ListCtrl.createSimple(&host.root, {20, 20, 180, 60})
    list.setSelectionMode(.Single)
    discard list.createLine("selected")
    list.selectLine(0)
    host.focus(list.listView!)
    host.finishAnimations()

    let rect    = list.listView.surfaceRect()
    let image   = host.render()
    let corner  = image.pixelColor(cast(s32) rect.x, cast(s32) rect.y)
    let center  = image.pixelColor(cast(s32) rect.x + 8, cast(s32) rect.y + 8)
    let leading = image.pixelColor(cast(s32) rect.x + 1, cast(s32) (rect.y + list.lineHeight() * 0.5))
    Swag.assert(center == host.theme.colors.listItem_FocusSelectedBk)
    Swag.assert(leading == host.theme.colors.listItem_FocusSelectedBk)
    Swag.assert(leading != host.theme.colors.activeRail)
    Swag.assert(corner != center)
}
