#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Gui, Pixel

// The animation preparation names the application and offers a visible attachment switch.
#[Swag.TestTag("golden")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let editor = testSetupInPlace(&host, dark: false)
    let previousWindow = g_CaptureWindow
    let previousAnchored = g_CaptureAnchored
    defer
    {
        g_CaptureWindow = previousWindow
        g_CaptureAnchored = previousAnchored
        g_CaptureMedia = .Picture
        g_Main?.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    g_CaptureWindow = {application: "brave", title: "Video sample — Brave", nativeWindow: 42}
    g_CaptureAnchored = true
    editor.setMedia(.Animation)
    let attachment = unwrap editor.linkButton
    Swag.require(attachment.parent != editor.bar)
    host.clickWnd(attachment)
    Swag.require(not g_CaptureAnchored and not attachment.on and attachment.label == appStrings().ui_AimDetached)
    host.clickWnd(attachment)
    Swag.require(g_CaptureAnchored and attachment.on and attachment.label == captureTargetLabel())
    host.finishAnimations()
    var image = host.render(editor)
    Pixel.Testing.assertImageGolden(&image, "inplace.linked-animation")
}
