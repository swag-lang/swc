#global public

using Core, Pixel

// Selects the axis along which a [[Gui.DockHost]] divides two pane stacks.
enum DockSplitOrientation
{
    Horizontal    // Places the panes side by side.
    Vertical      // Places the panes one above the other.
}

// One leaf in a programmatic dock layout, either a tab stack or a split of two leaves.
private struct DockNode
{
    late host:    *DockHost
    parent:       *DockNode?
    first:        *DockNode?
    second:       *DockNode?
    splitter:     *SplitterCtrl?
    tab:          *Tab?
    firstItem:    *SplitterItem?
    secondItem:   *SplitterItem?
    orientation:  DockSplitOrientation
    hasPendingSize: bool
    pendingPaneIndex: u32
    pendingSize:  f32
}

// One stable, host-wide pane identity and its owned page view.
private struct DockPane
{
    late id:     WndId
    late view:   *Wnd
    minimumSize: Math.Point
    late node:   *DockNode
    tabIndex:    u32
    hidden:      bool
}

// Hosts tab stacks arranged by a programmatic binary split tree.
struct DockHost
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        readonly paneCount: u64     // Number of open panes, including hidden panes.
    }

    private
    {
        root:  *DockNode?
        nodes: ArrayPtr'DockNode
        panes: ArrayPtr'DockPane
    }
}

impl IWnd for DockHost
{
    mtd impl onLayout()
    {
        if .root
        {
            let root = .root
            root.control().setPosition(.paddedClientRect())
            root.applyPendingSizes()
        }
    }

    mtd impl measureContent(_: Math.Point)->Math.Point
    {
        if not .root do
            return {}
        let root = .root
        return root.minimumSize()
    }
}

private impl DockNode
{
    mtd control()->*Wnd
    {
        if .tab do
            return .tab
        Swag.assert(.splitter != null)
        return .splitter
    }

    mtd minimumSize()->Math.Point
    {
        if .tab
        {
            let tab = .tab
            let tabMinimum = Math.Point{0, tab.barHeight + tab.padding.y + tab.padding.w}
            var result    = tabMinimum
            for pane in .host.panes where pane!.node == me and not pane.hidden
            {
                let viewMinimum = pane.view.measure({}).min
                result.x = Math.max(result.x, Math.max(pane.minimumSize.x, viewMinimum.x))
                result.y = Math.max(result.y, Math.max(pane.minimumSize.y, viewMinimum.y))
            }
            return result
        }

        let first = unwrap .first
        let second = unwrap .second
        let splitter = unwrap .splitter
        let firstVisible = first.hasVisiblePane()
        let secondVisible = second.hasVisiblePane()
        if not firstVisible do
            return secondVisible ? second.minimumSize() : Math.Point{}
        if not secondVisible do
            return first.minimumSize()

        let firstSize  = first.minimumSize()
        let secondSize = second.minimumSize()
        let barSize    = splitter.themeMetrics().splitView_BarSize
        if .orientation == .Horizontal do
            return {firstSize.x + secondSize.x + barSize, Math.max(firstSize.y, secondSize.y)}
        return {Math.max(firstSize.x, secondSize.x), firstSize.y + secondSize.y + barSize}
    }

    mtd hasVisiblePane()->bool
    {
        if .tab
        {
            for pane in .host.panes where pane!.node == me and not pane.hidden do
                return true
            return false
        }
        let first = unwrap .first
        let second = unwrap .second
        return first.hasVisiblePane() or second.hasVisiblePane()
    }

    mtd firstEmptyLeaf()->*DockNode
    {
        if .tab
        {
            Swag.assert(.tab.items.isEmpty())
            return me
        }
        let first = unwrap .first
        if not first.hasVisiblePane() do
            return first.firstEmptyLeaf()
        let second = unwrap .second
        return second.firstEmptyLeaf()
    }

    mtd applyPendingSizes()
    {
        if .splitter
        {
            let splitter = .splitter
            let available = .orientation == .Vertical ? splitter.position.height : splitter.position.width
            if .hasPendingSize and available > 0
            {
                let equalSize = Math.max(0, (available - splitter.themeMetrics().splitView_BarSize) * 0.5)
                let requestedSize = .pendingSize > 0 ? .pendingSize : equalSize
                splitter.setPaneSize(.pendingPaneIndex, requestedSize)
                .hasPendingSize = false
            }
            let first = unwrap .first
            let second = unwrap .second
            first.applyPendingSizes()
            second.applyPendingSizes()
        }
    }
}

impl DockHost
{
    // Creates an empty host whose panes are owned until closed or the host is destroyed.
    #[Swag.Discardable]
    func create(parent: *Wnd, position: Math.Rectangle = {}, id: WndId? = null)->*DockHost
    {
        Swag.assert(parent != null)
        return Wnd.create'DockHost(parent, null, position, id)
    }

    // Adds a pane to the root stack when the host has no open panes.
    //
    // The host takes ownership of `view` and destroys it when [[Gui.DockHost.closePane]] is
    // called or when the host is destroyed. `id` must be non-empty and unique for this host.
    // `minimumSize` is the page's minimum width and height in logical units.
    mtd addPane(id: WndId, title: string, view: *Wnd, minimumSize: Math.Point = {})
    {
        .validatePane(id, view, minimumSize)

        var node: *DockNode
        if .root
        {
            Swag.assert(.panes.isEmpty(), "addPane creates the root; use addTab or splitPane for later panes")
            let root = .root
            node = root.firstEmptyLeaf()
        }
        else
        {
            node = .createLeaf(me)
            .root = node
        }
        discard .addPaneTo(node, id, title, view, minimumSize)
    }

    // Adds a pane to the tab stack that contains `stackPaneId`.
    //
    // The host takes ownership of `view`. Its stable identifier is unique across every stack.
    // `minimumSize` is the page's minimum width and height in logical units.
    mtd addTab(stackPaneId: WndId, id: WndId, title: string, view: *Wnd, minimumSize: Math.Point = {})
    {
        .validatePane(id, view, minimumSize)
        let target = .findPane(stackPaneId)
        Swag.assert(target != null, "dock stack pane identifier was not found")
        discard .addPaneTo(target.node, id, title, view, minimumSize)
    }

    // Splits the stack containing `targetPaneId` and adds a new stack beside it.
    //
    // `after` places the new stack after or before the target stack in the split. A positive
    // `splitSize` is its requested size in logical units after the first layout. Pane minimums
    // and available space bound it. Zero divides available space evenly, subject to the same
    // minimums.
    // The host takes ownership of `view` and destroys it when the pane closes or the host is
    // destroyed.
    mtd splitPane(targetPaneId: WndId, id: WndId, title: string, view: *Wnd, orientation: DockSplitOrientation, after = true, splitSize: f32 = 0, minimumSize: Math.Point = {})
    {
        .validatePane(id, view, minimumSize)
        Swag.assert(splitSize >= 0, "dock split size must not be negative")

        let target = .findPane(targetPaneId)
        Swag.assert(target != null, "dock target pane identifier was not found")
        let leaf = target.node
        Swag.assert(leaf.tab != null)

        let oldTab      = leaf.tab
        let oldParent   = leaf.parent
        let parent      = oldTab.parent
        Swag.assert(parent != null)
        let oldPosition = oldTab.position
        var priorItem: *SplitterItem?
        if leaf.parent
        {
            let parentNode = leaf.parent
            if parentNode.splitter
            {
                for item in parentNode.splitter.items where item!.view == oldTab
                {
                    priorItem = item
                    break
                }
            }
        }

        let split = SplitterCtrl.create(parent, oldPosition, orientation == .Vertical)
        if priorItem do
            priorItem.view = split
        oldTab.setParent(null)

        let newLeaf = .createLeaf(split)

        let oldSize = orientation == .Vertical ? oldPosition.height : oldPosition.width
        let newSize = splitSize > 0 ? splitSize : oldSize * 0.5
        var oldItemMaybe: *SplitterItem? = null
        var newItemMaybe: *SplitterItem? = null
        if after
        {
            oldItemMaybe = split.addPane(oldTab, oldSize)
            newItemMaybe = split.addPane(unwrap newLeaf.tab, newSize)
        }
        else
        {
            newItemMaybe = split.addPane(unwrap newLeaf.tab, newSize)
            oldItemMaybe = split.addPane(oldTab, oldSize)
        }

        let oldItem = oldItemMaybe
        let newItem = newItemMaybe
        let splitNode = .nodes.allocate()
        splitNode.host             = me
        splitNode.parent           = oldParent
        splitNode.splitter         = split
        splitNode.orientation       = orientation
        splitNode.hasPendingSize   = true
        splitNode.pendingPaneIndex = after ? 1 : 0
        splitNode.pendingSize      = splitSize
        if after
        {
            splitNode.first      = leaf
            splitNode.second     = newLeaf
            splitNode.firstItem  = oldItem
            splitNode.secondItem = newItem
        }
        else
        {
            splitNode.first      = newLeaf
            splitNode.second     = leaf
            splitNode.firstItem  = newItem
            splitNode.secondItem = oldItem
        }
        leaf.parent    = splitNode
        newLeaf.parent = splitNode
        .nodes.add(splitNode)

        if oldParent
        {
            if oldParent.first == leaf do
                oldParent.first = splitNode
            else do
                oldParent.second = splitNode
        }
        else do
            .root = splitNode

        .refreshTree()
        discard .addPaneTo(newLeaf, id, title, view, minimumSize)
    }

    // Hides a pane without destroying it or removing its tab identity.
    //
    // The tab disappears from its stack, and its minimum size no longer constrains the layout.
    mtd hidePane(id: WndId)
    {
        let pane = .findPane(id)
        Swag.assert(pane != null, "dock pane identifier was not found")
        if pane.hidden do
            return

        let hiddenPane = pane
        hiddenPane.hidden = true
        let tab = unwrap hiddenPane.node.tab
        tab.setItemVisible(hiddenPane.tabIndex, false)
        .refreshTree()
    }

    // Makes a hidden pane available in its stack while preserving its identity and position.
    //
    // The current visible tab remains selected when the stack already has one.
    mtd showPane(id: WndId)
    {
        let pane = .findPane(id)
        Swag.assert(pane != null, "dock pane identifier was not found")
        if not pane.hidden do
            return

        let visiblePane = pane
        visiblePane.hidden = false
        let tab = unwrap visiblePane.node.tab
        tab.setItemVisible(visiblePane.tabIndex, true)
        .refreshTree()
    }

    // Closes a pane, removes its tab, and destroys the page view owned by the host.
    mtd closePane(id: WndId)
    {
        let pane = .findPane(id)
        Swag.assert(pane != null, "dock pane identifier was not found")
        let closingPane = pane
        let node        = closingPane.node
        let index       = .paneIndex(closingPane)
        let tabIndex    = closingPane.tabIndex
        closingPane.hidden = true
        for other in .panes
        {
            let openPane = unwrap other
            if openPane != closingPane and openPane.node == node and openPane.tabIndex > tabIndex do
                openPane.tabIndex -= 1
        }
        let tab = unwrap node.tab
        tab.removeItemAt(tabIndex)
        .panes.deleteAt(index)
        .updateTabIndices(node)
        .refreshTree()
    }

    // Reports whether an open pane with `id` is registered in the host.
    mtd const hasPane(id: WndId)->bool
    {
        for pane in .panes where pane!.id == id do
            return true
        return false
    }

    private mtd findPane(id: WndId)->*DockPane?
    {
        for pane in .panes where pane!.id == id do
            return pane
        return null
    }

    // Selects a visible pane in its tab stack; hidden panes cannot become active.
    mtd selectPane(id: WndId)
    {
        let pane = .findPane(id)
        Swag.assert(pane != null, "dock pane identifier was not found")
        Swag.assert(not pane.hidden, "a hidden pane cannot be selected")
        let visiblePane = pane
        let tab = unwrap visiblePane.node.tab
        tab.setSelectedIndex(visiblePane.tabIndex)
    }

    private mtd validatePane(id: WndId, view: *Wnd, minimumSize: Math.Point)
    {
        Swag.assert(id != "", "dock pane identifier must not be empty")
        Swag.assert(view != null)
        Swag.assert(minimumSize.x >= 0 and minimumSize.y >= 0, "dock pane minimum size must not be negative")
        Swag.assert(.findPane(id) == null, "dock pane identifiers must be unique")
    }

    private mtd createLeaf(parent: *Wnd)->*DockNode
    {
        let node = .nodes.allocate()
        node.host = me
        let tab = Tab.create(parent)
        node.tab = tab
        tab.sigSelectionChanged += func|host = me, tab|(_)
        {
            host.onTabSelectionChanged(tab)
        }
        .nodes.add(node)
        return node
    }

    private mtd addPaneTo(node: *DockNode, id: WndId, title: string, view: *Wnd, minimumSize: Math.Point)->*DockPane
    {
        let tab = unwrap node.tab
        let pane = .panes.allocate()
        pane.id          = id
        pane.view        = view
        pane.minimumSize = minimumSize
        pane.node        = node
        pane.tabIndex    = cast(u32, tab.items.count)
        tab.addItem(title, view: view)
        .panes.add(pane)
        .paneCount += 1
        .refreshTree()
        return pane
    }

    private mtd paneIndex(target: *DockPane)->u64
    {
        for pane, index in .panes where pane == target do
            return index
        Swag.assert(false, "dock pane is not registered")
        return 0
    }

    private mtd updateTabIndices(node: *DockNode)
    {
        Swag.assert(node.tab != null)
        let tab = node.tab
        for pane in .panes where pane!.node == node
        {
            for item, index in tab.items where item!.view == pane.view
            {
                pane.tabIndex = cast(u32, index)
                break
            }
        }
    }

    private mtd hasVisibleSelection(tab: *Tab)->bool
    {
        for pane in .panes where pane!.node.tab == tab and not pane.hidden and pane.tabIndex == tab.selectedIndex do
            return true
        return false
    }

    private mtd onTabSelectionChanged(tab: *Tab)
    {
        if .hasVisibleSelection(tab) do
            return
        tab.selectNearestVisible(tab.selectedIndex)
    }

    private mtd refreshTree()
    {
        if not .root
        {
            .paneCount = 0
            return
        }
        .paneCount = .panes.count
        let root = .root
        .refreshNode(root)
        .minSize = root.minimumSize()
        .invalidateLayout()
    }

    private mtd refreshNode(node: *DockNode)
    {
        if node.tab do
            return

        let first  = unwrap node.first
        let second = unwrap node.second
        .refreshNode(first)
        .refreshNode(second)
        let firstSize  = first.minimumSize()
        let secondSize = second.minimumSize()
        node.firstItem!.minimumSize  = node.orientation == .Horizontal ? firstSize.x : firstSize.y
        node.secondItem!.minimumSize = node.orientation == .Horizontal ? secondSize.x : secondSize.y
        node.firstItem.visible      = first.hasVisiblePane()
        node.secondItem.visible     = second.hasVisiblePane()
        node.splitter!.minSize       = node.minimumSize()
        node.splitter.sendResizeEvent()
    }
}

private impl Tab
{
    mtd host()->*DockHost
    {
        var parent = .parent
        while parent
        {
            if parent is DockHost as dockHost do
                return dockHost
            parent = parent.parent
        }
        Swag.assert(false, "dock tab is detached from its host")
        unreachable
    }

    mtd selectNearestVisible(fromIndex: u32)
    {
        let host = .host()
        for distance in 0 until .items.count
        {
            let right = cast(u64, fromIndex) + distance
            if right < .items.count
            {
                for pane in host.panes where pane!.node.tab == me and pane.tabIndex == right and not pane.hidden
                {
                    .setSelectedIndex(cast(u32, right))
                    return
                }
            }

            if distance <= fromIndex
            {
                let left = fromIndex - distance
                for pane in host.panes where pane!.node.tab == me and pane.tabIndex == left and not pane.hidden
                {
                    .setSelectedIndex(cast(u32, left))
                    return
                }
            }
        }

        if .selectedIndex < .items.count
        {
            let selected = unwrap .items[.selectedIndex]
            selected.view?.hide()
        }
    }
}
