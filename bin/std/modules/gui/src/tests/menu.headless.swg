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

    popup.items[1].hidden = true
    popup.computeLayoutPopup()
    popup.setPosition({0, 0, popup.position.width, popup.position.height})

    popup.items[1].pos  = popup.items[4].pos
    popup.items[1].size = popup.items[4].size
    popup.items[3].pos  = popup.items[4].pos
    popup.items[3].size = popup.items[4].size

    let pointOnQuit = Math.Point{popup.position.width * 0.5, popup.items[4].pos + popup.items[4].size * 0.5}
    @assert(popup.hitTestPopup(pointOnQuit) == 4)

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
