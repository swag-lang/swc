#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

enum MenuMarkerPalette
{
    Dark
    Light
}

// Renders every non-icon marker together so palette changes cannot make one of them disappear
// or restore excessive visual weight to submenu chevrons.
func assertMenuMarkerGolden(palette: MenuMarkerPalette, golden: string)
{
    var host: Testing.HeadlessHost
    host.setup(360, 240)

    switch palette
    {
    case .Dark:  host.theme.setDark()
    case .Light: host.theme.setLight()
    }

    host.notify(.ThemeChanged)

    let sub = MenuCtrl.createPopup(&host.root)
    sub.addItem("Child command", Menu_Open)

    let popup = MenuCtrl.createPopup(&host.root)
    popup.addItem("Checked option", Menu_New, checked: true)
    let selectedRadio = popup.addRadioItem("Selected choice", Menu_Open, checked: true)
    let clearRadio    = popup.addRadioItem("Available choice", Menu_Quit)
    selectedRadio.icon = host.theme.icon(.RepeatOne, 16)
    clearRadio.icon    = host.theme.icon(.Shuffle, 16)
    Swag.require(selectedRadio.rg == .ExclusiveGroup and clearRadio.rg == .ExclusiveGroup)
    popup.addItem("Downloads", "Menu.Downloads", host.theme.fileGlyph("Downloads", true))
    popup.addPopup("More choices", sub)
    popup.addItem("Unavailable option", "Menu.Disabled", disabled: true, checked: true)
    popup.addRadioItem("Unavailable choice", "Menu.DisabledRadio", disabled: true, checked: true).icon = host.theme.icon(.PlayOnce, 16)

    var captured: bool
    host.app.sigFrame += func|host = &host, golden, captured = &captured|(_)
    {
        if captured[] do
            return
        var image = host.render()
        Pixel.Testing.assertImageGolden(&image, golden)
        let menuDismissed = host.dismissPopupMenu()
        Swag.require(menuDismissed)
        captured[] = true
    }

    discard popup.doModal({24, 20}, .TopLeft, autoDestroy: true)
    Swag.require(captured)
    host.pump()
}

// Menu marker color and submenu restraint are explicit visual contracts in the dark palette.
#[Swag.TestTag("golden")]
#test
{
    assertMenuMarkerGolden(.Dark, "menu.popup.markers.dark")
}

// Menu marker color and submenu restraint are explicit visual contracts in the light palette.
#[Swag.TestTag("golden")]
#test
{
    assertMenuMarkerGolden(.Light, "menu.popup.markers.light")
}

// An icon-button menu keeps a clear gap from its selected opener.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 240)

    let button = IconButton.create(&host.root, host.theme.icon(.Options, 20), {24, 6, 48, 36}, flags: .CenterContent)
    button.setArrowPosition(.RightDownward)

    let popup = MenuCtrl.createPopup(&host.root)
    popup.addItem("Match case", Menu_Open, checked: true)
    popup.addItem("Match whole words", Menu_New)
    popup.addItem("Use regular expression", Menu_Quit)

    var checked: bool
    host.app.sigFrame += func|host = &host, popup, button, checked = &checked|(_)
    {
        if checked[] do
            return
        let anchor = button.surfaceRect()
        Swag.require(popup.popupAnchorButton == button)
        Swag.require(popup.popupBarItemSurfaceRect == anchor)
        Swag.require(popup.getPopupBodyRect().y == popup.getPopupBarAnchorHeight() + popup.themeMetrics().menuPopup_ShadowSize)
        Swag.require(popup.position.y + popup.getPopupBodyRect().y == anchor.bottom() + popup.themeMetrics().menuPopup_AnchorGap)
        var image = host.render()
        Pixel.Testing.assertImageGolden(&image, "menu.popup.icon-anchor")
        let menuDismissed = host.dismissPopupMenu()
        Swag.require(menuDismissed)
        checked[] = true
    }

    discard popup.doModal(button, autoDestroy: true)
    Swag.require(checked)
    host.pump()
}

// A button below its menu keeps the same clear gap above its opener.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 240)

    let button = IconButton.create(&host.root, host.theme.icon(.Redo, 20), {24, 198, 52, 36}, flags: .CenterContent)
    button.setArrowPosition(.RightUpward)

    let popup = MenuCtrl.createPopup(&host.root)
    popup.addItem("Rotate counter-clockwise", Menu_Open, host.theme.icon(.Undo, 16))
    popup.addItem("Rotate clockwise", Menu_New, host.theme.icon(.Redo, 16))
    popup.addSeparator()
    popup.addItem("Reset transform", Menu_Quit, host.theme.icon(.Update, 16))

    var checked: bool
    host.app.sigFrame += func|host = &host, popup, button, checked = &checked|(_)
    {
        if checked[] do
            return
        let anchor = button.surfaceRect()
        Swag.require(popup.popupAnchorButton == button and popup.popupButtonOpensUp)
        Swag.require(popup.position.y + popup.getPopupBodyRect().bottom() == anchor.y - popup.themeMetrics().menuPopup_AnchorGap)
        var image = host.render()
        Pixel.Testing.assertImageGolden(&image, "menu.popup.icon-anchor-up")
        let menuDismissed = host.dismissPopupMenu()
        Swag.require(menuDismissed)
        checked[] = true
    }

    discard popup.doModal(button, autoDestroy: true)
    Swag.require(checked)
    host.pump()
}

// A quiet reading at the foot of a light window aligns with the wording of its popup.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 260)
    host.setReducedMotion(false)
    host.theme.setLight()
    host.notify(.ThemeChanged)

    let button = IconButton.createQuiet(&host.root)
    button.setArrowPosition(.RightUpward)
    button.setQuietText("1931 × 1615")
    button.setPosition({24, 218, button.position.width, 28})

    let popup = MenuCtrl.createPopup(&host.root)
    popup.addItem("Resize Image…", Menu_Open)
    popup.addItem("Expand Image…", Menu_New)
    popup.addItem("Expand Capture…", Menu_Quit)
    popup.addItem("Trim Capture", "Menu.Trim")

    var checked: bool
    host.app.sigFrame += func|host = &host, popup, button, checked = &checked|(_)
    {
        if checked[] do
            return
        Swag.require(popup.popupAnchorButton == button and popup.popupButtonOpensUp)
        Swag.require(popup.presentationOpacity == 1 and popup.presentationOffset == Math.Point{})
        Swag.require(popup.position.y + popup.getPopupBodyRect().bottom() == button.surfaceRect().y - popup.themeMetrics().menuPopup_AnchorGap)
        var image = host.render()
        Pixel.Testing.assertImageGolden(&image, "menu.popup.quiet-anchor-up.light")
        Swag.require(host.dismissPopupMenu())
        checked[] = true
    }

    discard popup.doModal(button, autoDestroy: true)
    Swag.require(checked)
    host.pump()
}

// A button against the right edge keeps its integrated popup against that same edge. The shadow
// may extend outside the client area, but the visible body must not be clamped inward and detached
// from its trigger.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 240)

    let button = IconButton.create(&host.root, host.theme.icon(.Filter, 20), {312, 6, 48, 36}, flags: .CenterContent)
    button.setArrowPosition(.RightDownward)
    let popup = MenuCtrl.createPopup(&host.root)
    popup.addItem("Search", Menu_Open, checked: true)
    popup.addItem("Filter", Menu_New)

    var checked: bool
    host.app.sigFrame += func|host = &host, popup, button, checked = &checked|(_)
    {
        if checked[] do
            return
        let shadow = popup.themeMetrics().menuPopup_ShadowSize
        Swag.require(popup.popupAnchorButton == button)
        Swag.require(popup.position.right() - shadow <= host.root.clientRect().right() - popup.themeMetrics().menuPopup_WindowMargin)
        var image = host.render()
        Pixel.Testing.assertImageGolden(&image, "menu.popup.icon-anchor-right")
        let menuDismissed = host.dismissPopupMenu()
        Swag.require(menuDismissed)
        checked[] = true
    }

    discard popup.doModal(button, autoDestroy: true)
    Swag.require(checked)
    host.pump()
}

// A left-opening submenu marker replaces the unused glyph on its row, even when another row
// makes the popup keep a shared glyph column.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 220)

    let popup = MenuCtrl.createPopup(&host.root)
    let sub   = MenuCtrl.createPopup(&host.root)
    sub.addItem("Sans serif", Menu_Open, checked: true)
    sub.addItem("Monospace", Menu_Quit)
    popup.addItem("Current choice", Menu_New, checked: true, rightName: "Ctrl Enter")
    popup.addPopup("Typography", sub)
    popup.setSubmenuDirection(.Left)

    var checked: bool
    host.app.sigFrame += func|host = &host, checked = &checked|(_)
    {
        if checked[] do
            return
        var image = host.render()
        Pixel.Testing.assertImageGolden(&image, "menu.popup.left")
        let menuDismissed = host.dismissPopupMenu()
        Swag.require(menuDismissed)
        checked[] = true
    }

    discard popup.doModal({348, 204}, .AnchorBottomCenter, autoDestroy: true)
    Swag.require(checked)
    host.pump()
}

// A popup without any visible item glyph whose submenus open on the left reserves one shared
// arrow column, so the wording of every row starts at the same place whether or not its row
// carries the arrow.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 220)

    let sub = MenuCtrl.createPopup(&host.root)
    sub.addItem("Sans serif", Menu_Open)
    sub.addItem("Monospace", Menu_Quit)

    let popup = MenuCtrl.createPopup(&host.root)
    discard popup.addPopup("Typography", sub)
    popup.addItem("Plain item", Menu_New)
    popup.setSubmenuDirection(.Left)
    popup.computeLayoutPopup()

    let iconSub = MenuCtrl.createPopup(&host.root)
    iconSub.addItem("Sans serif", Menu_Open)
    let iconPopup = MenuCtrl.createPopup(&host.root)
    iconPopup.addPopup("Typography", iconSub, icon: host.theme.icon(.Appearance, 16))
    iconPopup.addItem("Plain item", Menu_New)
    iconPopup.setSubmenuDirection(.Left)
    iconPopup.computeLayoutPopup()

    // The shared arrow column is paid for once by the whole popup, so the no-glyph popup ends
    // up wider than the glyph one by the chevron column minus the glyph column it replaces.
    let metrics = popup.themeMetrics()
    Swag.require(Math.abs(popup.position.width - iconPopup.position.width - (metrics.chevron_Size - metrics.menuPopup_IconSize)) < 0.01)

    var checked: bool
    host.app.sigFrame += func|host = &host, checked = &checked|(_)
    {
        if checked[] do
            return
        var image = host.render()
        Pixel.Testing.assertImageGolden(&image, "menu.popup.left.no-icons")
        let menuDismissed = host.dismissPopupMenu()
        Swag.require(menuDismissed)
        checked[] = true
    }

    discard popup.doModal({348, 204}, .AnchorBottomCenter, autoDestroy: true)
    Swag.require(checked)
    host.pump()
}

// A taller menu bar centers its visual/hit item band and uses that band as popup anchor.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    let metrics   = host.root.themeMetrics()
    let barHeight = metrics.menuBar_Height + 12
    let bar       = MenuCtrl.createBar(&host.root, Math.Rectangle{0, 0, 300, barHeight})
    let sub       = MenuCtrl.createPopup(&host.root)
    sub.addItem("Open", Menu_Open)
    bar.addPopup("File", sub)

    bar.computeLayoutBar()
    let expectedItemY = (barHeight - metrics.menuBar_Height) * 0.5

    let barIt0 = unwrap bar.items[0]
    let itemX  = barIt0.pos + barIt0.size * 0.5
    Swag.require(bar.hitTestBar(Math.Point{itemX, 1}) == Swag.U32.Max)
    Swag.require(bar.hitTestBar(Math.Point{itemX, expectedItemY + 1}) == 0)

    host.mouseDown(Math.Point{itemX, expectedItemY + 1})

    Swag.require(sub.popupBarItemSurfaceRect.y == expectedItemY)
    Swag.require(sub.popupBarItemSurfaceRect.height == metrics.menuBar_Height)
    Swag.require(sub.position.y == expectedItemY - metrics.menuPopup_ShadowSize)

    var localAnchor = sub.popupBarItemSurfaceRect
    let popupRect   = sub.surfaceRect()
    localAnchor.x -= popupRect.x
    localAnchor.y -= popupRect.y
    let body = sub.getPopupBodyRect()
    Swag.require(popupRect.x + body.x >= metrics.menuPopup_WindowMargin)
    Swag.require(Math.abs(localAnchor.bottom() + metrics.menuPopup_AnchorGap - body.y) <= metrics.wnd_BorderSize)

    var image = host.render()
    Pixel.Testing.assertImageGolden(&image, "menu.popup.text-anchor.tall")

    host.mouseUp({0, 0})
}
