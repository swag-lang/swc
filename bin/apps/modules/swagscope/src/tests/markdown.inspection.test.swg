#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 800, 1.5)
    defer host.shutdown()
    let view = Markdown.View.createFile(&host.root, "C:/Perso/chouette/atelier-chouette/manuscrit.md")
    view.resize(960, 800)
    applyMarkdownViewerStyle(view, 1, 1)
    view.applyLayout()
    for 64 where view.isLoading() do
        host.fireTimers()
    var image = host.render(view)
    expect image.save(Path.combine(Path.directoryName(#curlocation.fileName)!, "scope-manuscrit.png"))
    var found = false
    for 64 where !found
    {
        host.mouseWheel({480, 400}, -4)
        host.finishAnimations()
        host.fireTimers()
        found = view.findText("Fig. 1")
    }
    Swag.assert(found)
    view.clearSearchHighlight()
    image = host.render(view)
    expect image.save(Path.combine(Path.directoryName(#curlocation.fileName)!, "scope-figure.png"))
}
