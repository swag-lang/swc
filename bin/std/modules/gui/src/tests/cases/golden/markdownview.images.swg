#global if #command == Swag.CompilerCommand.Test
#global private
using Swag, Core, Pixel

#[Swag.TestTag("golden")]
#test
{
    let fileName = Testing.tempFilePath("markdown-image-loading-", ".svg")
    defer discard catch File.delete(fileName)
    let secondFileName = Testing.tempFilePath("markdown-image-gallery-", ".svg")
    defer discard catch File.delete(secondFileName)
    const Picture = "<svg width='120' height='60'><rect width='120' height='60' fill='#285078'/></svg>"
    discard expect File.writeAllText(fileName, Picture)
    discard expect File.writeAllText(secondFileName, Picture)
    let source = Format.toString("![Figure](<%>)\n\n<div><img src='%'><img src='%'></div>",
                                 fileName,
                                 fileName,
                                 secondFileName)

    for name, index in ["dark", "light", "hidpi", "paper"]
    {
        var host: Testing.HeadlessHost
        host.setup(480, 240, index == 2 ? 2 : 1)
        if index == 1 do
            host.theme.setLight()

        host.app.deterministicStreaming = false
        let view = Markdown.View.createText(&host.root, source.toString())
        if index == 3 do
            view.setDocumentThemeColors("view_Bk 0xFFFFFFFF\nlabel_Text 0xFF333333")
        view.resize(480, 240)
        view.applyLayout()
        let inline = unwrap view.blocks[0].inline
        let html   = unwrap view.blocks[1].html
        let first  = view.blocks[0].wnd.position
        let second = view.blocks[1].wnd.position
        var image  = host.render(view)
        Swag.assert(not inline.images.parsing.isEmpty() and not html.images.parsing.isEmpty())
        Swag.assert(not inline.images.entries[0].uploaded and not html.images.entries[0].uploaded)
        Pixel.Testing.assertImageGolden(&image, Format.toString("markdownview.images.loading.%", name).toString())

        // Waiting belongs to the test harness; an actual frame only polls the tasks.
        for 3 where not inline.images.parsing.isEmpty() or not html.images.parsing.isEmpty()
        {
            for parsing in inline.images.parsing do
                parsing.task.wait()
            for parsing in html.images.parsing do
                parsing.task.wait()
            Swag.assert(host.surface.isDirty)
            host.surface.paintWnd(view)
        }

        Swag.assert(inline.images.parsing.isEmpty() and html.images.parsing.isEmpty())
        Swag.assert(inline.images.entries[0].uploaded and html.images.entries[0].uploaded)
        Swag.assert(html.images.entries.count == 2 and html.images.entries[1].uploaded)
        Swag.assert(view.blocks[0].wnd.position == first and view.blocks[1].wnd.position == second)
        Swag.assert(inline.images.entries[0].image.pixelColor(60, 30).argb == 0xFF285078)
        Swag.assert(html.images.entries[0].image.pixelColor(60, 30).argb == 0xFF285078)
    }
}
