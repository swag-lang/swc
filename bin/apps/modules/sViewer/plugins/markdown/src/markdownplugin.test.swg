#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel, Gui

#test
{
    let blocks = parseMarkdownBlocks("---\ntitle: Demo\n---\n\n# Document\n\nA **strong** paragraph with $\\alpha + \\beta$ and ==focus==.\n\n- [x] extended\n\n| Name | State |\n|---|---|\n| Math | ready |\n\n$$\\sum_{i=0}^{n} i$$\n\n```swag\nlet value = 42\n```")
    @assert(blocks.count == 7)
    @assert(blocks[0].kind == .Metadata)
    @assert(blocks[1].kind == .Heading1)
    @assert(blocks[2].kind == .Paragraph and Utf8.contains(blocks[2].text.toSlice(), "α + β"))
    @assert(blocks[3].kind == .List)
    @assert(blocks[4].kind == .Table)
    @assert(blocks[5].kind == .Math and Utf8.contains(blocks[5].text.toSlice(), "\\sum"))
    discard catch MathExpression.parse(blocks[5].text.toString()) as parseError
    @assert(parseError == null)
    @assert(blocks[6].kind == .Code)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    let view = MarkdownPluginView.createLoaded(&host.root, "# Typographic Markdown\n\nA quiet reading column with **clear hierarchy**, `inline code`, and enough air to scan.\n\n> A quotation keeps its own rhythm.\n\n| Feature | Support |\n|---|---|\n| Tables | Extended |\n\n$$\\frac{1}{n} \\sum_{i=0}^{n} x_i^2$$")
    view.resize(960, 680)
    view.applyLayout()
    view.layoutDocument()
    @assert(view.blocks.count == 5)
    @assert(view.blocks[0].label!.font().regular!.height > view.blocks[1].label!.font().regular!.height)
    Testing.assertContentFits(view)

    host.settleAnimations(view, 4)
    var image = host.render(view)
    Pixel.Testing.assertImageGolden(&image, "sviewer.markdown.document")
}

#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("sviewer_markdown_stream_%.md", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source: String
    for 2_000 do
        source += "## Streamed heading\n\nA paragraph stays on disk until the viewport approaches it.\n\n"
    discard expect File.writeAllBytes(fileName, @mkslice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    let view = MarkdownPluginView.create(&host.root, fileName)
    view.resize(960, 680)
    view.applyLayout()
    view.layoutDocument()
    view.streamStep()

    @assert(!view.blocks.isEmpty())
    @assert(view.stream.isOpen())
    @assert(expect view.stream.position() < source.length)
}
