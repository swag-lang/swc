#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

// A real field and nearby rows expose coincident edges which an isolated popup cannot show.
func anchoredContextGolden(golden: string, withIcon: bool, withText: bool, light: bool, scale: f32)
{
    var host: Testing.HeadlessHost
    host.setup(540, 290, scale)
    if light do
        host.theme.setLight()
    host.notify(.ThemeChanged)
    host.root.backgroundStyle = .Dialog
    discard EditBox.create(&host.root, "", {28, 28, 484, 34})
    let button = IconButton.createQuiet(&host.root)
    if withText do
        button.setQuietText("Projects")
    if withIcon do
        button.setIcon(host.theme.icon(.Folder, 16))
    button.setArrowPosition(.RightDownward)
    button.setPosition({190, 28, withText ? 120 : 44, 34})
    discard Label.create(&host.root, "Project folders", {28, 88, 240, 24})
    discard Label.create(&host.root, "Recently opened", {28, 130, 240, 24})

    let popup = MenuCtrl.createPopup(&host.root)
    popup.addItem("Illustrations", "illustrations", host.theme.icon(.Folder, 16))
    popup.addItem("Documents", "documents", host.theme.icon(.Folder, 16), checked: true)
    popup.addSeparator()
    popup.addItem("New folder…", "new", rightName: "Ctrl N")

    var captured: bool
    host.app.sigFrame += func|host = &host, popup, button, golden, withText, captured = &captured|(_)
    {
        if captured[] do
            return
        let body   = popup.localToSurface(popup.getPopupBodyRect())
        let anchor = button.surfaceRect()
        Swag.require(Math.abs(body.y - anchor.bottom() - popup.themeMetrics().menuPopup_AnchorGap) < 0.01)
        if withText
        {
            let textX = body.x + popup.padding.x + popup.themeMetrics().menuPopup_IconMargin + popup.themeMetrics().menuPopup_IconSize + popup.themeMetrics().menuPopup_IconTextMargin
            Swag.require(Math.abs(textX - button.menuAnchorTextLeft(anchor)) <= 0.5)
        }
        else
        {
            Swag.require(Math.abs(body.horzCenter() - anchor.horzCenter()) < 0.01)
        }

        var image = host.render()
        Pixel.Testing.assertImageGolden(&image, golden)
        captured[] = true
        popup.setEndModal(null)
    }

    discard popup.doModal(button, autoDestroy: true)
    Swag.require(captured)
}

#[Swag.TestTag("golden")]
#test
{
    anchoredContextGolden("menu.context.text.encre.hidpi", false, true, false, 1.5)
}

#[Swag.TestTag("golden")]
#test
{
    anchoredContextGolden("menu.context.mixed.paper", true, true, true, 1)
}

#[Swag.TestTag("golden")]
#test
{
    anchoredContextGolden("menu.context.icon.encre", true, false, false, 1)
}
