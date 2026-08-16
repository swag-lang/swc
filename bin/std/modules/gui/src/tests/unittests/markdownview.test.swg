#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Three-star delimiters distinguish thematic breaks from bold-italic spans.
#test
{
    @assert(renderMarkdownInline("***important***") == "<b><i>important</i></b>")
    @assert(renderMarkdownInline("___important___") == "<b><i>important</i></b>")

    let rules = parseMarkdownBlocks("***\n\n* * *\n\n___")
    @assert(rules.count == 3)
    for &rule in rules do
        @assert(rule.kind == .Rule)
}

// Extended block syntax remains stable at the renderer boundary.
#test
{
    let source = "---\ntitle: Quality\n---\n\n# Heading\n\n[TOC]\n\n> [!WARNING]\n> Check **this**.\n\nA [reference][guide], a footnote[^one], H~2~O and x^2^.\n\n[guide]: https://example.com/guide\n[^one]: Footnote text.\n\n\\[\n\\frac{a}{b}\n\\]\n"
    let blocks = parseMarkdownBlocks(source)

    @assert(blocks.count == 7)
    @assert(blocks[0].kind == .Metadata)
    @assert(blocks[1].kind == .Heading1)
    @assert(blocks[2].kind == .TableOfContents)
    @assert(blocks[3].kind == .AlertWarning)
    @assert(blocks[4].kind == .Paragraph)
    @assert(blocks[5].kind == .Footnote)
    @assert(blocks[6].kind == .Math)
    @assert(Utf8.contains(blocks[4].text.toString(), "<a>reference</a><t>https://example.com/guide</t>"))
    @assert(Utf8.contains(blocks[4].text.toString(), "<sub>2</sub>"))
    @assert(Utf8.contains(blocks[4].text.toString(), "<sup>2</sup>"))
}

// Inline mathematics is parsed by Pixel instead of being approximated with Unicode text.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 320)
    defer host.shutdown()

    let view = MarkdownView.createText(&host.root, "Inline $\\frac{x}{2}$ mathematics.")
    view.resize(640, 320)
    view.applyLayout()
    view.layoutDocument()

    @assert(view.blocks.count == 1)
    @assert(view.blocks[0].inline != null)
    var mathAtoms = 0'u32
    for &atom in view.blocks[0].inline!.atoms where atom.isMath do
        mathAtoms += 1
    @assert(mathAtoms == 1)
    Testing.assertContentFits(view)
}

// End waits for the real EOF and never chases an estimated document height.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("gui_markdown_stream_%.md", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source: String
    for 1_000 do
        source += "## Streamed heading\n\nA paragraph stays on disk until navigation requests it.\n\n"
    discard expect File.writeAllBytes(fileName, @mkslice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(720, 360)
    defer host.shutdown()
    let view = MarkdownView.createFile(&host.root, fileName)
    @assert(view.loadTimer != null)
    view.resize(720, 360)
    view.applyLayout()
    host.fireTimer(view.loadTimer)

    @assert(view.isLoading())
    @assert(view.loadedDocumentHeight() > view.documentStyle.topInset)
    let before = view.scroll.scrollPosition()
    var end = KeyEvent{kind: .Pressed, key: .End}
    @assert(view.handleDocumentKey(&end))
    @assert(view.jumpToEnd)
    @assert(view.scroll.scrollPosition() == before)

    var steps = 0'u32
    while view.isLoading() and steps < 4_000
    {
        view.streamStep()
        steps += 1
    }
    @assert(!view.isLoading())
    @assert(!view.jumpToEnd)
    @assert(view.scroll.scrollPosition().y > before.y)
}
