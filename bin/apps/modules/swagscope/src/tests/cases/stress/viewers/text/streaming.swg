#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui, Viewers

// Scroll and paint only queue work. Rapid gestures retain one request and publish the latest
// destination after the worker finishes, without synchronously reading at a resident edge.
#[Swag.TestTag("stress")]
#test
{
    let fileName = Testing.tempFilePath("scope-text-continuous-", ".txt")
    defer discard catch File.delete(fileName)
    var source: String
    for index in 12_000 do
        source += Format.toString("// Line % keeps the viewport covered during a resident transition.\n", index)
    discard expect File.writeAllBytes(fileName, source)
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    let commands = Wnd.create'Wnd(&host.root, {0, 0, 200, 36})
    var session  = openTestViewer(PlainText.viewerPlugin(), &host.root, fileName, commandParent: commands)

    with let view = assume cast(*PlainText.Panel, session.view)
    {
        .resize(640, 360)
        .applyLayout()
    }

    completeTextReads(&host, view)

    view.editor.setScrollPosition(Math.Point{0, view.virtualHeight * 0.8})
    view.loadNextChunk()
    Swag.require(view.read.started)
    view.editor.setScrollPosition({0, 0})
    Swag.require(not view.pendingSeek and view.read.wasCancelled())
    completeTextReads(&host, view)
    Swag.require(view.residentStart == 0)

    for ratio in [0.85'f32, 0.15'f32, 0.65'f32]
    {
        let previousStart = view.residentStart
        view.editor.setScrollPosition(Math.Point{0, view.virtualHeight * 0.45})
        view.loadNextChunk()
        Swag.require(view.read.started)
        view.editor.setScrollPosition(Math.Point{0, view.virtualHeight * ratio})
        let requested = view.pendingSeekOffset
        Swag.require(view.pendingSeek and view.read.wasCancelled())
        discard host.render(view)
        Swag.require(view.residentStart == previousStart)
        completeTextReads(&host, view)
        Swag.require(not view.pendingSeek)
        Swag.require(view.residentStart <= requested and view.bytesRead >= requested)
        Swag.require(view.bytesRead - view.residentStart <= 256 * 1024)
    }
}
