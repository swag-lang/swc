#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

var BreadcrumbPressedIndex: u64 = Swag.U64.Max
var BreadcrumbPressedCount: u32

// The measured width is every level laid out whole, whatever room the control has, so a host can
// share a line between the path and its neighbours.
#test
{
    var host: Testing.HeadlessHost
    host.setup(700, 160)
    let path = BreadcrumbCtrl.create(&host.root, {0, 0, 700, 34})
    path.fitToWidth = true
    path.addItem("Root")
    path.addItem("A long ancestor folder")
    path.addItem("Current", hasArrow: false)
    path.layout()
    let whole = path.items.back().bodyRect.right()
    Swag.require(Math.abs(path.itf.measureContent({}).x - whole) < 0.5)

    path.resize(110, 34)
    path.layout()
    Swag.require(path.firstVisible > 0)
    Swag.require(Math.abs(path.itf.measureContent({}).x - whole) < 0.5)
}

// Fitting keeps whole trailing levels and makes every hidden parent reachable.
#test
{
    var host: Testing.HeadlessHost
    host.setup(700, 160)
    let path = BreadcrumbCtrl.create(&host.root, {0, 0, 260, 34})
    path.fitToWidth = true
    path.addItem("Root")
    path.addItem("A long ancestor folder")
    path.addItem("Documents")
    path.addItem("Current")
    path.layout()
    Swag.require(path.firstVisible > 0)
    Swag.require(path.items[path.firstVisible].bodyRect.x == path.overflowRect.right())
    Swag.require(path.items.back().arrowRect.right() <= path.clientRect().right())

    path.resize(700, 34)
    path.layout()
    Swag.require(path.firstVisible == 0 and path.overflowRect.isEmpty())
    path.resize(110, 34)
    path.layout()
    Swag.require(path.firstVisible == 3)
    Swag.require(path.items.back().bodyRect.width > 0)
    Swag.require(path.items.back().arrowRect.right() <= 110)

    BreadcrumbPressedIndex = Swag.U64.Max
    path.sigItemPressed    += &breadcrumbPressed
    var opened: bool
    host.app.sigFrame += func|host = &host, &opened|(_)
    {
        if opened do
            return
        let menu = unwrap host.capturedPopupMenu()
        Swag.require(menu.items.count == 3)
        opened = true
        menu.setEndModal("1")
    }

    host.click(path.localToSurface(path.overflowRect.center()))
    Swag.require(opened and BreadcrumbPressedIndex == 1)
}

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
    let scroll     = Wnd.create'ScrollWnd(&host.root, {0, 0, 180, 40})
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
    Swag.require(BreadcrumbPressedIndex == 2)
}

// Levels lay out left-to-right without overlap; a leaf level has no chevron.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 60)
    let bc = BreadcrumbCtrl.create(&host.root, {0, 0, 400, 32})
    bc.addItem("Home", bc.theme().icon(.OpenFile, 28), 1)
    bc.addItem("Docs", {}, 2)
    bc.addItem("Workspace", {}, 3, hasArrow: false)
    bc.setLayoutMetrics(8, 4, 5)
    bc.layout()

    Swag.require(bc.items.count == 3)
    Swag.require(bc.iconSize == 16)
    Swag.require(bc.itemAt(1).name == "Docs")
    Swag.require(bc.items[0].bodyRect.x == 0)
    let standardIconWidth = bc.items[0].bodyRect.width
    bc.iconSize = 0
    bc.layout()
    Swag.require(bc.items[0].bodyRect.width == standardIconWidth + 12)
    Swag.require(bc.items[0].arrowRect.width > 0)
    Swag.require(bc.items[1].bodyRect.x >= bc.items[0].arrowRect.right())
    Swag.require(bc.items[2].bodyRect.x >= bc.items[1].arrowRect.right())
    Swag.require(bc.items[2].arrowRect.width == 0)

    bc.removeItemsFrom(2)
    Swag.require(bc.items.count == 2)
}

// Clicking a level body navigates to that level; clicking a chevron with no menu content
// does not navigate.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 60)
    BreadcrumbPressedCount = 0
    BreadcrumbPressedIndex = Swag.U64.Max

    let bc = BreadcrumbCtrl.create(&host.root, {0, 0, 400, 32})
    bc.addItem("Home", {}, 1)
    bc.addItem("Docs", {}, 2)
    bc.sigItemPressed += &breadcrumbPressed
    bc.layout()

    let r = bc.items[1].bodyRect
    host.click(Math.Point{r.horzCenter(), r.vertCenter()})
    Swag.require(BreadcrumbPressedCount == 1)
    Swag.require(BreadcrumbPressedIndex == 1)

    // A chevron with no sigFillMenu produces an empty (destroyed) popup, so no navigation.
    let a = bc.items[0].arrowRect
    host.click(Math.Point{a.horzCenter(), a.vertCenter()})
    Swag.require(BreadcrumbPressedCount == 1)
}

// A click past the last level reports the empty space, and never a level.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 60)
    BreadcrumbPressedCount = 0

    let bc = BreadcrumbCtrl.create(&host.root, {0, 0, 400, 32})
    bc.addItem("Home")
    bc.addItem("Docs")
    bc.sigItemPressed += &breadcrumbPressed
    var emptyPresses: u32
    bc.sigEmptyPressed += func|&emptyPresses|(_) { emptyPresses += 1 }
    bc.layout()

    host.click(Math.Point{bc.items.back().arrowRect.right() + 40, 16})
    Swag.require(emptyPresses == 1 and BreadcrumbPressedCount == 0)

    let r = bc.items[0].bodyRect
    host.click(Math.Point{r.horzCenter(), r.vertCenter()})
    Swag.require(emptyPresses == 1 and BreadcrumbPressedCount == 1)
}
