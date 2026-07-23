#global #if #command == Swag.CompilerCommand.Test
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
    @assert(!root.canExpand())

    root.forceExpandMark = true
    @assert(root.canExpand())

    root.forceExpandMark = false
    let child = root.lines.newPtr()
    child.parent = &root
    child.level  = 1
    root.lines.add(child)

    @assert(root.canExpand())
    @assert(root.isParentOf(child))
    @assert(!child.isParentOf(&root))

    let grandChild = child.lines.newPtr()
    grandChild.parent = child
    grandChild.level  = 2
    child.lines.add(grandChild)

    @assert(root.isParentOf(grandChild))
    @assert(child.isParentOf(grandChild))
    @assert(!grandChild.isParentOf(child))
}

#test
{
    var line: ListLine
    let item0 = line.setItem(0, "Name")
    @assert(line.items.count == 1)
    @assert(line.getItem(0) == item0)
    @assert(item0.name == "Name")
    @assert(item0.column == 0)

    let item1 = line.setItem(1, "Kind")
    @assert(line.items.count == 2)
    @assert(line.getItem(1) == item1)
    @assert(item1.name == "Kind")
    @assert(item1.column == 1)

    let updated = line.setItem(0, "Renamed")
    @assert(updated == item0)
    @assert(line.items.count == 2)
    @assert(line.getItem(0).name == "Renamed")
}

#test
{
    var list: ListCtrl

    let root0 = list.createLine("root0")
    let child0 = list.createLine("child0", parentLine: root0)
    let root1 = list.createLine("root1")
    let separator = list.createLine("separator")
    separator.separator = true
    let root2 = list.createLine("root2")

    @assert(root0.index == 0)
    @assert(child0.index == 1)
    @assert(root1.index == 2)
    @assert(separator.index == 3)
    @assert(root2.index == 4)
    @assert(list.getLineCount() == 4)
    @assert(list.getLine(0) == root0)
    @assert(list.getLine(1) == root1)
    @assert(list.getLine(2) == separator)
    @assert(list.getLine(3) == root2)
    @assert(list.idxLineToIdxList.find(root0.index).value == 0)
    @assert(list.idxLineToIdxList.tryFind(child0.index) == null)
    @assert(list.idxLineToIdxList.find(root1.index).value == 1)
    @assert(list.idxLineToIdxList.find(separator.index).value == 2)
    @assert(list.idxLineToIdxList.find(root2.index).value == 3)
}

#test
{
    var list: ListCtrl
    list.selectionMode = .Multi

    let root0 = list.createLine("root0")
    let hiddenChild = list.createLine("hidden", parentLine: root0)
    let root1 = list.createLine("root1")
    let separator = list.createLine("separator")
    separator.separator = true
    let root2 = list.createLine("root2")

    list.selectLines(3, 0)
    @assert(list.isSelectedLine(0))
    @assert(list.isSelectedLine(1))
    @assert(!list.isSelectedLine(2))
    @assert(list.isSelectedLine(3))

    let selected = list.getSelectedLines()
    @assert(selected.count == 3)
    @assert(selected[0] == root0)
    @assert(selected[1] == root1)
    @assert(selected[2] == root2)

    list.selModel.select(hiddenChild.index, true)
    let selectedVisible = list.getSelectedLines()
    @assert(selectedVisible.count == 3)

    list.checkModel.select(root1.index, true)
    list.checkModel.select(hiddenChild.index, true)
    let checked = list.getCheckedLines()
    @assert(checked.count == 1)
    @assert(checked[0] == root1)
}

#test
{
    var list: ListCtrl
    list.selectionMode = .Single

    discard list.createLine("root0")
    discard list.createLine("root1")
    discard list.createLine("root2")

    list.selectLines(0, 2)
    @assert(!list.isSelectedLine(0))
    @assert(!list.isSelectedLine(1))
    @assert(list.isSelectedLine(2))

    list.selectLines(2, 0, false)
    @assert(list.selModel.isEmpty())
}

#test
{
    var list: ListCtrl
    list.isVirtual     = true
    list.virtualCount  = 6
    list.selectionMode = .Multi

    list.selectLines(4, 2)
    @assert(!list.isLineSelected(1))
    @assert(list.isLineSelected(2))
    @assert(list.isLineSelected(3))
    @assert(list.isLineSelected(4))
    @assert(!list.isLineSelected(5))
    @assert(list.getSelectedLines().isEmpty())

    list.selectLine(3, false)
    @assert(!list.isLineSelected(3))

    list.clear()
    @assert(!list.isVirtual)
    @assert(list.getLineCount() == 0)
    @assert(list.selModel.isEmpty())

    let line = list.createLine("real")
    @assert(line.index == 0)
    @assert(list.getLineCount() == 1)
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

    @assert(list.getLineCount() == 2)
    @assert(root0.canExpand())
    @assert(!root0.expanded)

    list.expand(root0)
    @assert(root0.expanded)
    @assert(list.getLineCount() == 4)

    list.collapse(root0)
    @assert(!root0.expanded)
    @assert(list.getLineCount() == 2)

    host.shutdown()
}

// Single-selection: selecting another line deselects the previous one.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 320)
    ListCtrlHeadlessSelCount = 0

    let list = ListCtrl.createSimple(&host.root, {0, 0, 200, 300})
    list.sigSelChanged += &listCtrlHeadlessSel
    list.createLine("a")
    list.createLine("b")

    @assert(list.getLineCount() == 2)
    @assert(!list.isLineSelected(0))

    list.selectLine(0)
    @assert(list.isLineSelected(0))
    @assert(!list.isLineSelected(1))

    list.selectLine(1)
    @assert(!list.isLineSelected(0))
    @assert(list.isLineSelected(1))

    list.unselectAll()
    @assert(!list.isLineSelected(1))
    @assert(ListCtrlHeadlessSelCount == 3)

    host.shutdown()
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
    @assert(list.getLineCount() == 3)

    list.clear()
    @assert(list.getLineCount() == 0)

    host.shutdown()
}

// Clicking a line selects it; clicking another (Single mode) moves the selection.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 320)
    ListCtrlHeadlessSelCount = 0

    let list = ListCtrl.createSimple(&host.root, {0, 0, 200, 300})
    list.sigSelChanged += &listCtrlHeadlessSel
    list.createLine("a")
    list.createLine("b")
    list.createLine("c")

    let lh = list.getLineHeight()
    let vs = list.listView.getSurfaceRect()

    host.click({vs.x + 30, vs.y + lh * 0.5})
    @assert(list.isLineSelected(0))
    @assert(!list.isLineSelected(1))

    host.click({vs.x + 30, vs.y + lh * 2 + lh * 0.5})
    @assert(list.isLineSelected(2))
    @assert(!list.isLineSelected(0))
    @assert(ListCtrlHeadlessSelCount >= 2)

    host.shutdown()
}

// Multi-selection: Ctrl+click toggles individual lines.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 320)

    let list = ListCtrl.createSimple(&host.root, {0, 0, 200, 300})
    list.selectionMode = .Multi
    list.createLine("a")
    list.createLine("b")
    list.createLine("c")

    let lh = list.getLineHeight()
    let vs = list.listView.getSurfaceRect()

    host.click({vs.x + 30, vs.y + lh * 0.5})
    host.click({vs.x + 30, vs.y + lh * 2 + lh * 0.5}, Input.MouseButton.Left, Input.KeyModifiers.Control)

    @assert(list.isLineSelected(0))
    @assert(!list.isLineSelected(1))
    @assert(list.isLineSelected(2))

    host.shutdown()
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
    host.focus(notnull list.listView)

    host.keyPress(Input.Key.Down)
    @assert(list.isLineSelected(0))

    host.keyPress(Input.Key.Down)
    @assert(list.isLineSelected(1))
    @assert(!list.isLineSelected(0))

    host.keyPress(Input.Key.Up)
    @assert(list.isLineSelected(0))
    @assert(!list.isLineSelected(1))

    host.shutdown()
}
