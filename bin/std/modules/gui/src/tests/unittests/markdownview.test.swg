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

// Nested emphasis consumes the complete delimiter run, including inside block quotes.
#test
{
    @assert(renderMarkdownInline("**bold and *italic***") == "<b>bold and <i>italic</i></b>")
    @assert(renderMarkdownInline("*italic and **bold***") == "<i>italic and <b>bold</b></i>")

    let blocks = parseMarkdownBlocks("> **bold and *italic***\n> *italic and **bold***")
    @assert(blocks.count == 1)
    @assert(blocks[0].kind == .Quote)
    @assert(blocks[0].text == "<b>bold and <i>italic</i></b>\n<i>italic and <b>bold</b></i>")
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

// A multi-megabyte streamed document moves by one rendered line, one viewport page, or a document
// boundary through the real focused keyboard path; End still waits for the real EOF.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("gui_markdown_stream_%.md", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source: String
    for 40_000 do
        source += "## Streamed heading\n\nA paragraph stays on disk until navigation requests it.\n\n"
    @assert(source.length >= 2 * 1024 * 1024)
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
    view.setInitialFocus(view)
    @assert(view.hasFocus())
    let expectedLine = view.theme().createDefaultFont(view.documentStyle.bodyFontSize).height * view.documentStyle.lineHeight
    @assert(view.scroll.verticalScrollStep == expectedLine)
    host.keyPress(Input.Key.Down)
    var navigationSteps = 0'u32
    while view.hasPendingTarget and navigationSteps < 64
    {
        host.fireTimers()
        navigationSteps += 1
    }

    @assert(!view.hasPendingTarget)
    @assert(Math.abs(view.scroll.scrollPosition().y - expectedLine) <= 1)
    host.keyPress(Input.Key.Up)
    @assert(view.scroll.scrollPosition().y == 0)
    host.keyPress(Input.Key.PageDown)
    navigationSteps = 0
    while view.hasPendingTarget and navigationSteps < 64
    {
        host.fireTimers()
        navigationSteps += 1
    }

    @assert(!view.hasPendingTarget)
    let pagePosition = view.scroll.scrollPosition().y
    @assert(pagePosition > expectedLine)
    host.keyPress(Input.Key.PageUp)
    @assert(view.scroll.scrollPosition().y == 0)

    let before = view.scroll.scrollPosition()
    host.keyPress(Input.Key.End)
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
    host.keyPress(Input.Key.Home)
    @assert(view.residentStart == 0)
    @assert(view.scroll.scrollPosition().y == 0)
}

// A resident window opened near EOF retains blocks before its target and requests the preceding
// window while those blocks are still visible. Reverse scrolling must never alternate between a
// forward-only island and an empty virtual gap.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("gui_markdown_reverse_stream_%.md", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source: String
    for index in 16_000 do
        source += Format.toString("## Section %\n\nThe resident window keeps useful context on both sides.\n\n", index)
    const RevealContextSize  = 64 * 1024'u64
    const ReverseContextSize = 8 * 1024'u64
    @assert(source.length > RevealContextSize * 8)
    discard expect File.writeAllBytes(fileName, @mkslice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(720, 360)
    defer host.shutdown()
    let view = MarkdownView.createFile(&host.root, fileName)
    view.resize(720, 360)
    view.applyLayout()

    // The ordinary first resident blocks establish the document's byte-to-height estimate before
    // the reader asks for the end, exactly as the visible application does.
    host.fireTimer(view.loadTimer)
    @assert(view.virtualHeight > view.scroll.paddedClientRect().height)

    let requested = source.length - 1
    @assert(view.revealFileOffset(requested, ""))
    var steps = 0'u32
    while view.hasPendingTarget and steps < 512
    {
        host.fireTimers()
        steps += 1
    }

    @assert(!view.hasPendingTarget and !view.blocks.isEmpty())
    @assert(requested - view.residentStart > ReverseContextSize / 2)
    let firstResidentStart = view.residentStart
    let viewport           = view.scroll.paddedClientRect()
    let nearResidentStart  = view.virtualOrigin + viewport.height * 0.5
    view.scroll.setScrollPos(0, nearResidentStart)

    // The old resident content still covers the viewport when the reverse seek is requested.
    @assert(view.pendingSeek)
    @assert(view.scroll.scrollPosition().y + viewport.height > view.virtualOrigin)
    host.fireTimers()

    steps = 0
    while view.hasPendingTarget and steps < 512
    {
        host.fireTimers()
        steps += 1
    }

    @assert(!view.hasPendingTarget and view.residentStart < firstResidentStart)
    let position = view.scroll.scrollPosition().y
    var visibleBlock: bool
    for &block in view.blocks
    {
        if block.wnd.position.bottom() > position and block.wnd.position.y < position + viewport.height do
            visibleBlock = true
    }

    @assert(visibleBlock)
}
