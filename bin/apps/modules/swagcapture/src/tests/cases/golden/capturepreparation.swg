#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Gui, Pixel

// A fresh zone made an animation waits for its recording: the kinds, cursor, countdown, cadence,
// sound out of reach and why, Record and the cross, in Papier.
#[Swag.TestTag("golden")]
#test
{
    var host: Gui.Testing.HeadlessHost
    let editor = testSetupInPlace(&host, dark: false)
    defer
    {
        g_CaptureMedia = .Picture
        g_Main?.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    editor.source.captureOptions.recordCountdown = true
    editor.setMedia(.Animation)
    host.runFrames(1)
    host.finishAnimations()
    var image = host.render(editor)
    Pixel.Testing.assertImageGolden(&image, "inplace.record")
}
