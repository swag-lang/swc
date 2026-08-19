#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

func markdownFixturePath()->String
{
    return Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/markdown.comprehensive.md")
}

// The checked-in Markdown fixture exercises the extended block grammar from its canonical data
// directory, rather than rebuilding a second document inside the test source.
#test
{
    let source = expect File.readAllText(markdownFixturePath())
    let blocks = Markdown.parseBlocks(source.toString())

    @assert(blocks.count >= 10)
    @assert(blocks[0].kind == .Metadata)
    var hasTable: bool
    var hasMath:  bool
    var hasCode:  bool
    for &block in blocks
    {
        hasTable = hasTable or block.kind == .Table
        hasMath  = hasMath or block.kind == .Math
        hasCode  = hasCode or block.kind == .Code
    }

    @assert(hasTable and hasMath and hasCode)
}

// Three-star delimiters distinguish thematic breaks from bold-italic spans.
#test
{
    @assert(Markdown.renderInline("***important***") == "<b><i>important</i></b>")
    @assert(Markdown.renderInline("___important___") == "<b><i>important</i></b>")

    let rules = Markdown.parseBlocks("***\n\n* * *\n\n___")
    @assert(rules.count == 3)
    for &rule in rules do
        @assert(rule.kind == .Rule)
}

// Nested emphasis consumes the complete delimiter run, including inside block quotes.
#test
{
    @assert(Markdown.renderInline("**bold and *italic***") == "<b>bold and <i>italic</i></b>")
    @assert(Markdown.renderInline("*italic and **bold***") == "<i>italic and <b>bold</b></i>")

    let blocks = Markdown.parseBlocks("> **bold and *italic***\n> *italic and **bold***")
    @assert(blocks.count == 1)
    @assert(blocks[0].kind == .Quote)
    @assert(blocks[0].text == "<b>bold and <i>italic</i></b>\n<i>italic and <b>bold</b></i>")
}

// Extended block syntax remains stable at the renderer boundary.
#test
{
    let source = "---\ntitle: Quality\n---\n\n# Heading\n\n[TOC]\n\n> [!WARNING]\n> Check **this**.\n\nA [reference][guide], a footnote[^one], H~2~O and x^2^.\n\n[guide]: https://example.com/guide\n[^one]: Footnote text.\n\n\\[\n\\frac{a}{b}\n\\]\n"
    let blocks = Markdown.parseBlocks(source)

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

// Soft-wrapped list items stay in their list, while nested blocks remain independently laid out
// beneath the item that owns them.
#test
{
    let source = "- Found while: a condition was evaluated over a\n  Core.String.\n- Evidence: the failure was observed at\n  src/Compiler/CodeGen/Ast/CodeGen.If.cpp:74.\n\n  ```swag\n  if @countof(box) do\n      return 1\n  ```\n\n  A following paragraph still belongs beneath the evidence.\n- Next step: trace the condition."
    let blocks = Markdown.parseBlocks(source)

    @assert(blocks.count == 4)
    @assert(blocks[0].kind == .List)
    @assert(Utf8.contains(blocks[0].text.toString(), "a Core.String."))
    @assert(Utf8.contains(blocks[0].text.toString(), "at src/Compiler/CodeGen/Ast/CodeGen.If.cpp:74."))
    @assert(blocks[1].kind == .Code)
    @assert(blocks[2].kind == .Paragraph)
    @assert(blocks[3].kind == .List)

    let tasks = Markdown.parseBlocks("- [x] Complete\n- [ ] Pending")
    @assert(tasks.count == 1)
    @assert(Utf8.contains(tasks[0].text.toString(), "<lc>*</lc>"))
    @assert(Utf8.contains(tasks[0].text.toString(), "<lu>*</lu>"))
}

// A literal '<' survives the markup protocol losslessly, in text, code spans and entities alike.
#test
{
    @assert(Markdown.renderInline("a < b > c") == "a << b > c")
    @assert(Markdown.renderInline("`a < b`") == "<c>a << b</c>")
    @assert(Markdown.renderInline("2 &lt; 3 &gt; 1") == "2 << 3 > 1")

    var host: Testing.HeadlessHost
    host.setup(640, 240)
    defer host.shutdown()

    let view = Markdown.View.createText(&host.root, "a < b")
    view.resize(640, 240)
    view.applyLayout()
    view.layoutDocument()

    var rebuilt: String
    for &atom in view.blocks[0].inline!.atoms where !atom.isSpace and !atom.isBreak do
        rebuilt += atom.text
    @assert(rebuilt == "a<b")
    @assert(view.findText("a < b"))
}

// Link destinations keep their exact URL: titles are dropped, parentheses balance, and the angle
// form carries spaces — in the inline form and in a reference definition alike.
#test
{
    @assert(Markdown.renderInline("[x](https://e.com/guide \"Title\")") == "<a>x</a><t>https://e.com/guide</t>")
    @assert(Markdown.renderInline("[x](https://e.com/a(b)c)") == "<a>x</a><t>https://e.com/a(b)c</t>")
    @assert(Markdown.renderInline("[x](<https://e.com/a b>)") == "<a>x</a><t>https://e.com/a b</t>")

    let blocks = Markdown.parseBlocks("A [reference][guide].\n\n[guide]: https://e.com/guide \"Guide title\"")
    @assert(Utf8.contains(blocks[0].text.toString(), "<a>reference</a><t>https://e.com/guide</t>"))
}

// A longer code span quotes literal backticks, and a longer fence displays a shorter one.
#test
{
    @assert(Markdown.renderInline("``a `tick` b``") == "<c>a `tick` b</c>")

    let blocks = Markdown.parseBlocks("````\n```\ncode\n```\n````")
    @assert(blocks.count == 1)
    @assert(blocks[0].kind == .Code)
    @assert(Utf8.contains(blocks[0].text.toString(), "```"))
}

// A trailing backslash is a hard break, and '<br>' breaks a line even inside a table cell.
#test
{
    let blocks = Markdown.parseBlocks("line one\\\nline two")
    @assert(blocks.count == 1)
    @assert(blocks[0].text == "line one\nline two")
    @assert(Markdown.renderInline("cell<br>break") == "cell\nbreak")
}

// Ordered markers renumber from the first written value, per nesting level.
#test
{
    let blocks = Markdown.parseBlocks("1. a\n1. b\n1. c")
    @assert(blocks.count == 1)
    @assert(Utf8.contains(blocks[0].text.toString(), "<lm>1.</lm>"))
    @assert(Utf8.contains(blocks[0].text.toString(), "<lm>2.</lm>"))
    @assert(Utf8.contains(blocks[0].text.toString(), "<lm>3.</lm>"))

    let nested = Markdown.parseBlocks("3. a\n   1. x\n   1. y\n4. b")
    @assert(Utf8.contains(nested[0].text.toString(), "<lm>3.</lm>"))
    @assert(Utf8.contains(nested[0].text.toString(), "<lm>1.</lm>"))
    @assert(Utf8.contains(nested[0].text.toString(), "<lm>2.</lm>"))
    @assert(Utf8.contains(nested[0].text.toString(), "<lm>4.</lm>"))
}

// Underscore emphasis never closes inside a word.
#test
{
    @assert(Markdown.renderInline("_foo_bar_") == "<i>foo_bar</i>")
    @assert(Markdown.renderInline("snake_case_name") == "snake_case_name")
}

// Code blocks preserve the author's indentation; only the space a wrap leaves behind is dropped.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 240)
    defer host.shutdown()

    let view = Markdown.View.createText(&host.root, "```\nzero\n    four\n```")
    view.resize(640, 240)
    view.applyLayout()
    view.layoutDocument()

    @assert(view.blocks.count == 1)
    var zeroX = -1'f32
    var fourX = -1'f32
    for &atom in view.blocks[0].inline!.atoms where atom.visible
    {
        if atom.text == "zero" do
            zeroX = atom.position.x
        elif atom.text == "four" do
            fourX = atom.position.x
    }

    @assert(zeroX >= 0 and fourX > zeroX)
}

// Every occurrence of a find highlights, not only the first one.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 240)
    defer host.shutdown()

    let view = Markdown.View.createText(&host.root, "alpha beta alpha")
    view.resize(640, 240)
    view.applyLayout()
    view.layoutDocument()

    @assert(view.findText("alpha"))
    var hits = 0'u32
    for &atom in view.blocks[0].inline!.atoms where atom.searchHit and !atom.isSpace do
        hits += 1
    @assert(hits == 2)
}

// Table columns size from their content instead of splitting the width evenly.
#test
{
    var host: Testing.HeadlessHost
    host.setup(720, 360)
    defer host.shutdown()

    let source = "| A | Description |\n| --- | --- |\n| x | A much longer description cell |"
    let view   = Markdown.View.createText(&host.root, source)
    view.resize(720, 360)
    view.applyLayout()
    view.layoutDocument()

    @assert(view.blocks.count == 1)
    let table = view.blocks[0].table!
    @assert(table.columnCount == 2)
    @assert(table.columnWidths[1] > table.columnWidths[0] * 2)
}

// Inline mathematics is parsed by Pixel instead of being approximated with Unicode text.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 320)
    defer host.shutdown()

    let view = Markdown.View.createText(&host.root, "Inline $\\frac{x}{2}$ mathematics.")
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

// Find marks the visible words of a match, including one split by inline markup.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 240)
    defer host.shutdown()

    let view = Markdown.View.createText(&host.root, "Before **split search** result.")
    view.resize(640, 240)
    view.applyLayout()
    view.layoutDocument()

    @assert(view.findText("split search"))
    var hits = 0'u32
    for &atom in view.blocks[0].inline!.atoms where atom.searchHit do
        hits += 1
    @assert(hits >= 2)
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
    let view = Markdown.View.createFile(&host.root, fileName)
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
    let view = Markdown.View.createFile(&host.root, fileName)
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

// A file-open failure stays inspectable even when no observer was connected during construction.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()

    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("missing_gui_markdown_%.md", Guid64.random()).toString())
    let view = Markdown.View.createFile(&host.root, path)
    @assert(!view.failureReason.isEmpty())
    for 64 where view.isLoading() do
        host.fireTimers()
    @assert(!view.isLoading())
}

// A decoder failure found by the progressive reader is signaled after construction.
#test
{
    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("invalid_gui_markdown_%.md", Guid64.random()).toString())
    defer discard catch File.delete(path)
    let bytes: [3] u8 = ['a', 0, 'b']
    discard expect File.writeAllBytes(path, @mkslice(cast(const [*] u8) @dataof(bytes), @countof(bytes)))

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()

    var reported: String
    let view = Markdown.View.createFile(&host.root, path)
    view.sigLoadFailed += func|&reported|(markdown, reason)
    {
        discard markdown
        reported = reason
    }

    for 64 where reported.isEmpty() do
        host.fireTimers()
    @assert(!reported.isEmpty())
    @assert(reported == view.failureReason)
}
