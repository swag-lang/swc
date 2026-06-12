#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag, Core

var TabHeadlessSelChangedCount: u32

func tabHeadlessSelChanged(tab: *Tab)
{
    discard tab
    TabHeadlessSelChangedCount += 1
}

// Adding tabs and selecting one updates the index and fires sigSelChanged.
#test
{
    var host: GuiHeadlessHost
    host.setup(320, 200)
    TabHeadlessSelChangedCount = 0

    let tab = Tab.create(&host.root, {10, 10, 300, 180})
    tab.sigSelChanged += &tabHeadlessSelChanged

    tab.addItem("A")
    tab.addItem("B")
    tab.addItem("C")
    @assert(tab.views.count == 3)
    @assert(tab.selectedIdx == 0)

    tab.select(2)
    @assert(tab.selectedIdx == 2)
    @assert(TabHeadlessSelChangedCount == 1)
    @assert(tab.getSelectedItem().name.raw == "C")

    // Selecting the current tab is a no-op.
    tab.select(2)
    @assert(TabHeadlessSelChangedCount == 1)

    host.shutdown()
}

// Tab views are shown/hidden according to the selection.
#test
{
    var host: GuiHeadlessHost
    host.setup(320, 200)

    let tab     = Tab.create(&host.root, {10, 10, 300, 180})
    let viewA   = Wnd.create'Wnd(tab, null, {0, 0, 100, 100})
    let viewB   = Wnd.create'Wnd(tab, null, {0, 0, 100, 100})

    tab.addItem("A", {}, viewA)
    tab.addItem("B", {}, viewB)

    @assert(!viewA.wndFlags.has(.Hidden))
    @assert(viewB.wndFlags.has(.Hidden))

    tab.select(1)
    @assert(viewA.wndFlags.has(.Hidden))
    @assert(!viewB.wndFlags.has(.Hidden))

    host.shutdown()
}
