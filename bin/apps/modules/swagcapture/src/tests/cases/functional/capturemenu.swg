#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// The capture menu centers its compact delay choices and gives each wait its own glyph.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        host.shutdown()
        g_Main = null
    }

    host.theme.setLight()
    host.notify(.ThemeChanged)
    main.captureOptions.delay = 3
    main.applyLayout()
    host.finishAnimations()

    var captured: bool
    host.app.sigFrame += func|host = &host, main, captured = &captured|(_)
    {
        if captured[] do
            return

        let menu = unwrap host.capturedPopupMenu()
        Swag.require(menu.children.count == 1)
        let choices = assume cast(*Gui.StackLayoutCtrl, menu.children[0])
        Swag.require(choices.mode == .HorizontalCenter and choices.children.count == CaptureDelays.count)
        Swag.require((assume cast(*Gui.IconButton, choices.children[1])).isChecked)
        let first = choices.children[0].surfaceRect()
        let last  = choices.children[choices.children.count - 1].surfaceRect()
        let center = (first.x + last.right()) * 0.5
        Swag.require(Math.abs(center - menu.surfaceRect().horzCenter()) <= 0.5)

        captured[] = true
        Swag.require(host.dismissPopupMenu())
    }

    host.click(main.taskStrip.captureChoice.surfaceRect().center())
    Swag.require(captured)
    host.pump()
}
