#global if #command == Swag.CompilerCommand.Test
#global internal

using Swag, Core, Gui

// Builds the real main window inside the same measured frame as the shipped surface.
func testSetupMainWindow(host: *Testing.HeadlessHost, width = cast(f32) MainWindow.WindowWidth, height = cast(f32) MainWindow.WindowHeight, scale = 1.0'f32)->*MainWindow
{
    host.setup(width, height, scale)
    host.bindApplication(&g_App)

    // The window resolves its application through its surface, so that is the one a language
    // switch travels through and the one that has to be able to find the translations. The module
    // global gets them too, because the code under test reads `g_App` directly.
    registerAppStrings(&g_App.resources)
    registerAppStrings(&host.app.resources)

    let result = MainWindow.create(&host.surfaceWnd)
    host.surface.setTitle(ProductName)
    result.applyLayout()
    return result
}

func awaitFrame(viewer: *PreviewViewer, after: u32 = 0)
{
    var watch: Time.Stopwatch
    watch.start()
    while viewer.running and viewer.frameCount <= after and watch.elapsedMilliseconds() < 90000
    {
        Threading.Thread.sleep(10'ms)
        viewer.poll()
    }

    if viewer.probe.failed do
        Console.print(viewer.probe.diagnostics.toString())
    Swag.assert(viewer.running and viewer.frameCount > after)
}
