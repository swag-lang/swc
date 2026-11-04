#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// Destructive ink survives hover, while unavailable removal keeps the disabled treatment.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(390, 260)
    host.theme.setDark()
    host.notify(.ThemeChanged)

    let menu = MenuCtrl.createPopup(&host.root)
    menu.addItem("Open recycle bin", "open", host.theme.icon(.Remove))
    menu.addItem("Restore", "restore", host.theme.icon(.Undo))
    menu.addSeparator()
    menu.addItem("Delete permanently", "delete", host.theme.icon(.Remove)).critical = true
    menu.addItem("Empty recycle bin", "empty", host.theme.icon(.RemoveAll), disabled: true).critical = true

    var captured: bool
    host.app.sigFrame += func|host = &host, menu, captured = &captured|(_)
    {
        if captured[] do
            return
        menu.hotIdx = 3
        var image = host.render()
        Pixel.Testing.assertImageGolden(&image, "commands.destructive.ink")
        captured[] = true
        Swag.require(host.dismissPopupMenu())
    }

    discard menu.doModal({28, 28}, .TopLeft, autoDestroy: true)
    Swag.require(captured)
    host.pump()
}
