#global if #command == Swag.CompilerCommand.Test

using Core, Pixel

// Fallback extents belong to the atom's line box, while a cached text batch retains the
// primary font's baseline. The text and its selection must agree after either layout or paint.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 240)
    defer host.shutdown()
    let view  = Markdown.View.createText(&host.root, "A\u2192\u65E5\u672C\u8A9E")
    var style = Markdown.Style.theme()
    style.bodyTypeFaces[0] = host.theme.res.defaultFsTypeFaceR
    view.setDocumentStyle(style)
    view.resize(640, 240)
    view.applyLayout()
    let inline  = view.blocks[0].inline!
    let font    = view.documentFont(.Paragraph, style.bodyFontSize)
    let shaped  = Painter.shapeRun("A\u2192\u65E5\u672C\u8A9E", font)
    let metrics = shaped.lineMetrics()
    Swag.assert(inline.atoms[0].ascent == metrics.ascent)
    Swag.assert(inline.atoms[0].descent == metrics.descent)
    Swag.assert(inline.atoms[0].position.height == metrics.height)
    Swag.assert(inline.lines[0].height >= metrics.height)
    discard host.render(view)
    Swag.assert(not inline.textBatches.isEmpty())
    let batch = &inline.textBatches[0]
    let expectedBaseline = inline.atoms[0].position.y + inline.atoms[0].ascent
    Swag.assert(Math.isEqualEpsilon(batch.origin.y + font.ascent, expectedBaseline, 0.001))
    for glyph in batch.shaped.glyphs do
        Swag.assert(glyph.glyphIndex != 0)
}

// Typeface overrides affect measured text and survive a zoom; empty slots resume the GUI font.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 400)
    defer host.shutdown()
    let view   = Markdown.View.createText(&host.root, "iiii WWWW")
    let inline = view.blocks[0].inline!
    discard inline.layout(600)
    let original = inline.atoms[0].position.width
    var style    = Markdown.Style.theme()
    style.bodyTypeFaces[0] = host.theme.res.defaultFsTypeFaceR
    view.setDocumentStyle(style)
    discard inline.layout(600)
    let mono = inline.atoms[0].position.width
    Swag.assert(mono > original)
    style.bodyFontSize *= 2
    view.setDocumentStyle(style)
    discard inline.layout(600)
    Swag.assert(inline.atoms[0].position.width > mono * 1.8)
    view.setDocumentStyle(Markdown.Style.theme())
    discard inline.layout(600)
    Swag.assert(inline.atoms[0].position.width == original)
    Swag.assert(Markdown.renderInline("word&nbsp;!") == "word\u00A0!")
}

// Styling boundaries are not word boundaries, even when only the punctuation would overflow.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 400)
    defer host.shutdown()

    for source in ["prefix **word**, suffix", "prefix *word*, suffix", "prefix [word](target), suffix", "prefix `word`, suffix", "prefix **wo**rd, suffix", "prefix (**word**), suffix", "prefix $x$, suffix"]
    {
        let view   = Markdown.View.createText(&host.root, source)
        let inline = view.blocks[0].inline!
        discard inline.layout(600)
        let end   = inline.atoms.count - 2
        let width = inline.atoms[end - 1].position.right() - 1
        inline.layoutWidth = 0
        discard inline.layout(width)
        Swag.assert(inline.lines.count >= 2)
        Swag.assert(inline.lines[0].last == 2)
        Swag.assert(inline.lines[1].first == 2 and inline.lines[1].last >= end)
        view.destroy()
    }
}

// Emergency wrapping must not leave a comma as the final fragment of a long word.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 400)
    defer host.shutdown()
    let view   = Markdown.View.createText(&host.root, "abcdefghijklmnopqrstuvwx, tail")
    let inline = view.blocks[0].inline!
    discard inline.layout(90)
    Swag.assert(inline.atoms[0].text == "abcdefghijklmnopqrstuvwx,")
    Swag.assert(inline.text() == "abcdefghijklmnopqrstuvwx, tail")
}

// A blank-separated caption inside an HTML figure remains Markdown. Raw preformatted text and
// comments retain HTML semantics, including their literal punctuation.
#test
{
    let source = "<div align=\"center\">\n\n<img src=\"one.svg\" width=\"49%\"> <img src=\"two.svg\" width=\"49%\">\n\n> *FIG. 5 — **The center.** Two images, one caption.*\n\n</div>\n\nAfter."
    let blocks = Markdown.parseBlocks(source)
    Swag.assert(blocks.count == 3)
    Swag.assert(blocks[0].kind == .Html and Utf8.contains(blocks[0].text.toString(), "width=\"49%\""))
    Swag.assert(Utf8.endsWith(blocks[0].text.toString(), "</div>"))
    Swag.assert(blocks[1].kind == .Quote)
    Swag.assert(blocks[1].text == "<i>FIG. 5 — <b>The center.</b> Two images, one caption.</i>")
    Swag.assert(blocks[2].text == "After.")
    Swag.assert(blocks[0].sourceOffset < blocks[1].sourceOffset and blocks[1].sourceOffset < blocks[2].sourceOffset)

    let raw = Markdown.parseBlocks("<div><pre>\n\n> *literal*\n\n</pre><!--\n\n> *hidden*\n--></div>")
    Swag.assert(raw.count == 1 and raw[0].kind == .Html)
    Swag.assert(Utf8.contains(raw[0].text.toString(), "> *literal*"))
    let hidden = Markdown.parseBlocks("<div hidden>\n\n> *Hidden caption*\n\n</div>")
    Swag.assert(hidden.count == 1 and hidden[0].kind == .Html)
    let reference = Markdown.parseBlocks("[target]: https://example.com\n\n<div>\n\n> *A [link][target].*\n\n</div>")
    Swag.assert(reference.count == 2 and reference[1].kind == .Quote)
    Swag.assert(Utf8.contains(reference[1].text.toString(), "<a>link</a><t>https://example.com</t>"))
}

// HTML created after a document theme was selected must resolve its inherited text color again.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 400)
    defer host.shutdown()
    host.theme.setSwagDark()
    host.notify(.ThemeChanged)
    let fileName = Testing.tempFilePath("markdown-themed-html-", ".md")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllBytes(fileName, cast(const [..] u8) "<div>Readable HTML</div>")
    let view = Markdown.View.createFile(&host.root, fileName)
    view.setDocumentThemeColors("view_Bk 0xFFFFFFFF\nlabel_Text 0xFF333333")
    for 64 where view.isLoading() do
        host.fireTimers()
    view.resize(640, 400)
    view.applyLayout()
    view.layoutDocument()
    let html = view.blocks[0].html!
    for style in html.layout.styles do
        Swag.assert(style.color.argb == 0xFF333333)
}
