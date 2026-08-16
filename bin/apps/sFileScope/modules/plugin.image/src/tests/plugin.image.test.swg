#global if #command == Swag.CompilerCommand.Test
#global private

using Core

#test
{
    let fileName = Path.combine(Path.directoryName(#curlocation.fileName)!, "files/sample.svg")

    let image = expect loadViewerImage(fileName)
    @assert(image.width == 128 and image.height == 64)
}

// Every image decoder failure keeps the stable summary and exposes the exact decoder reason below
// it in the semantic error color.
#test
{
    let fileName = Gui.Testing.tempFilePath("filescope-image-", ".png")
    defer discard catch File.delete(fileName)
    expect File.writeAllBytes(fileName, "not a PNG")

    var host: Gui.Testing.HeadlessHost
    host.setup(640, 420)
    defer host.shutdown()

    let commands = Gui.Wnd.create'Gui.Wnd(&host.root, {0, 0, 362, 36})
    let view     = ImagePluginView.create(&host.root, commands, fileName)
    view.resize(640, 380)
    view.applyLayout()

    @assert(!view.imageView.isLocallyVisible())
    @assert(view.children.count == 2)
    let stack   = cast(*Gui.StackLayoutCtrl) view.children[1]
    let summary = cast(*Gui.Label) stack.children[0]
    let detail  = cast(*Gui.Label) stack.children[1]
    @assert(summary.text() == "This image could not be decoded.")
    @assert(@countof(detail.text()) > 0)
    @assert(detail.textColor == detail.themeColors().embInfo_CriticalText)
    Gui.Testing.assertContentFits(view)
}
