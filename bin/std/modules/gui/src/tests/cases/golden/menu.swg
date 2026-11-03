#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Dynamic navigation targets remain valid after the source collection has been released.

// An automatically destroyed popup retires its surface-sibling submenus before their owner.

const Menu_New  = "Menu.New"
const Menu_Open = "Menu.Open"
const Menu_Quit = "Menu.Quit"

var MenuSelectedCount: u32

// Stands for a string table field: a resolver reads it again on every layout.
var MenuResolvedLabel: string = "Open"

func menuResolvedLabel()->string => MenuResolvedLabel

func menuCommandSelected(_: *MenuCtrl, id: WndId)
{
    if id == Menu_Open do
        MenuSelectedCount += 1
}

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
    Swag.assert(selectedRadio.rg == .ExclusiveGroup and clearRadio.rg == .ExclusiveGroup)
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
        Swag.assert(menuDismissed)
        captured[] = true
    }

    discard popup.doModal({24, 20}, .TopLeft, autoDestroy: true)
    Swag.assert(captured)
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

// A menu bar holds items; a popup menu holds items, separators and disabled entries.

// An entry built from a resolver re-reads its label on every layout; one built from a
// literal keeps the wording it was created with.

// A submenu carries a resolver the same way, and a language change asks the bar to
// measure itself again.

// A bar entry reserves what its label really occupies at the density it is drawn at.
//
// Laid out at a scale of one and drawn at another, a run comes out wider than the width
// reserved for it and the entry loses its last glyph to the clip — a shortfall that grows
// with the word, so a long translation is where it shows.

// Headless tests can drive modal popup menus through the normal mouse pipeline.

// A modal menu's queued command keeps the identifier selected before its caller changes it.

// A submenu label keeps its complete measured run beside the reserved chevron band.

// Headless popup menus can drive nested submenus through hover/timer behavior.

// A centred popup fitted at the right edge keeps its notch under the requested anchor.

// Clicking outside a captured popup dismisses it without selecting an item.

// An icon-button menu carries the button itself into the popup outline, with no detached notch.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 240)

    let button = IconButton.create(&host.root, host.theme.icon(.Options, 20), {24, 6, 48, 36}, flags: .CenterContent)
    button.setArrowPosition(.RightDownward)
    Swag.assert(button.themeRects().menuPopup_BarAnchorBk.radius == button.themeRects().btnIcon_RoundSquareBk.radius)

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
        Swag.assert(popup.popupAnchorButton == button)
        Swag.assert(popup.popupBarItemSurfaceRect == anchor)
        Swag.assert(popup.getPopupBodyRect().y == popup.getPopupBarAnchorHeight() + popup.themeMetrics().menuPopup_ShadowSize)
        Swag.assert(popup.position.y + popup.getPopupBodyRect().y == anchor.bottom())
        var image = host.render()
        Pixel.Testing.assertImageGolden(&image, "menu.popup.icon-anchor")
        let menuDismissed = host.dismissPopupMenu()
        Swag.assert(menuDismissed)
        checked[] = true
    }

    discard popup.doModal(button, autoDestroy: true)
    Swag.assert(checked)
    host.pump()
}

// A button below its menu carries the same integrated outline, reflected around the shared edge.
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
        Swag.assert(popup.popupAnchorButton == button and popup.popupButtonOpensUp)
        Swag.assert(popup.position.y + popup.getPopupBodyRect().bottom() == anchor.y)
        var image = host.render()
        Pixel.Testing.assertImageGolden(&image, "menu.popup.icon-anchor-up")
        let menuDismissed = host.dismissPopupMenu()
        Swag.assert(menuDismissed)
        checked[] = true
    }

    discard popup.doModal(button, autoDestroy: true)
    Swag.assert(checked)
    host.pump()
}

// An anchored menu that is taller than the room above its button keeps its shadow and content
// inside the top edge instead of leaving the menu body glued beyond the window.

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
        Swag.assert(popup.popupAnchorButton == button)
        Swag.assert(popup.position.right() >= host.root.clientRect().right() - shadow)
        var image = host.render()
        Pixel.Testing.assertImageGolden(&image, "menu.popup.icon-anchor-right")
        let menuDismissed = host.dismissPopupMenu()
        Swag.assert(menuDismissed)
        checked[] = true
    }

    discard popup.doModal(button, autoDestroy: true)
    Swag.assert(checked)
    host.pump()
}

// A submenu at the right edge chooses the available left side as a complete rectangle.

// A caller can keep child menus and their markers on the left even when the right side also fits.

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
        Swag.assert(menuDismissed)
        checked[] = true
    }

    discard popup.doModal({348, 204}, .AnchorBottomCenter, autoDestroy: true)
    Swag.assert(checked)
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
    Swag.assert(Math.abs(popup.position.width - iconPopup.position.width - (metrics.chevron_Size + metrics.menuPopup_IconMargin - metrics.menuPopup_IconSize)) < 0.01)

    var checked: bool
    host.app.sigFrame += func|host = &host, checked = &checked|(_)
    {
        if checked[] do
            return
        var image = host.render()
        Pixel.Testing.assertImageGolden(&image, "menu.popup.left.no-icons")
        let menuDismissed = host.dismissPopupMenu()
        Swag.assert(menuDismissed)
        checked[] = true
    }

    discard popup.doModal({348, 204}, .AnchorBottomCenter, autoDestroy: true)
    Swag.assert(checked)
    host.pump()
}

// Hidden popup rows keep their previous layout values, but they must not
// intercept the row now visible under the mouse.

// A popup item links a submenu back to its owner.

// Opening a menu-bar popup on press must not be cancelled by the release
// captured by the newly shown popup.

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
    Swag.assert(bar.hitTestBar(Math.Point{itemX, 1}) == Swag.U32.Max)
    Swag.assert(bar.hitTestBar(Math.Point{itemX, expectedItemY + 1}) == 0)

    host.mouseDown(Math.Point{itemX, expectedItemY + 1})

    Swag.assert(sub.popupBarItemSurfaceRect.y == expectedItemY)
    Swag.assert(sub.popupBarItemSurfaceRect.height == metrics.menuBar_Height)
    Swag.assert(sub.position.y == expectedItemY - metrics.menuPopup_ShadowSize)

    var localAnchor = sub.popupBarItemSurfaceRect
    let popupRect   = sub.surfaceRect()
    localAnchor.x -= popupRect.x
    localAnchor.y -= popupRect.y
    let body = sub.getPopupBodyRect()
    Swag.assert(Math.abs(localAnchor.x - body.x) <= metrics.wnd_BorderSize)
    Swag.assert(Math.abs(localAnchor.bottom() - body.y) <= metrics.wnd_BorderSize)

    var image = host.render()
    Pixel.Testing.assertImageGolden(&image, "menu.popup.text-anchor.tall")

    host.mouseUp({0, 0})
}

// A menu-bar popup carries the opened bar item inside its own themed area.

// A menu opened from the end of a line stands with its top-right corner on the anchor, and an
// entry that destroys something is set apart in the critical ink.
