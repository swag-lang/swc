#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

#test
{
    let fileName = Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/sample.svg")

    let image = expect loadViewerImage(fileName)
    @assert(image.width == 128 and image.height == 64)
}

// Pins the still-image tools beside a real vector document: zoom, fit, native size, and rotate
// read as one icon family while the numeric zoom remains a value rather than an action.
#test
{
    let fileName = Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/sample.svg")

    var host: Gui.Testing.HeadlessHost
    host.setup(720, 440)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let commandBar = Wnd.create'Wnd(&host.root, {0, 0, 0, 52})
    commandBar.dockStyle       = .Bottom
    commandBar.backgroundStyle = .Window
    commandBar.padding         = {16, 8, 16, 8}

    let request = ViewerRequest{&host.root, commandBar, fileName}
    var result: ViewerResult
    createImageViewer(&request, &result)
    @assert(result.view != null and result.commands != null)

    let view = cast(*ImageViewer) result.view!
    view.dockStyle          = .Center
    view.commands.dockStyle = .Center
    host.root.applyLayout()
    host.settleAnimations(&host.root, 4)
    Testing.assertContentFits(&host.root)

    var image = host.render(&host.root)
    Pixel.Testing.assertImageGolden(&image, "viewer.image.document")
}

// A decoder refusal crosses the viewer boundary as data; the viewer creates no competing error UI.
#test
{
    let fileName = Gui.Testing.tempFilePath("filescope-image-", ".png")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "not a PNG")

    var host: Gui.Testing.HeadlessHost
    host.setup(640, 420)
    defer host.shutdown()

    let request = ViewerRequest{&host.root, &host.root, fileName}
    var result: ViewerResult
    createImageViewer(&request, &result)
    @assert(result.view == null and result.commands == null)
    @assert(!result.failureReason.isEmpty())
}
