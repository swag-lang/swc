#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// The shared path bar keeps short paths intact and the leaf of long paths reachable.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 100)
    let bar = PathBar.create(&host.root)
    bar.setPosition({0, 0, 400, 32})
    bar.setPath("Z:/Films")
    Swag.require(bar.breadcrumb.toolTip.isEmpty())
    Swag.require(bar.breadcrumb.items.count == 2)
    Swag.require(bar.breadcrumb.items[0].tag == "Z:/")
    Swag.require(bar.breadcrumb.items[1].name == "Films")
    Swag.require(bar.breadcrumb.scrollPos.x == 0)
    var navigated: String
    bar.sigNavigate += func|&navigated|(_, path) { navigated = path }
    host.click(bar.breadcrumb.localToSurface(bar.breadcrumb.items[0].bodyRect.center()))
    Swag.require(navigated == "Z:/")
    bar.setPath("Z:/A long collection folder/Another long folder/Films")
    bar.resize(180, 32)
    host.root.applyLayout()
    Swag.require(bar.breadcrumb.scrollPos.x == 0)
    Swag.require(bar.breadcrumb.firstVisible > 0)
    Swag.require(not bar.pathScroll.showBarH)
    let leaf = bar.breadcrumb.items.back().bodyRect
    host.click(bar.breadcrumb.localToSurface(leaf.center() - bar.breadcrumb.scrollPos))
    Swag.require(bar.edit.isLocallyVisible())
    Swag.require(bar.edit.text() == "Z:/A long collection folder/Another long folder/Films")
    host.keyPress(.Escape)
    Swag.require(not bar.edit.isLocallyVisible() and bar.pathScroll.isLocallyVisible())

    var submitted: String
    bar.sigSubmitted += func|&submitted|(_, path) { submitted = path }
    bar.beginEdit()
    bar.edit.setText("C:/Pictures")
    host.keyPress(.Return)
    Swag.require(submitted == "C:/Pictures")
    Swag.require(not bar.edit.isLocallyVisible())
}
