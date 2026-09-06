#global if #command == Swag.CompilerCommand.Test
#global private
using Core, Gui, Pixel

#[Swag.TestTag("golden")]
#test
{
    let fileName = "C:/Perso/chouette/atelier-chouette/manuscrit.md"
    let source = expect File.readAllText(fileName)
    let query = "Fig. 1 — Le nombre est une couleur"
    let offset = source.indexOf(query)
    Swag.assert(offset != Swag.U64.Max)
    var host: Testing.HeadlessHost
    host.setup(1000, 1000)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)
    var result = openTestViewer(markdownViewerPlugin(), &host.root, fileName)
    Swag.assert(result.view != null)
    let view = cast(*Markdown.View) result.view!
    applyMarkdownViewerStyle(view, 1, 1)
    view.resize(1000, 1000)
    view.applyLayout()
    Swag.assert(view.revealFileOffset(offset, query))
    var bounds: Math.Rectangle
    for 300 where !view.searchMatchRect(&bounds) do
        host.fireTimers()
    Swag.assert(view.searchMatchRect(&bounds) and bounds.width == 464 and bounds.height == 464)
    for 12 do
        host.fireTimers()
    view.clearSearchHighlight()
    var image = host.render(view)
    Pixel.Testing.assertImageGolden(&image, "manuscript.size.probe")
}
