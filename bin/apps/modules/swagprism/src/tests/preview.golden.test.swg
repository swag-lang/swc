#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui, Pixel

// A complete first frame makes the application surface a deterministic, real program preview.
func assertPreviewSurface(gui: bool, light: bool)
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    if light
    {
        host.theme.setLight()
        host.notify(.ThemeChanged)
    }

    window.openExample(gui ? .Gui : .Plasma)
    let viewer = assume cast(*PreviewViewer, window.panels[0].viewer!.window())
    awaitFrame(viewer)
    host.click(window.panels[0].pauseButton.localToSurface(Math.Point{8, 8}))
    Swag.assert(viewer.paused)
    host.moveMouse({1, 1})

    // Timings vary with the machine, while the compiled first frame is deterministic. The reader
    // knows the door, so the foot of the source says where the caret is.
    window.readingLine.setReading(Format.toString(appStrings().ui_LiveStats, 41, 812))
    window.doorKnown = true
    window.editor.setCursorPos(window.editor.cursorFromLogicalPosition(8, 40))
    window.refreshHints()
    host.settleAnimations(window, 6)
    var image = host.render(&host.surfaceWnd)
    var tolerance: Pixel.Testing.ImageGoldenOptions

    // Release FMA shifts eight Plasma samples by at most six channel levels.
    #static if #cfg == "release"
    {
        tolerance.maxChannelDelta    = 6
        tolerance.maxDifferentPixels = 8
    }

    Pixel.Testing.assertImageGolden(&image, gui ? "surface.gui" : (light ? "surface.render.paper" : "surface.render"), tolerance)
    window.shutdown()
}

#[Swag.TestTag("golden")]
#test { assertPreviewSurface(false, false) }

#[Swag.TestTag("golden")]
#test { assertPreviewSurface(false, true) }

#[Swag.TestTag("golden")]
#test { assertPreviewSurface(true, false) }
