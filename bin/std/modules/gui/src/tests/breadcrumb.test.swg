#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

var BreadcrumbPressedIndex: u64 = Swag.U64.Max
var BreadcrumbPressedCount: u32

func breadcrumbPressed(bc: *BreadcrumbCtrl, idx: u64)
{
    discard bc
    BreadcrumbPressedIndex = idx
    BreadcrumbPressedCount += 1
}

// Levels lay out left-to-right without overlap; a leaf level has no chevron.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 60)
    defer host.shutdown()
    let bc = BreadcrumbCtrl.create(&host.root, {0, 0, 400, 32})
    bc.addItem("Home", bc.theme().icon(.OpenFile, 28), 1)
    bc.addItem("Docs", {}, 2)
    bc.addItem("Workspace", {}, 3, hasArrow: false)
    bc.setLayoutMetrics(8, 4, 5)
    bc.layout()

    @assert(bc.items.count == 3)
    @assert(bc.iconSize == 16)
    @assert(bc.itemAt(1).name == "Docs")
    @assert(bc.items[0].bodyRect.x == 0)
    let standardIconWidth = bc.items[0].bodyRect.width
    bc.iconSize = 0
    bc.layout()
    @assert(bc.items[0].bodyRect.width == standardIconWidth + 12)
    @assert(bc.items[0].arrowRect.width > 0)
    @assert(bc.items[1].bodyRect.x >= bc.items[0].arrowRect.right())
    @assert(bc.items[2].bodyRect.x >= bc.items[1].arrowRect.right())
    @assert(bc.items[2].arrowRect.width == 0)

    bc.removeItemsFrom(2)
    @assert(bc.items.count == 2)
}

// Clicking a level body navigates to that level; clicking a chevron with no menu content
// does not navigate.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 60)
    defer host.shutdown()
    BreadcrumbPressedCount = 0
    BreadcrumbPressedIndex = Swag.U64.Max

    let bc = BreadcrumbCtrl.create(&host.root, {0, 0, 400, 32})
    bc.addItem("Home", {}, 1)
    bc.addItem("Docs", {}, 2)
    bc.sigItemPressed += &breadcrumbPressed
    bc.layout()

    let r = bc.items[1].bodyRect
    host.click({r.horzCenter(), r.vertCenter()})
    @assert(BreadcrumbPressedCount == 1)
    @assert(BreadcrumbPressedIndex == 1)

    // A chevron with no sigFillMenu produces an empty (destroyed) popup, so no navigation.
    let a = bc.items[0].arrowRect
    host.click({a.horzCenter(), a.vertCenter()})
    @assert(BreadcrumbPressedCount == 1)
}
