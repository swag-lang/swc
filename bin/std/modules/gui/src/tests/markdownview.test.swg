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

// Inline HTML is tokenized by the HTML parser before its semantics join Markdown rich text.
#test
{
    @assert(Markdown.renderInline("Press <kbd>Ctrl</kbd> and <strong>go</strong>.") == "Press <c>Ctrl</c> and <b>go</b>.")
    @assert(Markdown.renderInline("**Use <span>HTML</span> inside emphasis**") == "<b>Use HTML inside emphasis</b>")
    @assert(Markdown.renderInline("<a href=\"https://example.com\">Example</a>") == "<a>Example</a><t>https://example.com</t>")
    @assert(Markdown.renderInline("<span>&amp;lt; &lt;tag&gt;</span>") == "&lt; <<tag>")
    @assert(Markdown.renderInline("<span>*&lt;tag&gt;*</span>") == "<i><<tag></i>")
}

// Raw HTML blocks use the HTML document engine, including the centered image pattern used by
// the repository README, instead of leaking their tags into Markdown text.
#test
{
    let source = "<p align=\"center\">\n    <img src=\"web/imgs/swag_icon.png\" width=\"120\" height=\"120\" alt=\"Swag\">\n</p>\n\n<h1 align=\"center\">Swag</h1>\n\nAfter."
    let blocks = Markdown.parseBlocks(source)
    @assert(blocks.count == 3)
    @assert(blocks[0].kind == .Html)
    @assert(blocks[1].kind == .Html)
    @assert(blocks[2].kind == .Paragraph)

    var host: Testing.HeadlessHost
    host.setup(720, 480)
    defer host.shutdown()

    let view = Markdown.View.createText(&host.root, source)
    view.resize(720, 480)
    view.applyLayout()
    view.layoutDocument()

    @assert(view.blocks.count == 3)
    @assert(view.blocks[0].html != null and view.blocks[1].html != null)
    var hasImage: bool
    var imageNode = HtmlNoNode
    var paragraph = HtmlNoNode
    for node, index in view.blocks[0].html!.document.nodes where node.tag == .Img
    {
        hasImage  = true
        imageNode = cast(u32) index
    }

    for node, index in view.blocks[0].html!.document.nodes where node.tag == .P do
        paragraph = cast(u32) index
    @assert(hasImage)
    @assert(paragraph != HtmlNoNode and view.blocks[0].html!.layout.styleOfNode(paragraph).textAlign == .Center)
    @assert(imageNode != HtmlNoNode and view.blocks[0].html!.layout.styleOfNode(imageNode).width == HtmlLength.pixels(120))
    @assert(view.blocks[0].html!.layout.styleOfNode(imageNode).height == HtmlLength.pixels(120))
    @assert(view.blocks[1].html!.document.textContent(0) == "Swag")
    @assert(view.blocks[0].wnd.position.height > 0 and view.blocks[1].wnd.position.height > 0)
    Testing.assertContentFits(view)
}

// The scroll surface hidden inside an embedded HTML block must not consume a wheel event that no
// independently scrollable CSS region claimed; the Markdown document remains the scroll owner.
#test
{
    var source = String.from("<p align=\"center\"><b>Embedded HTML block</b></p>\n\n")
    for index in 64 do
        source += Format.toString("Paragraph % remains below the embedded block.\n\n", index)

    var host: Testing.HeadlessHost
    host.setup(640, 240)
    defer host.shutdown()
    let view = Markdown.View.createText(&host.root, source.toString())
    view.resize(640, 240)
    view.applyLayout()

    @assert(view.blocks[0].html != null)
    let point = view.blocks[0].html!.canvas.surfaceRect().center()
    host.mouseWheel(point, -1)
    @assert(view.scroll.scrollPosition().y > 0)
}

// HTML fragments loaded from a Markdown file resolve local images beside that Markdown file.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let stem          = Format.toString("gui_markdown_html_%", Guid64.random())
    let markdownPath  = Path.combine(tempDirectory.toString(), Format.toString("%.md", stem).toString())
    let imagePath     = Path.combine(tempDirectory.toString(), Format.toString("%.png", stem).toString())
    defer discard catch File.delete(markdownPath)
    defer discard catch File.delete(imagePath)

    var image = Pixel.Image.create(4, 3, .RGBA8)
    image.fill(Pixel.Color.fromArgb(0xFF285078))
    expect image.save(imagePath)
    let source = Format.toString("<p><img src=\"%\" width=\"80%%\" alt=\"Local\"></p>", Path.fileName(imagePath) orelse "")
    discard expect File.writeAllBytes(markdownPath, @mkslice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(320, 240)
    defer host.shutdown()

    let view = Markdown.View.createFile(&host.root, markdownPath)
    view.resize(320, 240)
    view.applyLayout()
    for 64 where view.hasUnloadedSource() do
        host.fireTimers()

    @assert(!view.hasUnloadedSource() and view.blocks.count == 1 and view.blocks[0].html != null)
    @assert(view.blocks[0].html!.images.entries.count == 1 and view.blocks[0].html!.images.entries[0].loaded)
    var imageNode = HtmlNoNode
    for node, index in view.blocks[0].html!.document.nodes where node.tag == .Img do
        imageNode = cast(u32) index
    @assert(imageNode != HtmlNoNode)
    @assert(view.blocks[0].html!.layout.styleOfNode(imageNode).width.kind == .Percent and view.blocks[0].html!.layout.styleOfNode(imageNode).width.value == 0.8)
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

// Returns the right edge of the last ink of every laid-out line of the first block.
func paragraphLineEdges(view: *Markdown.View)->Array'f32
{
    var result: retval
    var line = -1'f32
    for &atom in view.blocks[0].inline!.atoms where atom.visible and !atom.isSpace
    {
        if atom.position.y != line
        {
            line = atom.position.y
            result.add(atom.position.right())
        }
        else do
            result[result.count - 1] = Math.max(result[result.count - 1], atom.position.right())
    }

    return result
}

// A justified paragraph reaches the far edge of its column on every line a wrap ended, and leaves
// the line the paragraph ends on at its natural width.
//
// The space a wrap leaves at the end of a line is what makes this worth pinning: counted as one
// more gap it absorbs the whole stretch, and the last word of every line stops short of the edge
// while the paragraph still measures as justified.
#test
{
    var host: Testing.HeadlessHost
    host.setup(420, 320)
    defer host.shutdown()

    var style = Markdown.Style.theme()
    style.maxContentWidth = 280
    style.horizontalInset = 20

    let source = "one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen"
    let ragged = Markdown.View.createText(&host.root, source, style)
    ragged.resize(420, 320)
    ragged.applyLayout()
    ragged.layoutDocument()

    style.paragraphAlignment = .Justify
    let flush = Markdown.View.createText(&host.root, source, style)
    flush.resize(420, 320)
    flush.applyLayout()
    flush.layoutDocument()

    let raggedEdges = paragraphLineEdges(ragged)
    let flushEdges  = paragraphLineEdges(flush)
    @assert(raggedEdges.count == flushEdges.count and flushEdges.count >= 3)

    // Justification moves no word to another line: the wrap is decided before the stretch.
    @assert(ragged.blocks[0].inline!.layoutHeight == flush.blocks[0].inline!.layoutHeight)

    let last = flushEdges.count - 1
    for index in last
    {
        @assert(flushEdges[index] > raggedEdges[index])
        @assert(Math.abs(flushEdges[index] - flushEdges[0]) < 0.5)
    }

    @assert(flushEdges[last] == raggedEdges[last])
    @assert(flushEdges[last] < flushEdges[0] - 1)
}

// Returns the laid-out rectangle of one word of one block, in that block's own coordinates.
func markdownAtomRect(view: *Markdown.View, block: u64, word: string)->Math.Rectangle
{
    for &atom in view.blocks[block].inline!.atoms where atom.visible and atom.text == word do
        return atom.position
    return {}
}

// The document lets its text out: select all, copy, and give it back in reading order.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 480)
    defer host.shutdown()
    expect Clipboard.resetFake()

    let view = Markdown.View.createText(&host.root, "alpha beta\n\ngamma delta")
    view.resize(640, 480)
    view.applyLayout()
    view.layoutDocument()

    @assert(!view.hasSelection())
    view.selectAll()
    @assert(view.hasSelection())
    @assert(view.selectedText() == "alpha beta\ngamma delta")
    @assert(view.copySelection())
    @assert(Clipboard.getString() == "alpha beta\ngamma delta")

    view.clearSelection()
    @assert(!view.hasSelection())
    @assert(!view.copySelection())
}

// A drag selects what it crosses, blocks included, and stops on the byte it was released on
// rather than on the word holding it.
//
// The two ends are a block and an offset in that block's text, never a laid-out position, so the
// same selection survives the relayout a narrower reading measure forces.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 480)
    defer host.shutdown()

    let view = Markdown.View.createText(&host.root, "alpha beta\n\ngamma delta")
    view.resize(640, 480)
    view.applyLayout()
    view.layoutDocument()

    let alpha = markdownAtomRect(view, 0, "alpha")
    let beta  = markdownAtomRect(view, 0, "beta")
    let delta = markdownAtomRect(view, 1, "delta")
    @assert(alpha.width > 0 and beta.width > 0 and delta.width > 0)

    let first  = view.blocks[0].inline!
    let second = view.blocks[1].inline!
    host.drag(first.localToSurface(Math.Point{alpha.x + 1, alpha.vertCenter()}), second.localToSurface(Math.Point{delta.right(), delta.vertCenter()}))
    @assert(view.selectedText() == "alpha beta\ngamma delta")

    // The reading measure changes what the words sit on, not what was selected.
    var narrower = view.documentStyle
    narrower.maxContentWidth = 320
    view.setDocumentStyle(narrower)
    @assert(view.selectedText() == "alpha beta\ngamma delta")

    // A drag from the end of one word to the end of the next takes the space between them.
    host.drag(first.localToSurface(Math.Point{alpha.right(), alpha.vertCenter()}), first.localToSurface(Math.Point{markdownAtomRect(view, 0, "beta").right(), beta.vertCenter()}))
    @assert(view.selectedText() == " beta")

    host.doubleClick(first.localToSurface(Math.Point{alpha.horzCenter(), alpha.vertCenter()}))
    @assert(view.selectedText() == "alpha")

    // Pressing somewhere else drops it, the way every document viewer reads.
    host.click(first.localToSurface(Math.Point{alpha.x + 1, alpha.vertCenter()}))
    @assert(!view.hasSelection())
}

// A table copies as a table: one line per row, one tab between cells.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 480)
    defer host.shutdown()

    let source = "| A | B |\n| --- | --- |\n| x | y |"
    let view   = Markdown.View.createText(&host.root, source)
    view.resize(640, 480)
    view.applyLayout()
    view.layoutDocument()

    @assert(view.blocks.count == 1 and view.blocks[0].table != null)
    view.selectAll()
    @assert(view.selectedText() == "A\tB\nx\ty")
}

// A block a selection runs across, but that owns no text of its own, is taken whole: a formula
// comes out as the mathematics that produced it, since nothing else stands for it in plain text.
#test
{
    var host: Testing.HeadlessHost
    host.setup(760, 620)
    defer host.shutdown()

    let source = expect File.readAllText(markdownFixturePath())
    let view   = Markdown.View.createText(&host.root, source.toString())
    view.resize(760, 620)
    view.applyLayout()
    view.layoutDocument()

    view.selectAll()
    let text = view.selectedText()
    @assert(Utf8.contains(text.toString(), "Markdown viewer fixture"))
    @assert(Utf8.contains(text.toString(), "\\frac{x}{2}"))
    @assert(Utf8.contains(text.toString(), "\\int_0^1 x^2"))
    @assert(Utf8.contains(text.toString(), "Independent scrolling"))
    @assert(Utf8.contains(text.toString(), "func answer()->u32 => 42"))

    // Nothing of the marked-up source reaches the clipboard: what comes out is what is read.
    @assert(!Utf8.contains(text.toString(), "<b>"))
    @assert(!Utf8.contains(text.toString(), "**bold**"))
}

// The selection is one band per line, not one per word.
//
// Painting it from each glyph's own box is what makes a selection look hatched: it breaks at every
// space, and every change of size inside a sentence gives its own height. The bands are taken from
// the line boxes instead, so consecutive lines abut exactly and a column crossing that boundary
// never shows the page through it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(420, 260)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)

    var style = Markdown.Style.theme()
    style.maxContentWidth = 300
    style.horizontalInset = 20

    let view = Markdown.View.createText(&host.root, "one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen", style)
    view.resize(420, 260)
    view.applyLayout()
    view.layoutDocument()
    view.selectAll()

    let inline = view.blocks[0].inline!
    @assert(inline.lines.count >= 3)
    for index in inline.lines.count - 1 do
        @assert(Math.abs(inline.lines[index].top + inline.lines[index].height - inline.lines[index + 1].top) < 0.01)

    host.settleAnimations(&host.root, 4)
    var image = host.render(&host.root)

    // A column an early word stands in, walked across the boundary between the first two lines.
    let ground = view.themeColors().view_Bk
    let column = inline.localToSurface(Math.Point{inline.atoms[0].position.x + 2, 0})
    let above  = inline.localToSurface(Math.Point{0, inline.lines[0].top + inline.lines[0].height - 3})
    let below  = inline.localToSurface(Math.Point{0, inline.lines[1].top + 3})
    @assert(below.y > above.y)
    for y in cast(s32) above.y to cast(s32) below.y do
        @assert(image.pixelColor(cast(s32) column.x, y) != ground)
}

// The context menu and the keyboard reach the same two commands.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 480)
    defer host.shutdown()
    expect Clipboard.resetFake()

    let view = Markdown.View.createText(&host.root, "menu content")
    view.resize(640, 480)
    view.applyLayout()
    view.layoutDocument()

    host.clickPopupMenuItemWhenShown(Markdown.View.CtxSelectAll)
    view.showContextMenu({50, 50})
    host.pump()
    @assert(view.selectedText() == "menu content")

    host.clickPopupMenuItemWhenShown(Markdown.View.CtxCopy)
    view.showContextMenu({50, 50})
    host.pump()
    @assert(Clipboard.getString() == "menu content")

    view.clearSelection()
    view.setFocus()
    host.keyPress(.A, .Control)
    @assert(view.selectedText() == "menu content")

    expect Clipboard.resetFake()
    host.keyPress(.C, .Control)
    @assert(Clipboard.getString() == "menu content")

    host.keyPress(.Escape)
    @assert(!view.hasSelection())
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

// An ordinary document stops reporting active work when enough content is resident, even though
// its lazy source remains available for later wheel navigation.
#test
{
    let fileName = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("gui_markdown_wheel_%.md", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source: String
    for index in 256 do
        source += Format.toString("## README section %\n\nA paragraph remains available for progressive wheel navigation.\n\n", index)
    @assert(source.length > 8 * 1024)
    discard expect File.writeAllBytes(fileName, @mkslice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(720, 360)
    defer host.shutdown()
    let view = Markdown.View.createFile(&host.root, fileName)
    view.resize(720, 360)
    view.applyLayout()
    host.fireTimer(view.loadTimer)

    for 64 where view.isLoading() do
        host.fireTimers()
    @assert(!view.isLoading() and view.hasUnloadedSource())

    for 16 do
        host.mouseWheel({360, 180}, -1)
    @assert(view.isLoading())

    var steps = 0'u32
    while view.isLoading() and steps < 4_000
    {
        host.fireTimers()
        steps += 1
    }

    @assert(!view.isLoading())
    @assert(view.hasUnloadedSource())
    @assert(view.scroll.scrollPosition().y > 0)
}

// Sequential wheel reading evicts the old blocks once one bounded source window has been
// materialized. Reading in small chunks is not enough: without this cap a trip to EOF retains the
// complete Markdown document as windows, inline atoms and nested HTML views.
#test
{
    let fileName = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("gui_markdown_resident_cap_%.md", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source: String
    for index in 16_000 do
        source += Format.toString("## Bounded section %\n\nA paragraph is evicted after the resident source budget.\n\n", index)
    @assert(source.length > 1024 * 1024)
    discard expect File.writeAllBytes(fileName, @mkslice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(720, 360)
    defer host.shutdown()
    let view = Markdown.View.createFile(&host.root, fileName)
    view.resize(720, 360)
    view.applyLayout()

    var steps = 0'u32
    while view.bytesRead - view.residentStart < 256 * 1024 and steps < 8_000
    {
        let viewport = view.scroll.paddedClientRect()
        view.scroll.setScrollPos(0, Math.max(view.contentHeight - viewport.height * 0.5, 0))
        view.streamStep()
        steps += 1
    }

    @assert(steps < 8_000)
    @assert(view.bytesRead - view.residentStart <= 256 * 1024 + 8 * 1024)
    @assert(view.blocks.count < 10_000)
    @assert(view.hasUnloadedSource())
    @assert(!view.needsMore())

    let firstStart = view.residentStart
    view.scroll.setScrollPos(0, view.virtualHeight * 0.75)
    @assert(view.pendingSeek)
    host.fireTimers()
    @assert(view.residentStart > firstStart)
    @assert(view.bytesRead - view.residentStart <= 256 * 1024 + 8 * 1024)
    @assert(view.blocks.count < 10_000)
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

    @assert(view.hasUnloadedSource())
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
    while view.hasUnloadedSource() and steps < 4_000
    {
        view.streamStep()
        steps += 1
    }

    @assert(!view.hasUnloadedSource())
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
    for 64 where view.hasUnloadedSource() do
        host.fireTimers()
    @assert(!view.hasUnloadedSource())
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
