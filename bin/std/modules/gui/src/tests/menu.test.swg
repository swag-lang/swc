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

// A menu bar holds items; a popup menu holds items, separators and disabled entries.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    defer host.shutdown()
    let bar = MenuCtrl.createBar(&host.root, {0, 0, 300, 0})
    bar.addItem("New", Menu_New)
    @assert(bar.items.count == 1)
    @assert(bar.items[0]!.name.raw == "New")
    @assert(bar.items[0]!.id == Menu_New)

    let sub = MenuCtrl.createPopup(&host.root)
    sub.addItem("Open", Menu_Open)
    sub.addSeparator()
    sub.addItem("Quit", Menu_Quit, disabled: true)

    @assert(sub.items.count == 3)
    sub.computeLayoutPopup()
    @assert(sub.themeMetrics().menuPopup_IconSize == 16)
    @assert(sub.themeMetrics().menuPopup_ItemHeight == 24)
    @assert(sub.items[0]!.size + sub.themeMetrics().menuPopup_SpaceLines >= sub.themeMetrics().menuPopup_ItemHeight)
    @assert(!sub.items[0]!.separator)
    @assert(sub.items[1]!.separator)
    @assert(sub.items[2]!.disabled)
    @assert(sub.items[2]!.name.raw == "Quit")
    @assert(sub.itemAt(2).id == Menu_Quit)

    sub.removeItemAt(1)
    @assert(sub.items.count == 2)
    sub.clear()
    @assert(sub.items.isEmpty())
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
    @assert(bar.items[1]!.name.raw == "Open")

    MenuResolvedLabel = "Ouvrir"
    bar.computeLayoutBar()
    @assert(bar.items[1]!.name.raw == "Ouvrir")
    @assert(bar.items[0]!.name.raw == "New")

    // A longer label widens its own entry and pushes the next one along.
    let widened = bar.items[1]!.size
    MenuResolvedLabel = "Ouvrir un fichier"
    bar.computeLayoutBar()
    @assert(bar.items[1]!.size > widened)
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
    @assert(bar.items[0]!.name.raw == "File")
    @assert(bar.items[0]!.popup == sub)

    bar.computeLayoutBar()
    bar.dirtyLayout = false

    MenuResolvedLabel = "Fichier"
    var evt = NotifyEvent{}
    evt.kind = .LanguageChanged
    bar.sendEvent(&evt)
    @assert(bar.dirtyLayout)

    bar.computeLayoutBar()
    @assert(bar.items[0]!.name.raw == "Fichier")
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
    @assert(bar.deviceScale() == 1.5)
    @assert(bar.items[0]!.size >= drawn)

    // The scale is what decides: measuring at one under-counts every glyph advance, which
    // is exactly the width the entry used to be short of.
    @assert(measure("Affichage", rsf, 1.0) <= drawn)
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
            @assert(host.capturedPopupMenu() == popup)
            @assert(host.clickPopupMenuItem(Menu_Open))
            didClick[] = true
        }
    }

    let result = popup.doModal({40, 40}, autoDestroy: true)

    @assert(result == Menu_Open)
    @assert(MenuSelectedCount == 1)
    @assert(frameCount == 1)
    @assert(didClick)
    @assert(host.app.mouseCaptureWnd == null)

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
    @assert(metrics.chevron_Size == 12)
    @assert(metrics.menuPopup_WindowMargin == 8)
    @assert(popup.position.width - chromeWidth + 0.01 >= item.name.boundRect.width)
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
    @assert(popup.submenuDirection == .Right)

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
            @assert(host.openPopupSubMenu("More"))
            @assert(sub.position.x >= popup.position.right() - 2 * popup.themeMetrics().menuPopup_ShadowSize)
            opened[] = true
        }
        elif !clicked[]
        {
            @assert(host.clickPopupMenuItem(Menu_Open))
            clicked[] = true
        }
    }

    let result = popup.doModal({40, 40}, autoDestroy: true)

    @assert(result == Menu_Open)
    @assert(didOpen)
    @assert(didClick)
    @assert(hidTogether)
    @assert(host.app.mouseCaptureWnd == null)

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
        @assert(popup.position.x >= margin)
        @assert(popup.position.right() <= host.root.position.width - margin)
        @assert(Math.abs(popup.position.x + popup.anchorPosition - anchor.x) < 0.5)
        @assert(host.clickPopupMenuItem(Menu_Open))
        checked[] = true
    }

    @assert(popup.doModal(anchor, .AnchorTopCenter, autoDestroy: true) == Menu_Open)
    @assert(checked)
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
            @assert(host.dismissPopupMenu())
            dismissed[] = true
        }
    }

    let result = popup.doModal({40, 40}, autoDestroy: true)

    @assert(result == null)
    @assert(didDismiss)
    @assert(host.app.mouseCaptureWnd == null)

    host.pump()
}

// An icon-button menu carries the button itself into the popup outline, with no detached notch.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 240)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let button = IconButton.create(&host.root, host.theme.icon(.Options, 20), {24, 6, 48, 36}, flags: .CenterContent)
    button.setArrowPosition(.RightDownward)
    @assert(button.themeRects().menuPopup_BarAnchorBk.radius == button.themeRects().btnIcon_RoundSquareBk.radius)

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
        @assert(popup.popupAnchorButton == button)
        @assert(popup.popupBarItemSurfaceRect == anchor)
        @assert(popup.getPopupBodyRect().y == popup.getPopupBarAnchorHeight() + popup.themeMetrics().menuPopup_ShadowSize)
        @assert(popup.position.y + popup.getPopupBodyRect().y == anchor.bottom())
        var image = host.render()
        Pixel.Testing.assertImageGolden(&image, "menu.popup.icon-anchor")
        @assert(host.dismissPopupMenu())
        checked[] = true
    }

    discard popup.doModal(button, autoDestroy: true)
    @assert(checked)
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
        @assert(popup.position.x >= margin and popup.position.y >= margin)
        @assert(popup.position.right() <= host.root.position.width - margin)
        @assert(host.dismissPopupMenu())
        checked[] = true
    }

    discard popup.doModal({310, 18}, .AnchorBottomCenter, autoDestroy: true)
    @assert(checked)
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
        @assert(host.openPopupSubMenu("More choices"))
        @assert(sub.position.x >= popup.themeMetrics().menuPopup_WindowMargin)
        @assert(sub.position.right() <= popup.position.x + 2 * popup.themeMetrics().menuPopup_ShadowSize)
        @assert(host.clickPopupMenuItem(Menu_Open))
        checked[] = true
    }

    @assert(popup.doModal({315, 50}, .AnchorTopCenter, autoDestroy: true) == Menu_Open)
    @assert(checked)
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
    @assert(popup.submenuDirection == .Left)

    var checked: bool
    host.app.sigFrame += func|host = &host, popup, sub, checked = &checked|(app)
    {
        discard app
        if checked[] do
            return
        @assert(host.openPopupSubMenu("More choices"))
        @assert(sub.position.right() <= popup.position.x + 2 * popup.themeMetrics().menuPopup_ShadowSize)
        @assert(host.clickPopupMenuItem(Menu_Open))
        checked[] = true
    }

    @assert(popup.doModal({280, 50}, autoDestroy: true) == Menu_Open)
    @assert(checked)
    host.pump()
}

// A left-opening submenu marker replaces the unused glyph on its row, even when another row
// makes the popup keep a shared glyph column.
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
        @assert(host.dismissPopupMenu())
        checked[] = true
    }

    discard popup.doModal({348, 204}, .AnchorBottomCenter, autoDestroy: true)
    @assert(checked)
    host.pump()
}

// A left-opening submenu without any visible item glyph collapses the unused glyph column, so
// its wording follows the leading chevron at the normal icon-to-text distance.
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
    @assert(Math.abs(iconPopup.position.width - popup.position.width - (metrics.menuPopup_IconSize + metrics.menuPopup_IconTextMargin - metrics.menuPopup_IconMargin)) < 0.01)

    var checked: bool
    host.app.sigFrame += func|host = &host, checked = &checked|(app)
    {
        discard app
        if checked[] do
            return
        var image = host.render()
        Pixel.Testing.assertImageGolden(&image, "menu.popup.left.no-icons")
        @assert(host.dismissPopupMenu())
        checked[] = true
    }

    discard popup.doModal({348, 204}, .AnchorBottomCenter, autoDestroy: true)
    @assert(checked)
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
    @assert(popup.items.count == 4)

    let hiddenIt = popup.items[1]!
    let quitIt   = popup.items[3]!
    hiddenIt.hidden = true
    popup.computeLayoutPopup()
    popup.setPosition({0, 0, popup.position.width, popup.position.height})

    // Move the hidden row on top of Quit: it keeps its stale layout but must not steal the hit.
    hiddenIt.pos  = quitIt.pos
    hiddenIt.size = quitIt.size

    let pointOnQuit = Math.Point{popup.position.width * 0.5, quitIt.pos + quitIt.size * 0.5}
    @assert(popup.hitTestPopup(pointOnQuit) == 3)
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

    @assert(bar.items.count == 2)
    @assert(bar.items[1]!.name.raw == "File")
    @assert(bar.items[1]!.popup == sub)
    @assert(sub.ownerMenu == bar)
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

    @assert(bar.subVisible == sub)
    @assert(sub.ignoreNextRelease)

    host.mouseUp({0, 0})

    @assert(bar.subVisible == sub)
    @assert(!sub.ignoreNextRelease)
}

// A taller menu bar centers its visual/hit item band and uses that band as popup anchor.
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
    @assert(bar.hitTestBar({itemX, 1}) == Swag.U32.Max)
    @assert(bar.hitTestBar({itemX, expectedItemY + 1}) == 0)

    host.mouseDown({itemX, expectedItemY + 1})

    @assert(sub.popupBarItemSurfaceRect.y == expectedItemY)
    @assert(sub.popupBarItemSurfaceRect.height == metrics.menuBar_Height)
    @assert(sub.position.y == Math.max(expectedItemY - metrics.menuPopup_ShadowSize, 0))

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

    @assert(bar.subVisible == sub)
    @assert(sub.popupBarItemIdx == 0)
    @assert(sub.popupBarItemSurfaceRect.height == bar.position.height)
    @assert(sub.position.y == 0)
    @assert(sub.items[0]!.pos > metrics.menuPopup_ShadowSize + bar.position.height)
}
