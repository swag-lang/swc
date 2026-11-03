#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

private func assertBreadcrumbGolden(ancestors: bool)
{
    var host: Testing.HeadlessHost
    host.setup(640, 300, dpiScale: ancestors ? 1.0 : 1.5)
    if ancestors
    {
        host.theme.setLight()
        host.notify(.ThemeChanged)
    }

    host.root.backgroundStyle = .Dialog
    let bar = PathBar.create(&host.root)
    bar.setPosition({28, 28, 584, 34})
    bar.setPath(ancestors ? "C:/Projects/A long archive folder/Illustrations/Current" : "C:/Projects/Illustrations")
    if ancestors do
        bar.resize(300, 34)
    host.root.applyLayout()
    let path = bar.breadcrumb
    path.layout()
    path.sigFillMenu += func(_, _, menu)
    {
        menu.addItem("Cover", "cover")
        menu.addItem("Figures", "figures", checked: true)
        menu.addItem("Sketches", "sketches")
    }

    let image = host.renderSettled()
    Pixel.Testing.assertImageGolden(&image, ancestors ? "breadcrumb.overflow.paper" : "breadcrumb.path.encre")

    var captured: bool
    host.app.sigFrame += func|host = &host, &captured, ancestors|(_)
    {
        if captured do
            return
        let menu = unwrap host.capturedPopupMenu()
        Swag.assert(menu.popupAnchorButton != null)
        let anchor = menu.popupAnchorButton.surfaceRect()
        Swag.assert(Math.abs(menu.surfaceRect().y + menu.getPopupBodyRect().y - anchor.bottom()) < 0.5)
        let image = host.renderSettled()
        Pixel.Testing.assertImageGolden(&image, ancestors ? "breadcrumb.ancestors.paper" : "breadcrumb.children.encre")
        captured = true
        menu.setEndModal(null)
    }

    let target = ancestors ? path.overflowRect : path.items[1].arrowRect
    var point  = path.localToSurface(target.center())
    host.surface.surfaceToScreen(&point)
    host.click(point)
    Swag.assert(captured)
}

// The child menu stays attached to its level at high DPI, in Encre.
#[Swag.TestTag("golden")]
#test
{
    assertBreadcrumbGolden(false)
}

// Hidden ancestors remain reachable through the overflow menu, in Papier.
#[Swag.TestTag("golden")]
#test
{
    assertBreadcrumbGolden(true)
}
