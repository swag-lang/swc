#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag, Core

var ListCtrlHeadlessSelCount: u32

func listCtrlHeadlessSel(list: *ListCtrl)
{
    discard list
    ListCtrlHeadlessSelCount += 1
}

// Expanding/collapsing a parent line changes the visible line count.
#test
{
    var host: GuiHeadlessHost
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
    var host: GuiHeadlessHost
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
    var host: GuiHeadlessHost
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
    var host: GuiHeadlessHost
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
    var host: GuiHeadlessHost
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
    var host: GuiHeadlessHost
    host.setup(220, 320)

    let list = ListCtrl.createSimple(&host.root, {0, 0, 200, 300})
    list.createLine("a")
    list.createLine("b")
    list.createLine("c")
    host.focus(list.listView)

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
