#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

var TabHeadlessSelChangedCount: u32

// Flat tabs keep one contrasted Arc underline while it travels, over the hairline the bar stands
// on. The tab under the pointer changes its words, never the rule.
#test
{
    for palette in [ThemeColors.encrePalette(), ThemeColors.papierPalette()]
    {
        var host: Testing.HeadlessHost
        host.setup(320, 120)
        host.theme.colors.apply(palette)
        host.setReducedMotion(false)

        let tab = Tab.create(&host.root, {0, 0, 320, 120})
        tab.setForms(.Flat, .Flat, .None)
        for name in ["Create", "Open", "Mounted", "Options"] do
            tab.addItem(name)
        host.settleAnimations()

        let colors = tab.themeColors()
        Swag.assert(colors.tabItem_FlatSelected == colors.arc)
        Swag.assert(colors.tabItem_FlatSelected.contrastRatio(colors.dlg_Bk) >= 3.5)
        Swag.assert(colors.tabItem_FlatHot.a == 0)

        tab.setSelectedIndex(3)
        host.advanceAnimations(tab.themeMetrics().motion_QuickSeconds * 0.5)
        let halfway = host.render()
        let rail    = tab.selectionRail
        let y       = cast(u32, rail.y + rail.height / 2)
        Swag.assert(rail.height == tab.themeMetrics().tabItem_RailSize)
        Swag.assert(rail.x > 8 and rail.x < 248)
        Swag.assert(halfway.pixelColor(cast(u32, rail.x + rail.width / 2), y) == colors.tabItem_FlatSelected)
        Swag.assert(halfway.pixelColor(4, y) == colors.tabBar_FlatLine)
        Swag.assert(halfway.pixelColor(316, y) == colors.tabBar_FlatLine)

        host.finishAnimations()
        host.moveMouse(Math.Point{40, tab.barHeight / 2})
        host.settleAnimations()
        let hovered = host.render()
        Swag.assert(hovered.pixelColor(40, y) == colors.tabBar_FlatLine)
        Swag.assert(hovered.pixelColor(280, y) == colors.tabItem_FlatSelected)
    }
}

// Adding tabs and selecting one updates the index and fires sigSelectionChanged.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    TabHeadlessSelChangedCount = 0

    let tab = Tab.create(&host.root, {10, 10, 300, 180})
    tab.sigSelectionChanged += func(_) { TabHeadlessSelChangedCount += 1 }

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
    let tab   = Tab.create(&host.root, {10, 10, 300, 180})
    let viewA = Wnd.create'Wnd(tab, null, {0, 0, 100, 100})
    let viewB = Wnd.create'Wnd(tab, null, {0, 0, 100, 100})

    tab.addItem("A", {}, viewA)
    tab.addItem("B", {}, viewB)

    Swag.assert(not viewA.wndFlags.has(.Hidden))
    Swag.assert(viewB.wndFlags.has(.Hidden))

    tab.setSelectedIndex(1)
    Swag.assert(viewA.wndFlags.has(.Hidden))
    Swag.assert(not viewB.wndFlags.has(.Hidden))
}

// Opt-in page transitions keep the outgoing page painted under the incoming fade while preserving
// final visibility and logical geometry.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    host.setReducedMotion(false)
    let tab   = Tab.create(&host.root, {10, 10, 300, 180})
    let viewA = Wnd.create'Wnd(tab)
    let viewB = Wnd.create'Wnd(tab)
    tab.setForms(.Transparent, .Transparent, .None)
    viewA.backgroundStyle = .View
    viewB.backgroundStyle = .Window

    // The charter grounds a view and a window alike, so the incoming page gets a ground of its own.
    viewB.style.addStyleSheetColors("wnd_Bk $raised")
    tab.setPageTransitions(true)
    tab.addItem("A", view: viewA)
    tab.addItem("B", view: viewB)

    let before      = host.render()
    let beforeColor = before.pixelColor(160, 120)
    let emptyColor  = host.theme.colors.dlg_Bk
    Swag.assert(beforeColor.argb != emptyColor.argb)

    tab.setSelectedIndex(1)
    Swag.assert(viewA.wndFlags.has(.Hidden) and not viewB.wndFlags.has(.Hidden))
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
    Swag.assert(not viewA.paintsWhenHidden)
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
    TabHeadlessSelChangedCount = 0

    let tab   = Tab.create(&host.root, {10, 10, 300, 180})
    let viewA = Wnd.create'Wnd(tab)
    let viewB = Wnd.create'Wnd(tab)
    let viewC = Wnd.create'Wnd(tab)
    tab.addItem("A", view: viewA)
    tab.addItem("B", view: viewB)
    tab.addItem("C", view: viewC)
    tab.sigSelectionChanged += func(_) { TabHeadlessSelChangedCount += 1 }

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

// Measuring through Wnd must include the bar even when the tab has no explicit height.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    let tab = Tab.create(&host.root)
    tab.addItem("First")
    tab.addItem("Second")
    tab.padding = {3, 5, 7, 9}
    let wnd: *Wnd = tab
    for form in [TabForm.Flat, TabForm.Round, TabForm.Button]
    {
        tab.setForm(form)
        let hint = wnd.measure({300, 0})
        Swag.assert(hint.preferred.y == tab.barHeight + 14)
        Swag.assert(hint.preferred.x >= tab.minimumItemWidth * 2 + 10)
    }
}
