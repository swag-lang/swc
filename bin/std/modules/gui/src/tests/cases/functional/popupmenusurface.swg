#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A menu on its own surface fits its measured rows plus the native shadow and arms pointer
// capture only after the opening gesture.
#test
{
    var host: Testing.HeadlessHost
    host.setup(600, 400)
    defer host.shutdown()

    let surface = unwrap PopupMenuSurface.create(&host.app, {100, 100})
    with let root = Wnd.create'Wnd(surface.wnd)
    {
        .backgroundStyle = .Window
        .focusPolicy = .Click
        .dockStyle = .Center
    }
    let menu = Wnd.create'MenuCtrl(root)
    menu.addItem("First", "popup.first")
    menu.addItem("Second", "popup.second")
    menu.owner = &host.root
    menu.dockStyle = .Center
    menu.padding = 10
    menu.setFramePainting(true)
    PopupMenuSurface.show(root, menu, {100, 100, 80, 30}, .BelowAnchor, {100, 100})

    Swag.require(surface.position.width >= (menu.position.width + 2 * surface.shadowMargin()) * surface.dpiScale)
    Swag.require(surface.position.height >= (menu.position.height + 2 * surface.shadowMargin()) * surface.dpiScale)
    var wasActive, armed: bool
    Swag.require(not PopupMenuSurface.shouldDismiss(root, menu, &wasActive, &armed))
    Swag.require(armed and menu.mouseCapture() == menu)
    surface.destroy()
}
