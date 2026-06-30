#global #if #command == Swag.CompilerCommand.Test
#global fileprivate
using Swag, Core

const Menu_New  = "Menu.New"
const Menu_Open = "Menu.Open"
const Menu_Quit = "Menu.Quit"

// A menu bar holds items; a popup menu holds items, separators and disabled entries.
#test
{
    var host: GuiHeadlessHost
    host.setup(320, 200)

    let bar = MenuCtrl.createBar(&host.root, {0, 0, 300, 0})
    bar.addItem("New", Menu_New)
    @assert(bar.items.count == 1)
    @assert(bar.items[0].name.raw == "New")
    @assert(bar.items[0].id == Menu_New)

    let sub = MenuCtrl.createPopup(&host.root)
    sub.addItem("Open", Menu_Open)
    sub.addSeparator()
    sub.addItem("Quit", Menu_Quit, disabled: true)

    @assert(sub.items.count == 3)
    @assert(!sub.items[0].separator)
    @assert(sub.items[1].separator)
    @assert(sub.items[2].disabled)
    @assert(sub.items[2].name.raw == "Quit")

    host.shutdown()
}

// Hidden popup rows keep their previous layout values, but they must not
// intercept the row now visible under the mouse.
#test
{
    var host: GuiHeadlessHost
    host.setup(320, 200)

    let popup = MenuCtrl.createPopup(&host.root)
    popup.addItem("Open", Menu_Open)
    popup.addItem("Hidden", "Menu.Hidden")
    popup.addSeparator()
    popup.addSeparator()
    popup.addItem("Quit", Menu_Quit)

    // Consecutive separators collapse into one, so this is Open / Hidden / --- / Quit.
    @assert(popup.items.count == 4)

    popup.items[1].hidden = true
    popup.computeLayoutPopup()
    popup.setPosition({0, 0, popup.position.width, popup.position.height})

    // Move the hidden row on top of Quit: it keeps its stale layout but must not steal the hit.
    popup.items[1].pos  = popup.items[3].pos
    popup.items[1].size = popup.items[3].size

    let pointOnQuit = Math.Point{popup.position.width * 0.5, popup.items[3].pos + popup.items[3].size * 0.5}
    @assert(popup.hitTestPopup(pointOnQuit) == 3)

    host.shutdown()
}

// A popup item links a submenu back to its owner.
#test
{
    var host: GuiHeadlessHost
    host.setup(320, 200)

    let bar = MenuCtrl.createBar(&host.root, {0, 0, 300, 0})
    bar.addItem("New", Menu_New)

    let sub = MenuCtrl.createPopup(&host.root)
    sub.addItem("Open", Menu_Open)
    bar.addPopup("File", sub)

    @assert(bar.items.count == 2)
    @assert(bar.items[1].name.raw == "File")
    @assert(bar.items[1].popup == sub)
    @assert(sub.ownerMenu == bar)

    host.shutdown()
}

// Opening a menu-bar popup on press must not be cancelled by the release
// captured by the newly shown popup.
#test
{
    var host: GuiHeadlessHost
    host.setup(320, 200)

    let bar = MenuCtrl.createBar(&host.root, {0, 0, 300, 0})
    let sub = MenuCtrl.createPopup(&host.root)
    sub.addItem("Open", Menu_Open)
    bar.addPopup("File", sub)

    bar.computeLayoutBar()
    let itemX = bar.items[0].pos + bar.items[0].size * 0.5
    let itemY = bar.position.height * 0.5

    var evt = MouseEvent{kind: .MousePressed}
    evt.button     = .Left
    evt.surfacePos = {itemX, itemY}
    bar.sendEvent(&evt)

    @assert(bar.subVisible == sub)
    @assert(sub.ignoreNextRelease)

    evt.kind       = .MouseReleased
    evt.surfacePos = {0, 0}
    sub.sendEvent(&evt)

    @assert(bar.subVisible == sub)
    @assert(!sub.ignoreNextRelease)

    host.shutdown()
}

// A taller menu bar centers its visual/hit item band and uses that band as popup anchor.
#test
{
    var host: GuiHeadlessHost
    host.setup(320, 200)

    let metrics = host.root.getThemeMetrics()
    let barHeight = metrics.menuBar_Height + 12
    let bar = MenuCtrl.createBar(&host.root, {0, 0, 300, barHeight})
    let sub = MenuCtrl.createPopup(&host.root)
    sub.addItem("Open", Menu_Open)
    bar.addPopup("File", sub)

    bar.computeLayoutBar()
    let expectedItemY = (barHeight - metrics.menuBar_Height) * 0.5

    let itemX = bar.items[0].pos + bar.items[0].size * 0.5
    @assert(bar.hitTestBar({itemX, 1}) == Swag.U32.Max)
    @assert(bar.hitTestBar({itemX, expectedItemY + 1}) == 0)

    var evt = MouseEvent{kind: .MouseReleased}
    evt.button     = .Left
    evt.surfacePos = {itemX, expectedItemY + 1}
    bar.sendEvent(&evt)

    @assert(sub.popupBarItemSurfaceRect.y == expectedItemY)
    @assert(sub.popupBarItemSurfaceRect.height == metrics.menuBar_Height)
    @assert(sub.position.y == expectedItemY - metrics.menuPopup_ShadowSize)

    host.shutdown()
}

// A menu-bar popup carries the opened bar item inside its own themed area.
#test
{
    var host: GuiHeadlessHost
    host.setup(320, 200)

    let metrics = host.root.getThemeMetrics()
    let bar = MenuCtrl.createBar(&host.root, {0, 0, 300, 0})
    let sub = MenuCtrl.createPopup(&host.root)
    sub.addItem("Open", Menu_Open)
    bar.addPopup("File", sub)

    bar.computeLayoutBar()
    bar.hotIdx = 0
    bar.showHotPopup()

    @assert(bar.subVisible == sub)
    @assert(sub.popupBarItemIdx == 0)
    @assert(sub.popupBarItemSurfaceRect.height == bar.position.height)
    @assert(sub.position.y == -metrics.menuPopup_ShadowSize)
    @assert(sub.items[0].pos > metrics.menuPopup_ShadowSize + bar.position.height)

    host.shutdown()
}
