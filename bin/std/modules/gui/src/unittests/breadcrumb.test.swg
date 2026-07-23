#global #if #command == Swag.CompilerCommand.Test
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

    let bc = BreadcrumbCtrl.create(&host.root, {0, 0, 400, 32})
    bc.addItem("Home", {}, 1)
    bc.addItem("Docs", {}, 2)
    bc.addItem("captMe", {}, 3, hasArrow: false)
    bc.layout()

    @assert(bc.items.count == 3)
    @assert(bc.items[0].bodyRect.x == 0)
    @assert(bc.items[0].arrowRect.width > 0)
    @assert(bc.items[1].bodyRect.x >= bc.items[0].arrowRect.right())
    @assert(bc.items[2].bodyRect.x >= bc.items[1].arrowRect.right())
    @assert(bc.items[2].arrowRect.width == 0)

    host.shutdown()
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
    host.click({r.horzCenter(), r.vertCenter()})
    @assert(BreadcrumbPressedCount == 1)
    @assert(BreadcrumbPressedIndex == 1)

    // A chevron with no sigFillMenu produces an empty (destroyed) popup, so no navigation.
    let a = bc.items[0].arrowRect
    host.click({a.horzCenter(), a.vertCenter()})
    @assert(BreadcrumbPressedCount == 1)

    host.shutdown()
}
