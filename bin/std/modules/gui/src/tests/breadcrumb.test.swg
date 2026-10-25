#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

var BreadcrumbPressedIndex: u64 = Swag.U64.Max
var BreadcrumbPressedCount: u32

func breadcrumbPressed(_: *BreadcrumbCtrl, idx: u64)
{
    BreadcrumbPressedIndex = idx
    BreadcrumbPressedCount += 1
}

// A horizontally scrolled path hit-tests the visible level in content coordinates.
#test
{
    var host: Testing.HeadlessHost
    host.setup(180, 60)
    let scroll     = Wnd.create'ScrollWnd(&host.root, Math.Rectangle{0, 0, 180, 40})
    let breadcrumb = BreadcrumbCtrl.create(scroll)
    scroll.setView(breadcrumb)
    breadcrumb.addItem("A long ancestor folder")
    breadcrumb.addItem("Documents")
    breadcrumb.addItem("Current")
    breadcrumb.sigItemPressed += &breadcrumbPressed
    breadcrumb.layout()
    scroll.setScrollSize(breadcrumb.items.back().arrowRect.right(), 0)
    scroll.setScrollPos(scroll.scrollSize.x, 0)
    breadcrumb.layout()
    BreadcrumbPressedIndex = Swag.U64.Max
    let body = breadcrumb.items.back().bodyRect
    host.click(breadcrumb.localToSurface(Math.Point{body.horzCenter(), body.vertCenter()} - breadcrumb.scrollPos))
    Swag.assert(BreadcrumbPressedIndex == 2)
}

// Levels lay out left-to-right without overlap; a leaf level has no chevron.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 60)
    let bc = BreadcrumbCtrl.create(&host.root, Math.Rectangle{0, 0, 400, 32})
    bc.addItem("Home", bc.theme().icon(.OpenFile, 28), 1)
    bc.addItem("Docs", {}, 2)
    bc.addItem("Workspace", {}, 3, hasArrow: false)
    bc.setLayoutMetrics(8, 4, 5)
    bc.layout()

    Swag.assert(bc.items.count == 3)
    Swag.assert(bc.iconSize == 16)
    Swag.assert(bc.itemAt(1).name == "Docs")
    Swag.assert(bc.items[0].bodyRect.x == 0)
    let standardIconWidth = bc.items[0].bodyRect.width
    bc.iconSize = 0
    bc.layout()
    Swag.assert(bc.items[0].bodyRect.width == standardIconWidth + 12)
    Swag.assert(bc.items[0].arrowRect.width > 0)
    Swag.assert(bc.items[1].bodyRect.x >= bc.items[0].arrowRect.right())
    Swag.assert(bc.items[2].bodyRect.x >= bc.items[1].arrowRect.right())
    Swag.assert(bc.items[2].arrowRect.width == 0)

    bc.removeItemsFrom(2)
    Swag.assert(bc.items.count == 2)
}

// Clicking a level body navigates to that level; clicking a chevron with no menu content
// does not navigate.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 60)
    BreadcrumbPressedCount = 0
    BreadcrumbPressedIndex = Swag.U64.Max

    let bc = BreadcrumbCtrl.create(&host.root, Math.Rectangle{0, 0, 400, 32})
    bc.addItem("Home", {}, 1)
    bc.addItem("Docs", {}, 2)
    bc.sigItemPressed += &breadcrumbPressed
    bc.layout()

    let r = bc.items[1].bodyRect
    host.click(Math.Point{r.horzCenter(), r.vertCenter()})
    Swag.assert(BreadcrumbPressedCount == 1)
    Swag.assert(BreadcrumbPressedIndex == 1)

    // A chevron with no sigFillMenu produces an empty (destroyed) popup, so no navigation.
    let a = bc.items[0].arrowRect
    host.click(Math.Point{a.horzCenter(), a.vertCenter()})
    Swag.assert(BreadcrumbPressedCount == 1)
}
