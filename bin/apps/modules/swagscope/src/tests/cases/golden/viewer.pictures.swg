#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

#[Swag.TestTag("golden")]
#test
{
    picturedViewer(picturedFixture("imageset-real-review.webp"), false, "pictured.image", options: picturedGoldenOptions(600))
    picturedViewer(picturedFixture("viewer.csv"), true, "pictured.table.paper")
    picturedViewer(picturedFixture("viewer.page.html"), true, "pictured.html.paper", options: picturedGoldenOptions(512))
    picturedViewer(picturedFixture("segoeui.ttf"), true, "pictured.font.paper", 1280, 800)

    var binaryHost: Testing.HeadlessHost
    photographViewer(&binaryHost, picturedWindowAs(&binaryHost, picturedFixture("segoeui.ttf"), "binary", false), "pictured.binary")
}

// The return action sits after the application glyph and stays centred across viewers.
// Each viewer records its own strip so changes in its caption controls remain visible.
#[Swag.TestTag("golden")]
#test
{
    Swag.require(Sound.acquireEngine(.NoSound))
    defer Sound.releaseEngine()

    let files = [picturedFixture("comprehensive.txt"),
                 picturedFixture("comprehensive.md"),
                 picturedFixture("sample.cpp"),
                 picturedFixture("title.png"),
                 picturedFixture("viewer.csv"),
                 picturedFixture("viewer.page.html"),
                 picturedFixture("segoeui.ttf"),
                 picturedFixture("viewer.pdf"),
                 picturedFixture("ffmpeg-h264-two-aac.mkv"),
                 picturedFixture("pacman_beginning.wav"),
                 picturedFixture("viewer.srt"),
                 picturedFixture("viewer.groove.mid"),
                 picturedFixture("viewer.hex"),
                 picturedFixture("viewer.console.exe")]

    for file, index in files
    {
        let light  = index % 2 == 1
        var host: Testing.HeadlessHost
        let height = Utf8.endsWith(file.toString(), ".mkv") ? 800 : 128
        let window = framedViewerWindow(&host, file.toString(), light, 1280, height)
        Swag.require(window.choices.count != 0 and window.activeChoiceIndex < window.choices.count,
                     "return strip fixture must open in a document viewer")
        if window.choices[window.activeChoiceIndex].key == "video"
        {
            let view = assume cast(*Film.Panel, window.currentView)
            pinVideoFrame(view, 0)

            // This golden measures the return command's window placement. Keep decoded video
            // out of its backdrop so a browser or GPU load cannot choose pixels behind the strip.
            view.imageView.show(false)
        }

        window.explorer = Explorer.create(window.documentPanel, window)
        window.explorer.setShown(false)
        window.explorerActive = true
        window.refreshExplorerCaption()
        host.surface.setTitle("Swag Scope")
        host.surfaceWnd.sendResizeEvent()

        let button  = window.returnExplorerCaptionButton
        let metrics = host.theme.metrics
        let client  = host.surfaceWnd.clientRect()
        button.show(true)
        Swag.require(button.isLocallyVisible())
        Swag.require(Math.abs(button.position.vertCenter() - metrics.wnd_StripHeight * 0.5) < 0.5)
        Swag.require(button.position.x > client.x and button.position.x < client.horzCenter())

        var image = host.renderSettled(&host.surfaceWnd)
        image.crop({0, 0, image.width, cast(s32, metrics.wnd_StripHeight)})
        var golden = Format.toString("viewer.return.%", Path.fileName(file.toString()) orelse "document")
        if window.outlineCaptionButton.isLocallyVisible() do
            golden += ".outline"
        golden += light ? ".paper" : ".ink"
        Pixel.Testing.assertImageGolden(&image, golden.toString())
    }
}
