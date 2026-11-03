#global if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core

#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 240)
    let menu     = MenuCtrl.createPopup(&host.root)
    let expected = "C:/Projects/A folder path longer than inline string storage/Documents"
    scope
    {
        let target = Core.String.from(expected)
        menu.addItem("Documents", target)
    }

    Swag.assert(menu.items[0]!.id == expected)
}
#test
{
    var destroyed: u32
    var host:      Testing.HeadlessHost
    host.setup(360, 240)
    let button = IconButton.create(&host.surfaceWnd, host.theme.icon(.Appearance, 20), {20, 20, 80, 32})
    let popup  = MenuCtrl.createPopup(button)
    let sub    = MenuCtrl.createPopup(popup)
    let nested = MenuCtrl.createPopup(sub)
    nested.addItem("Command", "Menu.Lifetime.Command")
    sub.addPopup("Nested", nested)
    popup.addPopup("Submenu", sub)
    for menu in [popup, sub, nested]
    {
        menu.hookOnEvent = func|count = &destroyed|(_, evt)->bool
        {
            if evt is DestroyEvent do
                count[] += 1
            return false
        }
    }

    host.app.sigFrame += func|host = &host|(_) { discard host.dismissPopupMenu() }
    discard popup.doModal(button, autoDestroy: true)
    host.app.sigFrame.clear()
    host.pump()
    Swag.assert(destroyed == 3)
    button.destroy()
    host.pump()
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
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
    Swag.assert(sub.themeMetrics().menuPopup_ItemHeight == 30)
    Swag.assert(sub.items[0]!.size + sub.themeMetrics().menuPopup_SpaceLines >= sub.themeMetrics().menuPopup_ItemHeight)
    Swag.assert(not sub.items[0]!.separator)
    Swag.assert(sub.items[1]!.separator)
    Swag.assert(sub.items[2]!.disabled)
    Swag.assert(sub.items[2]!.name.raw == "Quit")
    Swag.assert(sub.itemAt(2).id == Menu_Quit)

    sub.removeItemAt(1)
    Swag.assert(sub.items.count == 2)
    sub.clear()
    Swag.assert(sub.items.isEmpty())
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)

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
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)

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
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 200, 1.5)

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
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    let popup = MenuCtrl.createPopup(&host.root)
    popup.addItem("Open", Menu_Open)
    popup.addItem("Quit", Menu_Quit)
    MenuSelectedCount        = 0
    popup.sigCommandSelected += &menuCommandSelected

    var frameCount: u32
    var didClick:   bool
    host.app.sigFrame += func|host = &host, popup, frames = &frameCount, didClick = &didClick|(_)
    {
        frames[] += 1
        if not didClick[]
        {
            Swag.assert(host.capturedPopupMenu() == popup)
            let menuItemClicked = host.clickPopupMenuItem(Menu_Open)
            Swag.assert(menuItemClicked)
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
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    host.recordCommands()

    for expected in ["Menu.Short", "Menu.Command.With.An.Allocated.Identifier"]
    {
        var id    = String.from(expected)
        let popup = MenuCtrl.createPopup(&host.root)
        popup.addItem("Open", id.toString())
        host.clickPopupMenuItemWhenShown(expected)

        let before   = host.commandCount
        let selected = popup.doModal({40, 40}, autoDestroy: true)
        Swag.assert(selected == expected)
        Swag.assert(host.autoHandled and host.autoFailure.isEmpty())
        Swag.assert(host.commandCount == before)

        id[0] = 'X'
        host.pump()
        Swag.assert(host.commandCount == before + 1)
        Swag.assert(host.lastCommand == expected)
    }
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)

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
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    let popup = MenuCtrl.createPopup(&host.root)
    let sub   = MenuCtrl.createPopup(&host.root)
    sub.addItem("Open", Menu_Open)
    popup.addPopup("More", sub)
    popup.setSubmenuDirection(.Right)
    Swag.assert(popup.submenuDirection == .Right)

    var didOpen:     bool
    var didClick:    bool
    var hidTogether: bool
    sub.sigCommandSelected += func|popup, sub, hidTogether = &hidTogether|(_, _)
    {
        hidTogether[] = popup.isHidden() and sub.isHidden()
    }

    host.app.sigFrame += func|host = &host, popup, sub, opened = &didOpen, clicked = &didClick|(_)
    {
        if not opened[]
        {
            let submenuOpened = host.openPopupSubMenu("More")
            Swag.assert(submenuOpened)
            Swag.assert(sub.position.x >= popup.position.right() - 2 * popup.themeMetrics().menuPopup_ShadowSize)
            opened[] = true
        }
        elif not clicked[]
        {
            let menuItemClicked = host.clickPopupMenuItem(Menu_Open)
            Swag.assert(menuItemClicked)
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
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)

    let popup = MenuCtrl.createPopup(&host.root)
    popup.addItem("Actual size", Menu_Open)
    popup.addItem("Fit to view", Menu_Quit)

    let anchor = Math.Point{310, 40}
    var checked: bool
    host.app.sigFrame += func|host = &host, popup, anchor, checked = &checked|(_)
    {
        if checked[] do
            return

        let margin = popup.themeMetrics().menuPopup_WindowMargin
        Swag.assert(popup.position.x >= margin)
        Swag.assert(popup.position.right() <= host.root.position.width - margin)
        Swag.assert(Math.abs(popup.position.x + popup.anchorPosition - anchor.x) < 0.5)
        let menuItemClicked = host.clickPopupMenuItem(Menu_Open)
        Swag.assert(menuItemClicked)
        checked[] = true
    }

    let modalResult = popup.doModal(anchor, .AnchorTopCenter, autoDestroy: true)
    Swag.assert(modalResult == Menu_Open)
    Swag.assert(checked)
    host.pump()
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    let popup = MenuCtrl.createPopup(&host.root)
    popup.addItem("Open", Menu_Open)

    var didDismiss: bool
    host.app.sigFrame += func|host = &host, dismissed = &didDismiss|(_)
    {
        if not dismissed[]
        {
            let menuDismissed = host.dismissPopupMenu()
            Swag.assert(menuDismissed)
            dismissed[] = true
        }
    }

    let result = popup.doModal({40, 40}, autoDestroy: true)

    Swag.assert(result == null)
    Swag.assert(didDismiss)
    Swag.assert(host.app.mouseCaptureWnd == null)

    host.pump()
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 160)

    let popup = MenuCtrl.createPopup(&host.root)
    for index in 8 do
        popup.addItem(Format.toString("Caption %", index).toString(), Menu_Open)

    var checked: bool
    host.app.sigFrame += func|host = &host, popup, checked = &checked|(_)
    {
        if checked[] do
            return
        let margin = popup.themeMetrics().menuPopup_WindowMargin
        Swag.assert(popup.position.x >= margin and popup.position.y >= margin)
        Swag.assert(popup.position.right() <= host.root.position.width - margin)
        let menuDismissed = host.dismissPopupMenu()
        Swag.assert(menuDismissed)
        checked[] = true
    }

    discard popup.doModal({310, 18}, .AnchorBottomCenter, autoDestroy: true)
    Swag.assert(checked)
    host.pump()
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)

    let popup = MenuCtrl.createPopup(&host.root)
    let sub   = MenuCtrl.createPopup(&host.root)
    sub.addItem("Open", Menu_Open)
    popup.addPopup("More choices", sub)

    var checked: bool
    host.app.sigFrame += func|host = &host, popup, sub, checked = &checked|(_)
    {
        if checked[] do
            return
        let submenuOpened = host.openPopupSubMenu("More choices")
        Swag.assert(submenuOpened)
        Swag.assert(sub.position.x >= popup.themeMetrics().menuPopup_WindowMargin)
        Swag.assert(sub.position.right() <= popup.position.x + 2 * popup.themeMetrics().menuPopup_ShadowSize)
        let menuItemClicked = host.clickPopupMenuItem(Menu_Open)
        Swag.assert(menuItemClicked)
        checked[] = true
    }

    let modalResult = popup.doModal({315, 50}, .AnchorTopCenter, autoDestroy: true)
    Swag.assert(modalResult == Menu_Open)
    Swag.assert(checked)
    host.pump()
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(520, 220)

    let popup = MenuCtrl.createPopup(&host.root)
    let sub   = MenuCtrl.createPopup(&host.root)
    sub.addItem("Open", Menu_Open)
    popup.addPopup("More choices", sub)
    popup.setSubmenuDirection(.Left)
    Swag.assert(popup.submenuDirection == .Left)

    var checked: bool
    host.app.sigFrame += func|host = &host, popup, sub, checked = &checked|(_)
    {
        if checked[] do
            return
        let submenuOpened = host.openPopupSubMenu("More choices")
        Swag.assert(submenuOpened)
        Swag.assert(sub.position.right() <= popup.position.x + 2 * popup.themeMetrics().menuPopup_ShadowSize)
        let menuItemClicked = host.clickPopupMenuItem(Menu_Open)
        Swag.assert(menuItemClicked)
        checked[] = true
    }

    let modalResult = popup.doModal({280, 50}, autoDestroy: true)
    Swag.assert(modalResult == Menu_Open)
    Swag.assert(checked)
    host.pump()
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    let popup = MenuCtrl.createPopup(&host.root)
    popup.addItem("Open", Menu_Open)
    popup.addItem("Hidden", "Menu.Hidden")
    popup.addSeparator()
    popup.addSeparator()
    popup.addItem("Quit", Menu_Quit)

    // Consecutive separators collapse into one, so this is Open / Hidden / --- / Quit.
    Swag.assert(popup.items.count == 4)

    let hiddenIt = unwrap popup.items[1]
    let quitIt   = unwrap popup.items[3]
    hiddenIt.hidden = true
    popup.computeLayoutPopup()
    popup.setPosition(Math.Rectangle{0, 0, popup.position.width, popup.position.height})

    // Move the hidden row on top of Quit: it keeps its stale layout but must not steal the hit.
    hiddenIt.pos  = quitIt.pos
    hiddenIt.size = quitIt.size

    let pointOnQuit = Math.Point{popup.position.width * 0.5, quitIt.pos + quitIt.size * 0.5}
    Swag.assert(popup.hitTestPopup(pointOnQuit) == 3)
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
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
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    let bar = MenuCtrl.createBar(&host.root, {0, 0, 300, 0})
    let sub = MenuCtrl.createPopup(&host.root)
    sub.addItem("Open", Menu_Open)
    bar.addPopup("File", sub)

    bar.computeLayoutBar()
    let barIt0 = unwrap bar.items[0]
    let itemX  = barIt0.pos + barIt0.size * 0.5
    let itemY  = bar.position.height * 0.5

    host.mouseDown(Math.Point{itemX, itemY})

    Swag.assert(bar.subVisible == sub)
    Swag.assert(sub.ignoreNextRelease)

    host.mouseUp({0, 0})

    Swag.assert(bar.subVisible == sub)
    Swag.assert(not sub.ignoreNextRelease)
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
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
    Swag.assert(sub.position.y == -metrics.menuPopup_ShadowSize)
    Swag.assert(sub.items[0]!.pos > metrics.menuPopup_ShadowSize + bar.position.height)
}
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 320)

    let popup = MenuCtrl.createPopup(&host.root)
    popup.addItem("Keep", Menu_New)
    popup.addSeparator()
    let destroy = popup.addItem("Clear All…", Menu_Quit)
    destroy.critical = true
    Swag.assert(destroy.critical and not popup.items[0]!.critical)

    var placed: bool
    host.app.sigFrame += func|host = &host, popup, placed = &placed|(_)
    {
        if placed[] do
            return
        let shadow = popup.themeMetrics().menuPopup_ShadowSize
        let body   = popup.surfaceRect()
        Swag.assert(Math.abs(body.right() - shadow - 400) <= 1 and Math.abs(body.y + shadow - 40) <= 1)
        Swag.assert(host.dismissPopupMenu())
        placed[] = true
    }

    discard popup.doModal({400, 40}, .TopRight, autoDestroy: true)
    Swag.assert(placed)
    host.pump()
}
