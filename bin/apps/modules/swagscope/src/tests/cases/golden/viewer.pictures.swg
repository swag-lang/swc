#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// Each viewer in the window the application ships, at the size of its picture, so its golden is
// judged whole against the picture of the charter.
func picturedViewer(fileName: string, light: bool, golden: string, width = 960, height = 600, options: Pixel.Testing.ImageGoldenOptions = {})
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, fileName, light, width, height)
    if window.choices[window.activeChoiceIndex].key == "image"
    {
        let view = assume cast(*Picture.Panel, window.currentView)
        if view.imageView.movie.isAnimated()
        {
            view.imageView.setPaused(true)
            view.imageView.setFrameIndex(0)
            Swag.require(view.imageView.movie.isPaused and view.imageView.movie.frameIndex == 0)
        }
    }

    photographViewer(&host, window, golden, options)
}

// Opens `fileName` in the viewer named `key` rather than the one it opens in.
func picturedWindowAs(host: *Testing.HeadlessHost, fileName, key: string, light: bool)->*ViewerWindow
{
    let window = framedViewerWindow(host, fileName, light)
    for choice, index in window.choices where choice.key == key
    {
        window.selectViewer(cast(u32, index))
        break
    }

    completeQueuedViewerFile(host, window)
    Swag.require(window.choices[window.activeChoiceIndex].key == key)
    return window
}

// Photographs `window` at rest.
func photographViewer(host: *Testing.HeadlessHost, window: *ViewerWindow, golden: string, options: Pixel.Testing.ImageGoldenOptions = {})
{
    window.applyLayout()
    var image = host.renderSettled(window)
    Pixel.Testing.assertImageGolden(&image, golden, options)
}

private func picturedGoldenOptions(maxDifferentPixels: u64)->Pixel.Testing.ImageGoldenOptions
{
    if Env.variable("SWAG_TEST_RENDERER") == "cpu" do
        return {}
    return {maxDifferentPixels: maxDifferentPixels}
}

func picturedFixture(name: string)->String => Path.combine(testSourceRoot(#curlocation), "datas", name)

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

// The byte view of a PNG, as its picture shows it: the chunks as tabs over the grid, the data of
// the image header selected, and the inspector reading the width the caret stands on.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = picturedWindowAs(&host, picturedFixture("title.png"), "hex", false)
    let view   = assume cast(*Viewers.Hex.Panel, window.currentView)

    var labels: Array'String
    for tab in view.structure.tabs do
        labels.add(tab.label)
    Swag.require(view.structure.formatName == "PNG" and labels.count == 6)
    Swag.require(labels[0] == "Signature" and
                 labels[1] == "IHDR" and
                 labels[4] == "IDAT × 9" and
                 labels[5] == "IEND")

    view.grid.selectRange(0x10, 13)
    Swag.require(view.tabs.active == 1)
    with let inspector = view.inspectorView
    {
        Swag.require(.headline == "5 000" and .caption == "u32 BE at 0x00000010")
        Swag.require(.fields.count == 8 and .fields[0].label == "Width" and .fields[0].strong)
        Swag.require(.fields[3].value == "6 · RGBA")
    }

    Swag.require(view.details == "0x10 – 0x1C · 13 bytes selected")
    photographViewer(&host, window, "pictured.hex", picturedGoldenOptions(8))
}

// A Windows program on the binary viewer's report page, as its picture shows it: the name over the
// identity line, the figures, the sections as one bar, the imports by library.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    let window = framedViewerWindow(&host, picturedFixture("viewer.console.exe"), false)
    Swag.require(window.choices[window.activeChoiceIndex].key == "binary")
    let view = assume cast(*Viewers.Binary.Panel, window.currentView)

    with let overview = &view.doc.report.overview
    {
        Swag.require(.identity.count >= 3 and .identity[0] == "PE32+" and .identity[1] == "x64")
        Swag.require(.sections.count != 0 and .sections[0].name == ".text")
        Swag.require(.strings != 0)
        Swag.require(.libraries.count != 0)
        Swag.require(.imports != 0)
    }

    Swag.require(view.page.isLocallyVisible() and not view.list.isLocallyVisible())
    photographViewer(&host, window, "pictured.binary.page")

    view.showPage(false)
    Swag.require(view.list.isLocallyVisible() and not view.page.isLocallyVisible())
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
