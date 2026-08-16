using Core, Pixel, Gui, Gui.Testing

#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_markdown_%.md", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    let source = "# Typographic Markdown\n\nA quiet reading column with **clear hierarchy**, `inline code`, and enough air to scan.\n\n> [!NOTE]\n> A themed alert keeps its own rhythm.\n\n| Feature | Support |\n|:---|---:|\n| Tables | Extended |\n\nInline math $x^2 + y^2$ and display math:\n\n$$\\frac{1}{n} \\sum_{i=0}^{n} x_i^2$$"
    discard expect File.writeAllBytes(fileName, @mkslice(cast(const [*] u8) @dataof(source), @countof(source)))

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    var commands: #null *Wnd
    var details: String
    let wnd = sFileScopePluginCreate(&host.root, &host.root, fileName, 3'u32, &commands, &details)
    @assert(wnd != null)
    @assert(commands == null)
    @assert(Utf8.contains(details.toString(), "Markdown"))

}

#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let style = MarkdownStyle.theme()
    let view  = MarkdownView.createText(&host.root, "# Typographic Markdown\n\nA quiet reading column with **clear hierarchy**, `inline code`, and enough air to scan.\n\n> [!NOTE]\n> A themed alert keeps its own rhythm.\n\n| Feature | Support |\n|:---|---:|\n| Tables | Extended |\n\nInline math $x^2 + y^2$ and display math:\n\n$$\\frac{1}{n} \\sum_{i=0}^{n} x_i^2$$", style)
    view.resize(960, 680)
    view.applyLayout()

    @assert(!view.isLoading())
    @assert(view.loadedDocumentHeight() > style.topInset)
    @assert(view.documentStyle.maxContentWidth == style.maxContentWidth)
    Testing.assertContentFits(view)
    host.settleAnimations(view, 8)
    var image = host.render(view)
    Pixel.Testing.assertImageGolden(&image, "plugin.markdown.document")
}
