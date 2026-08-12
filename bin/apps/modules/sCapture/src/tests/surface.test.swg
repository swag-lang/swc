#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Builds the shipped window on the surface root, including every application pane.
func testSetupSurfaceMain(host: *Gui.Testing.HeadlessHost)->*MainWnd
{
    testUseScratchLibrary()
    host.setup(1024, 640)
    host.bindApplication(&g_App)
    registerAppStrings(&g_App.resources)
    registerAppStrings(&host.app.resources)

    let main = MainWnd.create(&host.surfaceWnd)
    main.setPosition({0, 0, 1024, 640})
    main.applyLayout()
    return main
}

// The complete sCapture surface must survive its first layout and paint without a desktop.
// This is the visual boundary that the smaller interaction fixtures deliberately avoid.
#test
{
    var host: Gui.Testing.HeadlessHost
    let main = testSetupSurfaceMain(&host)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    let capture = Memory.new'Capture()
    capture.width, capture.widthOrg   = 400
    capture.height, capture.heightOrg = 240
    capture.backImg                   = Gui.Testing.indexedImage(400, 240)
    discard testAddShape(capture, 48, 40, 144, 80)
    main.editWnd.editView.setCapture(capture)

    host.theme.setSwagDark()
    host.theme.metrics.surfaceWnd_ShadowSize   = 0
    host.theme.metrics.surfaceWnd_CornerRadius = 0
    host.notify(.ThemeChanged)
    main.applyLayout()
    host.finishAnimations()

    var image = host.render(main)
    Pixel.Testing.assertImageGolden(&image, "scapture.surface")
}

// Repeated painted document replacement exercises the ownership boundary between Capture,
// EditView and renderer-owned background/form textures.
#test
{
    var f: HeadlessFixture
    f.setup(320, 240)
    defer f.shutdown()

    for i in 32
    {
        let capture = Memory.new'Capture()
        capture.width, capture.widthOrg   = 96 + cast(s32) i
        capture.height, capture.heightOrg = 64 + cast(s32) i
        capture.backImg                   = Gui.Testing.indexedImage(capture.width, capture.height)

        let image = testAddImage(capture, 8, 8, 40, 32)
        image.kind  = .Image
        image.image = Gui.Testing.indexedImage(16 + cast(s32) (i % 7), 12 + cast(s32) (i % 5))

        f.editView.setCapture(capture)
        f.editView.setZoom(1)
        var rendered = f.gui.render(f.editView)
        @assert(rendered.isValid())
    }
}
