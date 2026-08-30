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
    Swag.assert(tab.items.count == 3)
    Swag.assert(tab.selectedIndex == 0)

    tab.setSelectedIndex(2)
    Swag.assert(tab.selectedIndex == 2)
    Swag.assert(TabHeadlessSelChangedCount == 1)
    Swag.assert(tab.selectedItem()!.name.raw == "C")

    // Selecting the current tab is a no-op.
    tab.setSelectedIndex(2)
    Swag.assert(TabHeadlessSelChangedCount == 1)

    host.focus(tab)
    host.keyPress(Input.Key.Left)
    Swag.assert(tab.selectedIndex == 1 and TabHeadlessSelChangedCount == 2)
    host.keyPress(Input.Key.Home)
    Swag.assert(tab.selectedIndex == 0 and TabHeadlessSelChangedCount == 3)
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

    Swag.assert(!viewA.wndFlags.has(.Hidden))
    Swag.assert(viewB.wndFlags.has(.Hidden))

    tab.setSelectedIndex(1)
    Swag.assert(viewA.wndFlags.has(.Hidden))
    Swag.assert(!viewB.wndFlags.has(.Hidden))
}

// Opt-in page transitions keep the outgoing page painted under the incoming fade while preserving
// final visibility and logical geometry.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()
    host.setReducedMotion(false)
    let tab   = Tab.create(&host.root, {10, 10, 300, 180})
    let viewA = Wnd.create'Wnd(tab)
    let viewB = Wnd.create'Wnd(tab)
    tab.setForms(.Transparent, .Transparent, .None)
    viewA.backgroundStyle = .View
    viewB.backgroundStyle = .Window
    tab.setPageTransitions(true)
    tab.addItem("A", view: viewA)
    tab.addItem("B", view: viewB)

    let before      = host.render()
    let beforeColor = before.pixelColor(160, 120)
    let emptyColor  = host.theme.colors.dlg_Bk
    Swag.assert(beforeColor.argb != emptyColor.argb)

    tab.setSelectedIndex(1)
    Swag.assert(viewA.wndFlags.has(.Hidden) and !viewB.wndFlags.has(.Hidden))
    Swag.assert(viewA.paintsWhenHidden)
    Swag.assert(viewA.presentationOpacity == 1)
    Swag.assert(viewB.presentationOpacity == 0)
    Swag.assert(viewB.presentationOffset.x == tab.themeMetrics().motion_PageOffset)
    let start = host.render()
    Swag.assert(start.pixelColor(160, 120).argb == beforeColor.argb)
    let logicalPosition = viewB.position

    host.advanceAnimations(tab.themeMetrics().motion_PageSeconds * 0.5)
    Swag.assert(viewA.presentationOpacity > 0 and viewA.presentationOpacity < 1)
    Swag.assert(viewB.presentationOpacity > 0 and viewB.presentationOpacity < 1)
    Swag.assert(viewB.position == logicalPosition)
    let halfway = host.render()
    Swag.assert(halfway.pixelColor(160, 120).argb != emptyColor.argb)
    host.finishAnimations()
    Swag.assert(!viewA.paintsWhenHidden)
    Swag.assert(viewA.presentationOpacity == 1)
    Swag.assert(viewB.presentationOpacity == 1 and viewB.presentationOffset == Math.Point{})
    let finished = host.render()
    Swag.assert(finished.pixelColor(160, 120).argb != beforeColor.argb)
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
    Swag.assert(tab.selectedIndex == 1 and tab.selectedItem()!.name.raw == "C")
    Swag.assert(TabHeadlessSelChangedCount == 1)

    tab.removeItemAt(1)
    Swag.assert(tab.selectedIndex == 0 and tab.selectedItem()!.name.raw == "B")
    Swag.assert(TabHeadlessSelChangedCount == 2)

    tab.clear()
    Swag.assert(tab.items.isEmpty() and tab.selectedItem() == null and tab.selectedIndex == Swag.U32.Max)
    Swag.assert(viewA.isPendingDestroy and viewB.isPendingDestroy and viewC.isPendingDestroy)
    host.pump()
}
