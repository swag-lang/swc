#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, Pixel

// The inspector gives a selected annotation a typed start, end and whole-duration command.
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
    expect testWriteFrames(Capture.mediaPathOf(file), pictures, 10_000_000)
    expect capture.adoptRecording()
    expect capture.showFrame(1)
    main.editWnd.editView.setCapture(capture)

    let form = testAddArrow(capture, 8, 40, 30, 14)
    form.timeStart = 6_000_000
    form.timeEnd   = 22_000_000
    capture.selection.add(0)
    main.applyLayout()
    main.updateState()
    main.propWnd.grid.scrollWnd.setScrollPos(0, 10000)
    host.finishAnimations()

    var screen = host.render(main)
    var image  = screen.cropped(main.inspector.surfaceRect())
    Pixel.Testing.assertImageGolden(&image, "inspector.time")
}
