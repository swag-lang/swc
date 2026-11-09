#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// A zoomed passage of a long recording keeps the playhead and an annotation span readable.
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

    let capture = Memory.new'Capture()
    capture.file = testTempCapturePath()
    let file = String.from(capture.file)
    defer catch Capture.deleteFiles(file)

    var pictures: [3] Image
    pictures[0] = testFramePicture(10, 0)
    pictures[1] = testFramePicture(40, 8)
    pictures[2] = testFramePicture(70, 16)
    expect testWriteFrames(Capture.mediaPathOf(file), pictures, 1_800_000_000)
    expect capture.adoptRecording()
    expect capture.showFrame(1)
    main.editWnd.editView.setCapture(capture)

    let form = testAddArrow(capture, 8, 40, 30, 14)
    form.timeStart = 1_400_000_000
    form.timeEnd   = 3_200_000_000
    capture.selection.add(0)

    main.applyLayout()
    main.updateState()
    let bar = unwrap main.timeline
    bar.zoomAt(bar.trackX(capture.playheadTime()), 4)
    host.finishAnimations()

    var screen = host.render(main)
    Swag.require(bar.thumbReader != null and bar.thumbsReady)
    Swag.require(bar.thumbStart == bar.viewStart and bar.thumbSpan == bar.visibleDuration())
    let lastThumb = bar.thumbReader
    let sampled = bar.viewStart + bar.visibleDuration() * (2 * TimelineThumbnails - 1) /
                                 (2 * TimelineThumbnails)
    let shown = lastThumb.timeOf(lastThumb.frameAt(sampled))
    Swag.require(shown >= bar.viewStart and shown <= bar.viewStart + bar.visibleDuration())
    var image  = screen.cropped(bar.panel.surfaceRect())
    Pixel.Testing.assertImageGolden(&image, "timeline.zoom")
}
