#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

const Menu_New  = "Menu.New"
const Menu_Open = "Menu.Open"
const Menu_Quit = "Menu.Quit"

var MenuSelectedCount: u32

// Stands for a string table field: a resolver reads it again on every layout.
var MenuResolvedLabel: string = "Open"

func menuResolvedLabel()->string => MenuResolvedLabel

func menuCommandSelected(menu: *MenuCtrl, id: WndId)
{
    discard menu
    if id == Menu_Open do
        MenuSelectedCount += 1
}

enum MenuMarkerPalette
{
    Dark
    Light
    SwagDark
}

// Renders every non-icon marker together so palette changes cannot make one of them disappear
// or restore excessive visual weight to submenu chevrons.
func assertMenuMarkerGolden(palette: MenuMarkerPalette, golden: string)
{
    var host: Testing.HeadlessHost
    host.setup(360, 240)
    defer host.shutdown()

    switch palette
    {
    case .Dark:     host.theme.setDark()
    case .Light:    host.theme.setLight()
    case .SwagDark: host.theme.setSwagDark()
    }

    host.notify(.ThemeChanged)

    let sub = MenuCtrl.createPopup(&host.root)
    sub.addItem("Child command", Menu_Open)

    let popup = MenuCtrl.createPopup(&host.root)
    popup.addItem("Checked option", Menu_New, checked: true)
    let selectedRadio = popup.addItem("Selected choice", Menu_Open, checked: true)
    selectedRadio.rg = .ExclusiveGroup
    let clearRadio = popup.addItem("Available choice", Menu_Quit)
    clearRadio.rg = .ExclusiveGroup
    popup.addPopup("More choices", sub)
    popup.addItem("Unavailable option", "Menu.Disabled", disabled: true, checked: true)

    var captured: bool
    host.app.sigFrame += func|host = &host, golden, captured = &captured|(app)
    {
        discard app
        if captured[] do
            return
        var image = host.render()
        Pixel.Testing.assertImageGolden(&image, golden)
        Swag.assert(host.dismissPopupMenu())
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

// Menu marker color and submenu restraint are explicit visual contracts in the Swag palette.
#[Swag.TestTag("golden")]
#test
{
    assertMenuMarkerGolden(.SwagDark, "menu.popup.markers.swag-dark")
}

// A menu bar holds items; a popup menu holds items, separators and disabled entries.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()
    let bar = MenuCtrl.createBar(&host.root, {0, 0, 300, 0})
    bar.addItem("New", Menu_New)
    Swag.assert(bar.items.count == 1)
    Swag.assert(bar.items[0]!.name.raw == "New")
    Swag.assert(bar.items[0]!.id == Menu_New)

    let sub = MenuCtrl.createPopup(&host.root)
    sub.addItem("Open", Menu_Open)
    sub.addSeparator()
    sub.addItem("Quit", Menu_Quit, disabled: true)

    Swag.assert(sub.items.count == 3)
    sub.computeLayoutPopup()
    Swag.assert(sub.themeMetrics().menuPopup_IconSize == 16)
    Swag.assert(sub.themeMetrics().menuPopup_ItemHeight == 24)
    Swag.assert(sub.items[0]!.size + sub.themeMetrics().menuPopup_SpaceLines >= sub.themeMetrics().menuPopup_ItemHeight)
    Swag.assert(!sub.items[0]!.separator)
    Swag.assert(sub.items[1]!.separator)
    Swag.assert(sub.items[2]!.disabled)
    Swag.assert(sub.items[2]!.name.raw == "Quit")
    Swag.assert(sub.itemAt(2).id == Menu_Quit)

    sub.removeItemAt(1)
    Swag.assert(sub.items.count == 2)
    sub.clear()
    Swag.assert(sub.items.isEmpty())
}

// An entry built from a resolver re-reads its label on every layout; one built from a
// literal keeps the wording it was created with.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()

    MenuResolvedLabel = "Open"
    let bar = MenuCtrl.createBar(&host.root, {0, 0, 300, 0})
    bar.addItem("New", Menu_New)
    bar.addItem(&menuResolvedLabel, Menu_Open)

    // The resolver already answers once, so the item is usable before any layout.
    Swag.assert(bar.items[1]!.name.raw == "Open")

    MenuResolvedLabel = "Ouvrir"
    bar.computeLayoutBar()
    Swag.assert(bar.items[1]!.name.raw == "Ouvrir")
    Swag.assert(bar.items[0]!.name.raw == "New")

    // A longer label widens its own entry and pushes the next one along.
    let widened = bar.items[1]!.size
    MenuResolvedLabel = "Ouvrir un fichier"
    bar.computeLayoutBar()
    Swag.assert(bar.items[1]!.size > widened)
}

// A submenu carries a resolver the same way, and a language change asks the bar to
// measure itself again.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()

    MenuResolvedLabel = "File"
    let sub = MenuCtrl.createPopup(&host.root)
    sub.addItem("Quit", Menu_Quit)

    let bar = MenuCtrl.createBar(&host.root, {0, 0, 300, 0})
    bar.addPopup(&menuResolvedLabel, sub)
    Swag.assert(bar.items[0]!.name.raw == "File")
    Swag.assert(bar.items[0]!.popup == sub)

    bar.computeLayoutBar()
    bar.dirtyLayout = false

    MenuResolvedLabel = "Fichier"
    var evt = NotifyEvent{}
    evt.kind = .LanguageChanged
    bar.sendEvent(&evt)
    Swag.assert(bar.dirtyLayout)

    bar.computeLayoutBar()
    Swag.assert(bar.items[0]!.name.raw == "Fichier")
}

// A bar entry reserves what its label really occupies at the density it is drawn at.
//
// Laid out at a scale of one and drawn at another, a run comes out wider than the width
// reserved for it and the entry loses its last glyph to the clip — a shortfall that grows
// with the word, so a long translation is where it shows.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200, 1.5)
    defer host.shutdown()

    let bar = MenuCtrl.createBar(&host.root, {0, 0, 380, 0})
    bar.addItem("Affichage", Menu_New)
    bar.computeLayoutBar()

    var rsf: Pixel.RichStringFormat
    rsf.font = bar.font()

    func measure(text: string, format: Pixel.RichStringFormat, scale: f32)->f32
    {
        var run: Pixel.RichString
        run.set(text)
        run.compute()
        Pixel.Painter.computeLayout({0, 0, MaxTextLayoutExtent, MaxTextLayoutExtent}, &run, format, scale)
        return run.boundRect.width
    }

    let drawn = measure("Affichage", rsf, bar.deviceScale())
    Swag.assert(bar.deviceScale() == 1.5)
    Swag.assert(bar.items[0]!.size >= drawn)

    // The scale is what decides: measuring at one under-counts every glyph advance, which
    // is exactly the width the entry used to be short of.
    Swag.assert(measure("Affichage", rsf, 1.0) <= drawn)
}

// Headless tests can drive modal popup menus through the normal mouse pipeline.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()
    let popup = MenuCtrl.createPopup(&host.root)
    popup.addItem("Open", Menu_Open)
    popup.addItem("Quit", Menu_Quit)
    MenuSelectedCount        = 0
    popup.sigCommandSelected += &menuCommandSelected

    var frameCount: u32
    var didClick:   bool
    host.app.sigFrame += func|host = &host, popup, frames = &frameCount, didClick = &didClick|(app)
    {
        frames[] += 1
        if !didClick[]
        {
            Swag.assert(host.capturedPopupMenu() == popup)
            Swag.assert(host.clickPopupMenuItem(Menu_Open))
            didClick[] = true
        }
    }

    let result = popup.doModal({40, 40}, autoDestroy: true)

    Swag.assert(result == Menu_Open)
    Swag.assert(MenuSelectedCount == 1)
    Swag.assert(frameCount == 1)
    Swag.assert(didClick)
    Swag.assert(host.app.mouseCaptureWnd == null)

    host.pump()
}

// A submenu label keeps its complete measured run beside the reserved chevron band.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()

    let sub = MenuCtrl.createPopup(&host.root)
    sub.addItem("System language", Menu_Open)
    let popup = MenuCtrl.createPopup(&host.root)
    popup.updateFlags(.HideShortcuts)
    let item = popup.addPopup("Language", sub)
    popup.computeLayoutPopup()

    let metrics     = popup.themeMetrics()
    let shadowWidth = 2 * metrics.menuPopup_ShadowSize
    let chromeWidth = metrics.menuPopup_IconSize + metrics.menuPopup_IconMargin + metrics.menuPopup_IconTextMargin + metrics.chevron_Size + popup.padding.x + popup.padding.z + shadowWidth
    Swag.assert(metrics.chevron_Size == 12)
    Swag.assert(metrics.menuPopup_WindowMargin == 8)
    Swag.assert(popup.position.width - chromeWidth + 0.01 >= item.name.boundRect.width)
}

// Headless popup menus can drive nested submenus through hover/timer behavior.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()
    let popup = MenuCtrl.createPopup(&host.root)
    let sub   = MenuCtrl.createPopup(&host.root)
    sub.addItem("Open", Menu_Open)
    popup.addPopup("More", sub)
    popup.setSubmenuDirection(.Right)
    Swag.assert(popup.submenuDirection == .Right)

    var didOpen:     bool
    var didClick:    bool
    var hidTogether: bool
    sub.sigCommandSelected += func|popup, sub, hidTogether = &hidTogether|(menu, id)
    {
        discard menu
        discard id
        hidTogether[] = popup.isHidden() and sub.isHidden()
    }
    host.app.sigFrame += func|host = &host, popup, sub, opened = &didOpen, clicked = &didClick|(app)
    {
        if !opened[]
        {
            Swag.assert(host.openPopupSubMenu("More"))
            Swag.assert(sub.position.x >= popup.position.right() - 2 * popup.themeMetrics().menuPopup_ShadowSize)
            opened[] = true
        }
        elif !clicked[]
        {
            Swag.assert(host.clickPopupMenuItem(Menu_Open))
            clicked[] = true
        }
    }

    let result = popup.doModal({40, 40}, autoDestroy: true)

    Swag.assert(result == Menu_Open)
    Swag.assert(didOpen)
    Swag.assert(didClick)
    Swag.assert(hidTogether)
    Swag.assert(host.app.mouseCaptureWnd == null)

    host.pump()
}

// A centred popup fitted at the right edge keeps its notch under the requested anchor.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()

    let popup = MenuCtrl.createPopup(&host.root)
    popup.addItem("Actual size", Menu_Open)
    popup.addItem("Fit to view", Menu_Quit)

    let anchor = Math.Point{310, 40}
    var checked: bool
    host.app.sigFrame += func|host = &host, popup, anchor, checked = &checked|(app)
    {
        if checked[] do
            return

        let margin = popup.themeMetrics().menuPopup_WindowMargin
        Swag.assert(popup.position.x >= margin)
        Swag.assert(popup.position.right() <= host.root.position.width - margin)
        Swag.assert(Math.abs(popup.position.x + popup.anchorPosition - anchor.x) < 0.5)
        Swag.assert(host.clickPopupMenuItem(Menu_Open))
        checked[] = true
    }

    Swag.assert(popup.doModal(anchor, .AnchorTopCenter, autoDestroy: true) == Menu_Open)
    Swag.assert(checked)
    host.pump()
}

// Clicking outside a captured popup dismisses it without selecting an item.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()
    let popup = MenuCtrl.createPopup(&host.root)
    popup.addItem("Open", Menu_Open)

    var didDismiss: bool
    host.app.sigFrame += func|host = &host, dismissed = &didDismiss|(app)
    {
        if !dismissed[]
        {
            Swag.assert(host.dismissPopupMenu())
            dismissed[] = true
        }
    }

    let result = popup.doModal({40, 40}, autoDestroy: true)

    Swag.assert(result == null)
    Swag.assert(didDismiss)
    Swag.assert(host.app.mouseCaptureWnd == null)

    host.pump()
}

// An icon-button menu carries the button itself into the popup outline, with no detached notch.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 240)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let button = IconButton.create(&host.root, host.theme.icon(.Options, 20), {24, 6, 48, 36}, flags: .CenterContent)
    button.setArrowPosition(.RightDownward)
    Swag.assert(button.themeRects().menuPopup_BarAnchorBk.radius == button.themeRects().btnIcon_RoundSquareBk.radius)

    let popup = MenuCtrl.createPopup(&host.root)
    popup.addItem("Match case", Menu_Open, checked: true)
    popup.addItem("Match whole words", Menu_New)
    popup.addItem("Use regular expression", Menu_Quit)

    var checked: bool
    host.app.sigFrame += func|host = &host, popup, button, checked = &checked|(app)
    {
        discard app
        if checked[] do
            return
        let anchor = button.surfaceRect()
        Swag.assert(popup.popupAnchorButton == button)
        Swag.assert(popup.popupBarItemSurfaceRect == anchor)
        Swag.assert(popup.getPopupBodyRect().y == popup.getPopupBarAnchorHeight() + popup.themeMetrics().menuPopup_ShadowSize)
        Swag.assert(popup.position.y + popup.getPopupBodyRect().y == anchor.bottom())
        var image = host.render()
        Pixel.Testing.assertImageGolden(&image, "menu.popup.icon-anchor")
        Swag.assert(host.dismissPopupMenu())
        checked[] = true
    }

    discard popup.doModal(button, autoDestroy: true)
    Swag.assert(checked)
    host.pump()
}

// An anchored menu that is taller than the room above its button keeps its shadow and content
// inside the top edge instead of leaving the menu body glued beyond the window.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 160)
    defer host.shutdown()

    let popup = MenuCtrl.createPopup(&host.root)
    for index in 8 do
        popup.addItem(Format.toString("Caption %", index).toString(), Menu_Open)

    var checked: bool
    host.app.sigFrame += func|host = &host, popup, checked = &checked|(app)
    {
        discard app
        if checked[] do
            return
        let margin = popup.themeMetrics().menuPopup_WindowMargin
        Swag.assert(popup.position.x >= margin and popup.position.y >= margin)
        Swag.assert(popup.position.right() <= host.root.position.width - margin)
        Swag.assert(host.dismissPopupMenu())
        checked[] = true
    }

    discard popup.doModal({310, 18}, .AnchorBottomCenter, autoDestroy: true)
    Swag.assert(checked)
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
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let button = IconButton.create(&host.root, host.theme.icon(.Filter, 20), {312, 6, 48, 36}, flags: .CenterContent)
    button.setArrowPosition(.RightDownward)
    let popup = MenuCtrl.createPopup(&host.root)
    popup.addItem("Search", Menu_Open, checked: true)
    popup.addItem("Filter", Menu_New)

    var checked: bool
    host.app.sigFrame += func|host = &host, popup, button, checked = &checked|(app)
    {
        discard app
        if checked[] do
            return
        let shadow = popup.themeMetrics().menuPopup_ShadowSize
        Swag.assert(popup.popupAnchorButton == button)
        Swag.assert(popup.position.right() >= host.root.clientRect().right() - shadow)
        var image = host.render()
        Pixel.Testing.assertImageGolden(&image, "menu.popup.icon-anchor-right")
        Swag.assert(host.dismissPopupMenu())
        checked[] = true
    }

    discard popup.doModal(button, autoDestroy: true)
    Swag.assert(checked)
    host.pump()
}

// A submenu at the right edge chooses the available left side as a complete rectangle.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()

    let popup = MenuCtrl.createPopup(&host.root)
    let sub   = MenuCtrl.createPopup(&host.root)
    sub.addItem("Open", Menu_Open)
    popup.addPopup("More choices", sub)

    var checked: bool
    host.app.sigFrame += func|host = &host, popup, sub, checked = &checked|(app)
    {
        discard app
        if checked[] do
            return
        Swag.assert(host.openPopupSubMenu("More choices"))
        Swag.assert(sub.position.x >= popup.themeMetrics().menuPopup_WindowMargin)
        Swag.assert(sub.position.right() <= popup.position.x + 2 * popup.themeMetrics().menuPopup_ShadowSize)
        Swag.assert(host.clickPopupMenuItem(Menu_Open))
        checked[] = true
    }

    Swag.assert(popup.doModal({315, 50}, .AnchorTopCenter, autoDestroy: true) == Menu_Open)
    Swag.assert(checked)
    host.pump()
}

// A caller can keep child menus and their markers on the left even when the right side also fits.
#test
{
    var host: Testing.HeadlessHost
    host.setup(520, 220)
    defer host.shutdown()

    let popup = MenuCtrl.createPopup(&host.root)
    let sub   = MenuCtrl.createPopup(&host.root)
    sub.addItem("Open", Menu_Open)
    popup.addPopup("More choices", sub)
    popup.setSubmenuDirection(.Left)
    Swag.assert(popup.submenuDirection == .Left)

    var checked: bool
    host.app.sigFrame += func|host = &host, popup, sub, checked = &checked|(app)
    {
        discard app
        if checked[] do
            return
        Swag.assert(host.openPopupSubMenu("More choices"))
        Swag.assert(sub.position.right() <= popup.position.x + 2 * popup.themeMetrics().menuPopup_ShadowSize)
        Swag.assert(host.clickPopupMenuItem(Menu_Open))
        checked[] = true
    }

    Swag.assert(popup.doModal({280, 50}, autoDestroy: true) == Menu_Open)
    Swag.assert(checked)
    host.pump()
}

// A left-opening submenu marker replaces the unused glyph on its row, even when another row
// makes the popup keep a shared glyph column.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 220)
    defer host.shutdown()

    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let popup = MenuCtrl.createPopup(&host.root)
    let sub   = MenuCtrl.createPopup(&host.root)
    sub.addItem("Sans serif", Menu_Open, checked: true)
    sub.addItem("Monospace", Menu_Quit)
    popup.addItem("Current choice", Menu_New, checked: true, rightName: "Ctrl+Enter")
    popup.addPopup("Typography", sub)
    popup.setSubmenuDirection(.Left)

    var checked: bool
    host.app.sigFrame += func|host = &host, checked = &checked|(app)
    {
        discard app
        if checked[] do
            return
        var image = host.render()
        Pixel.Testing.assertImageGolden(&image, "menu.popup.left")
        Swag.assert(host.dismissPopupMenu())
        checked[] = true
    }

    discard popup.doModal({348, 204}, .AnchorBottomCenter, autoDestroy: true)
    Swag.assert(checked)
    host.pump()
}

// A left-opening submenu without any visible item glyph collapses the unused glyph column, so
// its wording follows the leading chevron at the normal icon-to-text distance.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 220)
    defer host.shutdown()

    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let sub = MenuCtrl.createPopup(&host.root)
    sub.addItem("Sans serif", Menu_Open)
    sub.addItem("Monospace", Menu_Quit)

    let popup = MenuCtrl.createPopup(&host.root)
    let item  = popup.addPopup("Typography", sub)
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

    let metrics = popup.themeMetrics()
    Swag.assert(Math.abs(iconPopup.position.width - popup.position.width - (metrics.menuPopup_IconSize + metrics.menuPopup_IconTextMargin - metrics.menuPopup_IconMargin)) < 0.01)

    var checked: bool
    host.app.sigFrame += func|host = &host, checked = &checked|(app)
    {
        discard app
        if checked[] do
            return
        var image = host.render()
        Pixel.Testing.assertImageGolden(&image, "menu.popup.left.no-icons")
        Swag.assert(host.dismissPopupMenu())
        checked[] = true
    }

    discard popup.doModal({348, 204}, .AnchorBottomCenter, autoDestroy: true)
    Swag.assert(checked)
    host.pump()
}

// Hidden popup rows keep their previous layout values, but they must not
// intercept the row now visible under the mouse.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()
    let popup = MenuCtrl.createPopup(&host.root)
    popup.addItem("Open", Menu_Open)
    popup.addItem("Hidden", "Menu.Hidden")
    popup.addSeparator()
    popup.addSeparator()
    popup.addItem("Quit", Menu_Quit)

    // Consecutive separators collapse into one, so this is Open / Hidden / --- / Quit.
    Swag.assert(popup.items.count == 4)

    let hiddenIt = popup.items[1]!
    let quitIt   = popup.items[3]!
    hiddenIt.hidden = true
    popup.computeLayoutPopup()
    popup.setPosition({0, 0, popup.position.width, popup.position.height})

    // Move the hidden row on top of Quit: it keeps its stale layout but must not steal the hit.
    hiddenIt.pos  = quitIt.pos
    hiddenIt.size = quitIt.size

    let pointOnQuit = Math.Point{popup.position.width * 0.5, quitIt.pos + quitIt.size * 0.5}
    Swag.assert(popup.hitTestPopup(pointOnQuit) == 3)
}

// A popup item links a submenu back to its owner.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()
    let bar = MenuCtrl.createBar(&host.root, {0, 0, 300, 0})
    bar.addItem("New", Menu_New)

    let sub = MenuCtrl.createPopup(&host.root)
    sub.addItem("Open", Menu_Open)
    bar.addPopup("File", sub)

    Swag.assert(bar.items.count == 2)
    Swag.assert(bar.items[1]!.name.raw == "File")
    Swag.assert(bar.items[1]!.popup == sub)
    Swag.assert(sub.ownerMenu == bar)
}

// Opening a menu-bar popup on press must not be cancelled by the release
// captured by the newly shown popup.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()
    let bar = MenuCtrl.createBar(&host.root, {0, 0, 300, 0})
    let sub = MenuCtrl.createPopup(&host.root)
    sub.addItem("Open", Menu_Open)
    bar.addPopup("File", sub)

    bar.computeLayoutBar()
    let barIt0 = bar.items[0]!
    let itemX  = barIt0.pos + barIt0.size * 0.5
    let itemY  = bar.position.height * 0.5

    host.mouseDown({itemX, itemY})

    Swag.assert(bar.subVisible == sub)
    Swag.assert(sub.ignoreNextRelease)

    host.mouseUp({0, 0})

    Swag.assert(bar.subVisible == sub)
    Swag.assert(!sub.ignoreNextRelease)
}

// A taller menu bar centers its visual/hit item band and uses that band as popup anchor.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()
    let metrics   = host.root.themeMetrics()
    let barHeight = metrics.menuBar_Height + 12
    let bar       = MenuCtrl.createBar(&host.root, {0, 0, 300, barHeight})
    let sub       = MenuCtrl.createPopup(&host.root)
    sub.addItem("Open", Menu_Open)
    bar.addPopup("File", sub)

    bar.computeLayoutBar()
    let expectedItemY = (barHeight - metrics.menuBar_Height) * 0.5

    let barIt0 = bar.items[0]!
    let itemX  = barIt0.pos + barIt0.size * 0.5
    Swag.assert(bar.hitTestBar({itemX, 1}) == Swag.U32.Max)
    Swag.assert(bar.hitTestBar({itemX, expectedItemY + 1}) == 0)

    host.mouseDown({itemX, expectedItemY + 1})

    Swag.assert(sub.popupBarItemSurfaceRect.y == expectedItemY)
    Swag.assert(sub.popupBarItemSurfaceRect.height == metrics.menuBar_Height)
    Swag.assert(sub.position.y == Math.max(expectedItemY - metrics.menuPopup_ShadowSize, 0))

    var image = host.render()
    Pixel.Testing.assertImageGolden(&image, "menu.popup.text-anchor.tall")

    host.mouseUp({0, 0})
}

// A menu-bar popup carries the opened bar item inside its own themed area.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()
    let metrics = host.root.themeMetrics()
    let bar     = MenuCtrl.createBar(&host.root, {0, 0, 300, 0})
    let sub     = MenuCtrl.createPopup(&host.root)
    sub.addItem("Open", Menu_Open)
    bar.addPopup("File", sub)

    bar.computeLayoutBar()
    bar.hotIdx = 0
    bar.showHotPopup()

    Swag.assert(bar.subVisible == sub)
    Swag.assert(sub.popupBarItemIdx == 0)
    Swag.assert(sub.popupBarItemSurfaceRect.height == bar.position.height)
    Swag.assert(sub.position.y == 0)
    Swag.assert(sub.items[0]!.pos > metrics.menuPopup_ShadowSize + bar.position.height)
}
