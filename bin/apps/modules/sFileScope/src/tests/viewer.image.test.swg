#global if #command == Swag.CompilerCommand.Test
#global private

using Core

#test
{
    let fileName = Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/sample.svg")

    let image = expect loadViewerImage(fileName)
    @assert(image.width == 128 and image.height == 64)
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
