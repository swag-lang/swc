#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

var TabHeadlessSelChangedCount: u32

// Adding tabs and selecting one updates the index and fires sigSelectionChanged.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()
    TabHeadlessSelChangedCount = 0

    let tab = Tab.create(&host.root, {10, 10, 300, 180})
    tab.sigSelectionChanged += func(tab) { TabHeadlessSelChangedCount += 1 }

    tab.addItem("A")
    tab.addItem("B")
    tab.addItem("C")
    @assert(tab.items.count == 3)
    @assert(tab.selectedIndex == 0)

    tab.setSelectedIndex(2)
    @assert(tab.selectedIndex == 2)
    @assert(TabHeadlessSelChangedCount == 1)
    @assert((notnull tab.selectedItem()).name.raw == "C")

    // Selecting the current tab is a no-op.
    tab.setSelectedIndex(2)
    @assert(TabHeadlessSelChangedCount == 1)

    host.focus(tab)
    host.keyPress(Input.Key.Left)
    @assert(tab.selectedIndex == 1 and TabHeadlessSelChangedCount == 2)
    host.keyPress(Input.Key.Home)
    @assert(tab.selectedIndex == 0 and TabHeadlessSelChangedCount == 3)
}

// Tab views are shown/hidden according to the selection.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()
    let tab   = Tab.create(&host.root, {10, 10, 300, 180})
    let viewA = Wnd.create'Wnd(tab, null, {0, 0, 100, 100})
    let viewB = Wnd.create'Wnd(tab, null, {0, 0, 100, 100})

    tab.addItem("A", {}, viewA)
    tab.addItem("B", {}, viewB)

    @assert(!viewA.wndFlags.has(.Hidden))
    @assert(viewB.wndFlags.has(.Hidden))

    tab.setSelectedIndex(1)
    @assert(viewA.wndFlags.has(.Hidden))
    @assert(!viewB.wndFlags.has(.Hidden))
}

// Removing tabs destroys owned pages, preserves the selected item identity, and clears safely.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()
    TabHeadlessSelChangedCount = 0

    let tab   = Tab.create(&host.root, {10, 10, 300, 180})
    let viewA = Wnd.create'Wnd(tab)
    let viewB = Wnd.create'Wnd(tab)
    let viewC = Wnd.create'Wnd(tab)
    tab.addItem("A", view: viewA)
    tab.addItem("B", view: viewB)
    tab.addItem("C", view: viewC)
    tab.sigSelectionChanged += func(tab) { TabHeadlessSelChangedCount += 1 }

    tab.setSelectedIndex(2)
    tab.removeItemAt(0)
    @assert(tab.selectedIndex == 1 and (notnull tab.selectedItem()).name.raw == "C")
    @assert(TabHeadlessSelChangedCount == 1)

    tab.removeItemAt(1)
    @assert(tab.selectedIndex == 0 and (notnull tab.selectedItem()).name.raw == "B")
    @assert(TabHeadlessSelChangedCount == 2)

    tab.clear()
    @assert(tab.items.isEmpty() and tab.selectedItem() == null and tab.selectedIndex == Swag.U32.Max)
    @assert(viewA.isPendingDestroy and viewB.isPendingDestroy and viewC.isPendingDestroy)
    host.pump()
}
