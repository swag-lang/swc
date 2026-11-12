#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A detached menu keeps its keyboard selection on actionable rows and cycles matching names.
#test
{
    var host: Testing.HeadlessHost
    host.setup(440, 320)
    defer host.shutdown()

    let menu = MenuCtrl.createPopup(&host.root)
    menu.addLabel("Capture")
    menu.addItem("Capture Area", "capture.area")
    menu.addItem("Unavailable", "capture.disabled", disabled: true)
    menu.addSeparator()
    menu.addItem("Record Video", "record.video")
    menu.addItem("Record Screen", "record.screen")

    var down = KeyEvent{kind: .Pressed, key: .Down}
    menu.handleKeyboard(&down)
    Swag.require(down.accepted and menu.selectedIdx == 1)
    menu.handleKeyboard(&down)
    Swag.require(menu.selectedIdx == 4)

    var letter = KeyEvent{kind: .Character, character: 'r'}
    menu.handleKeyboard(&letter)
    Swag.require(letter.accepted and menu.selectedIdx == 5)
    menu.handleKeyboard(&letter)
    Swag.require(menu.selectedIdx == 4)

    var home = KeyEvent{kind: .Pressed, key: .Home}
    menu.handleKeyboard(&home)
    Swag.require(menu.selectedIdx == 1)
    var end = KeyEvent{kind: .Pressed, key: .End}
    menu.handleKeyboard(&end)
    Swag.require(menu.selectedIdx == 5)

    var enter = KeyEvent{kind: .Pressed, key: .Return}
    menu.handleKeyboard(&enter)
    Swag.require(enter.accepted and menu.isModalEnded() and menu.modalResult() == "record.screen")
}

// Dynamic navigation targets remain valid after the source collection has been released.
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

    Swag.require(menu.items[0]!.id == expected)
}

// A submenu keeps its command identifier after the source string changes.
#test
{
    var received: String
    var host:     Testing.HeadlessHost
    host.setup(400, 240)
    let popup    = MenuCtrl.createPopup(&host.root)
    let submenu  = MenuCtrl.createPopup(&host.root)
    let expected = "Menu.Submenu.With.An.Allocated.Identifier"
    var source   = Core.String.from(expected)

    let item = popup.addPopup("More", submenu, id: source.toString())
    source[0] = 'X'

    host.root.hookOnEvent = func|received = &received|(_, event)->bool
    {
        if event is CommandStateEvent as state where state.kind == .Compute
        {
            received[] = String.from(state.id)
            return true
        }

        return false
    }

    popup.updateState()

    Swag.require(item.id == expected and received.toString() == expected)
}

// A popup note remains readable information and cannot be selected like a command.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 240)
    let menu = MenuCtrl.createPopup(&host.root)
    menu.addLabel("Capture keys")
    let note = menu.addNote("PrintScreen is unavailable")
    menu.addItem("Capture Area", "capture.area")

    Swag.require(note.disabled and not note.label)
    Swag.require(note.name.raw == "PrintScreen is unavailable" and note.id == "")
    menu.computeLayoutPopup()
    Swag.require(note.size > 0)
}

// An automatically destroyed popup retires its surface-sibling submenus before their owner.
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
    Swag.require(destroyed == 3)
    button.destroy()
    host.pump()
}

var MenuSelectedCount: u32

// Stands for a string table field: a resolver reads it again on every layout.
var MenuResolvedLabel: string = "Open"

func menuResolvedLabel()->string => MenuResolvedLabel

func menuCommandSelected(_: *MenuCtrl, id: WndId)
{
    if id == Menu_Open do
        MenuSelectedCount += 1
}

// A menu bar holds items; a popup menu holds items, separators and disabled entries.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    let bar = MenuCtrl.createBar(&host.root, {0, 0, 300, 0})
    bar.addItem("New", Menu_New)
    Swag.require(bar.items.count == 1)
    Swag.require(bar.items[0]!.name.raw == "New")
    Swag.require(bar.items[0]!.id == Menu_New)

    let sub = MenuCtrl.createPopup(&host.root)
    sub.addItem("Open", Menu_Open)
    sub.addSeparator()
    sub.addItem("Quit", Menu_Quit, disabled: true)

    Swag.require(sub.items.count == 3)
    sub.computeLayoutPopup()
    Swag.require(sub.themeMetrics().menuPopup_IconSize == 16)
    Swag.require(sub.themeMetrics().menuPopup_ItemHeight == 30)
    Swag.require(sub.items[0]!.size + sub.themeMetrics().menuPopup_SpaceLines >= sub.themeMetrics().menuPopup_ItemHeight)
    Swag.require(not sub.items[0]!.separator)
    Swag.require(sub.items[1]!.separator)
    Swag.require(sub.items[2]!.disabled)
    Swag.require(sub.items[2]!.name.raw == "Quit")
    Swag.require(sub.itemAt(2).id == Menu_Quit)

    sub.removeItemAt(1)
    Swag.require(sub.items.count == 2)
    sub.clear()
    Swag.require(sub.items.isEmpty())
}

// An entry built from a resolver re-reads its label on every layout; one built from a
// literal keeps the wording it was created with.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)

    MenuResolvedLabel = "Open"
    let bar = MenuCtrl.createBar(&host.root, {0, 0, 300, 0})
    bar.addItem("New", Menu_New)
    bar.addItem(&menuResolvedLabel, Menu_Open)

    // The resolver already answers once, so the item is usable before any layout.
    Swag.require(bar.items[1]!.name.raw == "Open")

    MenuResolvedLabel = "Ouvrir"
    bar.computeLayoutBar()
    Swag.require(bar.items[1]!.name.raw == "Ouvrir")
    Swag.require(bar.items[0]!.name.raw == "New")

    // A longer label widens its own entry and pushes the next one along.
    let widened = bar.items[1]!.size
    MenuResolvedLabel = "Ouvrir un fichier"
    bar.computeLayoutBar()
    Swag.require(bar.items[1]!.size > widened)
}

// A submenu carries a resolver the same way, and a language change asks the bar to
// measure itself again.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)

    MenuResolvedLabel = "File"
    let sub = MenuCtrl.createPopup(&host.root)
    sub.addItem("Quit", Menu_Quit)

    let bar = MenuCtrl.createBar(&host.root, {0, 0, 300, 0})
    bar.addPopup(&menuResolvedLabel, sub)
    Swag.require(bar.items[0]!.name.raw == "File")
    Swag.require(bar.items[0]!.popup == sub)

    bar.computeLayoutBar()
    bar.dirtyLayout = false

    MenuResolvedLabel = "Fichier"
    var evt = NotifyEvent{}
    evt.kind = .LanguageChanged
    bar.sendEvent(&evt)
    Swag.require(bar.dirtyLayout)

    bar.computeLayoutBar()
    Swag.require(bar.items[0]!.name.raw == "Fichier")
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
    Swag.require(bar.deviceScale() == 1.5)
    Swag.require(bar.items[0]!.size >= drawn)

    // The scale is what decides: measuring at one under-counts every glyph advance, which
    // is exactly the width the entry used to be short of.
    Swag.require(measure("Affichage", rsf, 1.0) <= drawn)
}

// Headless tests can drive modal popup menus through the normal mouse pipeline.
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
            Swag.require(host.capturedPopupMenu() == popup)
            let menuItemClicked = host.clickPopupMenuItem(Menu_Open)
            Swag.require(menuItemClicked)
            didClick[] = true
        }
    }

    let result = popup.doModal({40, 40}, autoDestroy: true)

    Swag.require(result == Menu_Open)
    Swag.require(MenuSelectedCount == 1)
    Swag.require(frameCount == 1)
    Swag.require(didClick)
    Swag.require(host.app.mouseCaptureWnd == null)

    host.pump()
}

// A widget row sends a captured menu click to the button inside its layout.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 220)
    let popup = MenuCtrl.createPopup(&host.root)
    popup.addItem("Open", Menu_Open)

    with let choices = StackLayoutCtrl.create(popup, .Left)
    {
        .fitToContent = true
    }
    let choice = IconButton.create(choices, {}, {0, 0, 48, 24}, flags: .Radio)
    choice.setText("3 s")
    popup.addWidget(choices)

    var clicked: bool
    host.app.sigFrame += func|host = &host, popup, choice, clicked = &clicked|(_)
    {
        if clicked[] do
            return
        clicked[] = true
        Swag.require(host.capturedPopupMenu() == popup)
        host.clickWnd(choice)
        Swag.require(choice.isChecked)
        Swag.require(not popup.isModalEnded())
        Swag.require(host.capturedPopupMenu() == popup)
        Swag.require(host.clickPopupMenuItem(Menu_Open))
    }

    let result = popup.doModal({40, 40}, autoDestroy: true)
    Swag.require(clicked and result == Menu_Open)
}

// A modal menu's queued command keeps the identifier selected before its caller changes it.
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
        Swag.require(selected == expected)
        Swag.require(host.autoHandled and host.autoFailure.isEmpty())
        Swag.require(host.commandCount == before)

        id[0] = 'X'
        host.pump()
        Swag.require(host.commandCount == before + 1)
        Swag.require(host.lastCommand == expected)
    }
}

// A submenu label keeps its complete measured run beside the reserved chevron band.
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
    Swag.require(metrics.chevron_Size == 12)
    Swag.require(metrics.menuPopup_WindowMargin == 8)
    Swag.require(popup.position.width - chromeWidth + 0.01 >= item.name.boundRect.width)
}

// Headless popup menus can drive nested submenus through hover/timer behavior.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    let popup = MenuCtrl.createPopup(&host.root)
    let sub   = MenuCtrl.createPopup(&host.root)
    sub.addItem("Open", Menu_Open)
    popup.addPopup("More", sub)
    popup.setSubmenuDirection(.Right)
    Swag.require(popup.submenuDirection == .Right)

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
            Swag.require(submenuOpened)
            Swag.require(sub.position.x >= popup.position.right() - 2 * popup.themeMetrics().menuPopup_ShadowSize)
            opened[] = true
        }
        elif not clicked[]
        {
            let menuItemClicked = host.clickPopupMenuItem(Menu_Open)
            Swag.require(menuItemClicked)
            clicked[] = true
        }
    }

    let result = popup.doModal({40, 40}, autoDestroy: true)

    Swag.require(result == Menu_Open)
    Swag.require(didOpen)
    Swag.require(didClick)
    Swag.require(hidTogether)
    Swag.require(host.app.mouseCaptureWnd == null)

    host.pump()
}

// A centred popup fitted at the right edge keeps its notch under the requested anchor.
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
        Swag.require(popup.position.x >= margin)
        Swag.require(popup.position.right() <= host.root.position.width - margin)
        Swag.require(Math.abs(popup.position.x + popup.anchorPosition - anchor.x) < 0.5)
        let menuItemClicked = host.clickPopupMenuItem(Menu_Open)
        Swag.require(menuItemClicked)
        checked[] = true
    }

    let modalResult = popup.doModal(anchor, .AnchorTopCenter, autoDestroy: true)
    Swag.require(modalResult == Menu_Open)
    Swag.require(checked)
    host.pump()
}

// Clicking outside a captured popup dismisses it without selecting an item.
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
            Swag.require(menuDismissed)
            dismissed[] = true
        }
    }

    let result = popup.doModal({40, 40}, autoDestroy: true)

    Swag.require(result == null)
    Swag.require(didDismiss)
    Swag.require(host.app.mouseCaptureWnd == null)

    host.pump()
}

// An anchored menu that is taller than the room above its button keeps its shadow and content
// inside the top edge instead of leaving the menu body glued beyond the window.
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
        Swag.require(popup.position.x >= margin and popup.position.y >= margin)
        Swag.require(popup.position.right() <= host.root.position.width - margin)
        let menuDismissed = host.dismissPopupMenu()
        Swag.require(menuDismissed)
        checked[] = true
    }

    discard popup.doModal({310, 18}, .AnchorBottomCenter, autoDestroy: true)
    Swag.require(checked)
    host.pump()
}

// A submenu at the right edge chooses the available left side as a complete rectangle.
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
        Swag.require(submenuOpened)
        Swag.require(sub.position.x >= popup.themeMetrics().menuPopup_WindowMargin)
        Swag.require(sub.position.right() <= popup.position.x + 2 * popup.themeMetrics().menuPopup_ShadowSize)
        let menuItemClicked = host.clickPopupMenuItem(Menu_Open)
        Swag.require(menuItemClicked)
        checked[] = true
    }

    let modalResult = popup.doModal({315, 50}, .AnchorTopCenter, autoDestroy: true)
    Swag.require(modalResult == Menu_Open)
    Swag.require(checked)
    host.pump()
}

// Automatic placement uses one side for every child, chosen for the widest submenu.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 220)

    let narrow = MenuCtrl.createPopup(&host.root)
    narrow.addItem("Open", Menu_Open)
    let wide = MenuCtrl.createPopup(&host.root)
    wide.addItem("A child command too wide to fit on the right side of its parent menu", Menu_Open)

    let popup = MenuCtrl.createPopup(&host.root)
    let narrowItem = popup.addPopup("Narrow", narrow)
    let wideItem   = popup.addPopup("Wide", wide)

    var stage: u32
    host.app.sigFrame += func|host = &host, popup, narrow, narrowItem, wideItem, stage = &stage|(_)
    {
        if stage[] == 0
        {
            Swag.require(narrowItem.submenuOpensLeft)
            Swag.require(wideItem.submenuOpensLeft)
            let narrowWidth = narrow.position.width
            let rightEdge   = popup.position.right() - 2 * popup.themeMetrics().menuPopup_ShadowSize
            let margin      = popup.themeMetrics().menuPopup_WindowMargin
            Swag.require(rightEdge + narrowWidth <= host.root.position.width - margin)

            let submenuOpened = host.openPopupSubMenu("Narrow")
            Swag.require(submenuOpened)
            Swag.require(narrow.position.right() <= rightEdge + 0.5)
            Swag.require(host.dismissPopupMenu())
            stage[] = 1
        }
        elif stage[] == 1
        {
            Swag.require(host.dismissPopupMenu())
            stage[] = 2
        }
    }

    discard popup.doModal({350, 40}, .TopLeft, autoDestroy: true)
    Swag.require(stage == 2)
    host.pump()
}

// A caller can keep child menus and their markers on the left even when the right side also fits.
#test
{
    var host: Testing.HeadlessHost
    host.setup(520, 220)

    let popup = MenuCtrl.createPopup(&host.root)
    let sub   = MenuCtrl.createPopup(&host.root)
    sub.addItem("Open", Menu_Open)
    popup.addPopup("More choices", sub)
    popup.setSubmenuDirection(.Left)
    Swag.require(popup.submenuDirection == .Left)

    var checked: bool
    host.app.sigFrame += func|host = &host, popup, sub, checked = &checked|(_)
    {
        if checked[] do
            return
        let submenuOpened = host.openPopupSubMenu("More choices")
        Swag.require(submenuOpened)
        Swag.require(sub.position.right() <= popup.position.x + 2 * popup.themeMetrics().menuPopup_ShadowSize)
        let menuItemClicked = host.clickPopupMenuItem(Menu_Open)
        Swag.require(menuItemClicked)
        checked[] = true
    }

    let modalResult = popup.doModal({280, 50}, autoDestroy: true)
    Swag.require(modalResult == Menu_Open)
    Swag.require(checked)
    host.pump()
}

// Hidden popup rows keep their previous layout values, but they must not
// intercept the row now visible under the mouse.
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
    Swag.require(popup.items.count == 4)

    let hiddenIt = unwrap popup.items[1]
    let quitIt   = unwrap popup.items[3]
    hiddenIt.hidden = true
    popup.computeLayoutPopup()
    popup.setPosition(Math.Rectangle{0, 0, popup.position.width, popup.position.height})

    // Move the hidden row on top of Quit: it keeps its stale layout but must not steal the hit.
    hiddenIt.pos  = quitIt.pos
    hiddenIt.size = quitIt.size

    let pointOnQuit = Math.Point{popup.position.width * 0.5, quitIt.pos + quitIt.size * 0.5}
    Swag.require(popup.hitTestPopup(pointOnQuit) == 3)
}

// A popup item links a submenu back to its owner.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 200)
    let bar = MenuCtrl.createBar(&host.root, {0, 0, 300, 0})
    bar.addItem("New", Menu_New)

    let sub = MenuCtrl.createPopup(&host.root)
    sub.addItem("Open", Menu_Open)
    bar.addPopup("File", sub)

    Swag.require(bar.items.count == 2)
    Swag.require(bar.items[1]!.name.raw == "File")
    Swag.require(bar.items[1]!.popup == sub)
    Swag.require(sub.ownerMenu == bar)
}

// Opening a menu-bar popup on press must not be cancelled by the release
// captured by the newly shown popup.
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

    Swag.require(bar.subVisible == sub)
    Swag.require(sub.ignoreNextRelease)

    host.mouseUp({0, 0})

    Swag.require(bar.subVisible == sub)
    Swag.require(not sub.ignoreNextRelease)
}

// A menu-bar popup carries the opened bar item inside its own themed area.
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

    Swag.require(bar.subVisible == sub)
    Swag.require(sub.popupBarItemIdx == 0)
    Swag.require(sub.popupBarItemSurfaceRect.height == bar.position.height)
    Swag.require(sub.position.y == -metrics.menuPopup_ShadowSize)
    Swag.require(sub.items[0]!.pos > metrics.menuPopup_ShadowSize + bar.position.height)
}

// A menu opened from the end of a line stands with its top-right corner on the anchor, and an
// entry that destroys something is set apart in the critical ink.
#test
{
    var host: Testing.HeadlessHost
    host.setup(480, 320)

    let popup = MenuCtrl.createPopup(&host.root)
    popup.addItem("Keep", Menu_New)
    popup.addSeparator()
    let destroy = popup.addItem("Clear All…", Menu_Quit)
    destroy.critical = true
    Swag.require(destroy.critical and not popup.items[0]!.critical)

    var placed: bool
    host.app.sigFrame += func|host = &host, popup, placed = &placed|(_)
    {
        if placed[] do
            return
        let shadow = popup.themeMetrics().menuPopup_ShadowSize
        let body   = popup.surfaceRect()
        Swag.require(Math.abs(body.right() - shadow - 400) <= 1 and Math.abs(body.y + shadow - 40) <= 1)
        Swag.require(host.dismissPopupMenu())
        placed[] = true
    }

    discard popup.doModal({400, 40}, .TopRight, autoDestroy: true)
    Swag.require(placed)
    host.pump()
}
