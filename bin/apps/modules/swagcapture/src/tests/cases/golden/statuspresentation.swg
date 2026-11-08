#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// A lasting selection mode reads as a quiet operation in Encre, beside the image output.
#[Swag.TestTag("golden")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true, text: false)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let capture = unwrap main.getCapture()
    discard testAddShape(capture, 32, 32, 80, 50)
    main.freezeSelection(true)
    host.finishAnimations()
    var image = host.renderSettled(main)
    Pixel.Testing.assertImageGolden(&image, "status.frozen.ink")
}

// A persistent capture-key failure reads beside Capture in Papier, with its details on request.
#[Swag.TestTag("golden")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: false, text: false)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    main.takenHotKeys.clear()
    main.takenHotKeys.add(String.from("PrintScreen"))
    main.taskStrip.showUnavailableShortcuts(true)
    host.finishAnimations()
    var image = host.renderSettled(main)
    Pixel.Testing.assertImageGolden(&image, "status.shortcuts.paper")
}

// The unavailable keys and the recovery note fit the anchored detail menu in Encre.
#[Swag.TestTag("golden")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: true, text: false)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    main.takenHotKeys.clear()
    main.takenHotKeys.add(String.from("PrintScreen"))
    main.takenHotKeys.add(String.from("Ctrl Shift PrintScreen"))
    main.taskStrip.showUnavailableShortcuts(true)

    var captured: bool
    host.app.sigFrame += func|host = &host, main, captured = &captured|(_)
    {
        if captured[] do
            return
        Swag.require(host.capturedPopupMenu() != null)
        host.finishAnimations()
        var image = host.render(main)
        Pixel.Testing.assertImageGolden(&image, "status.shortcuts.detail.ink")
        captured[] = true
        Swag.require(host.dismissPopupMenu())
    }

    host.click(main.taskStrip.shortcutWarning.surfaceRect().center())
    Swag.require(captured)
}
