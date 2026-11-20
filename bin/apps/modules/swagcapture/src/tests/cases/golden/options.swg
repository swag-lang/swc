#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// Capture's options show checked, unchecked and modified settings in the shipped dialog.
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

    main.captureOptions = CaptureOptions{drawCross: false, hideEditorBefore: false}

    var captured: bool
    host.app.sigFrame += func|host = &host, captured = &captured|(_)
    {
        if captured[] do
            return

        for surface in host.app.surfaces where surface.view() is Gui.Dialog
        {
            captured[] = true
            let image = host.renderSurface(surface)
            Pixel.Testing.assertImageGolden(&image, "options.capture.encre")
            let dismissed = host.clickModalButton(Gui.Dialog.BtnCancel)
            Swag.require(dismissed)
            break
        }
    }

    main.sendCommandEvent(ActionOptions.Options)
    host.pump()
    Swag.require(captured)
}
