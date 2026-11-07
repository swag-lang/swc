#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// An animation in the editor: the timeline floats under the canvas on a panel of its own, clear of
// the dock and of the inspector, above the hint line.
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

    var pictures: [3] Image
    pictures[0] = testFramePicture(10, 0)
    pictures[1] = testFramePicture(40, 8)
    pictures[2] = testFramePicture(70, 16)

    let capture = Memory.new'Capture()
    capture.file = testTempCapturePath()
    let file = String.from(capture.file)
    defer catch Capture.deleteFiles(file)
    defer capture.closeMedia()
    expect testWriteFrames(Capture.mediaPathOf(file), pictures, 400_000)
    expect capture.adoptRecording()
    expect capture.showFrame(1)

    main.editWnd.editView.setCapture(capture)
    main.applyLayout()
    main.updateState()
    host.finishAnimations()

    // The panel stands between the dock and the inspector, with the air of the floating parts.
    let metrics = main.themeMetrics()
    let panel   = (unwrap main.timeline).panel
    Swag.require(panel.isLocallyVisible())
    Swag.require(panel.surfaceRect().x >= main.dock.surfaceRect().right() + metrics.floating_Inset)
    Swag.require(panel.surfaceRect().right() <= main.inspector.surfaceRect().x - metrics.floating_Inset)

    var image = host.render(main)
    Pixel.Testing.assertImageGolden(&image, "edit.timeline")
}
