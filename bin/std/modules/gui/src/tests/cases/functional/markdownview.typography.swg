#global if #command == Swag.CompilerCommand.Test

using Core, Pixel

// Inline layout uses the same resolved, device-snapped advances as painting. Keeping nominal
// widths at a fractional scale lets wider painted glyphs consume the blank before a later word.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 240, dpiScale: 1.5)

    var style = Markdown.Style.theme()
    style.bodyFontSize = 19
    let view   = Markdown.View.createText(&host.root, "abandonnée comme axe", style)
    let inline = unwrap view.blocks[0].inline
    discard inline.layout(600)

    let font   = view.documentFont(.Paragraph, style.bodyFontSize)
    let shaped = Painter.shapeRun("abandonnée", font)
    let width  = Painter.measureStringSnapped(&shaped, deviceScale: inline.deviceScale())
    Swag.require(Math.isEqualEpsilon(inline.atoms[0].position.width, width, 0.001))
    Swag.require(inline.atoms[1].isSpace and inline.atoms[2].text == "comme")
    Swag.require(Math.isEqualEpsilon(inline.atoms[2].position.x, inline.atoms[0].position.width + inline.atoms[1].position.width, 0.001))
}

// Fallback extents belong to the atom's line box, while a cached text batch retains the
// primary font's baseline. The text and its selection must agree after either layout or paint.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 240)
    let view  = Markdown.View.createText(&host.root, "A\u2192\u65E5\u672C\u8A9E")
    var style = Markdown.Style.theme()
    style.bodyTypeFaces[0] = host.theme.res.defaultFsTypeFaceR
    view.setDocumentStyle(style)
    view.resize(640, 240)
    view.applyLayout()
    let inline  = unwrap view.blocks[0].inline
    let font    = view.documentFont(.Paragraph, style.bodyFontSize)
    let shaped  = Painter.shapeRun("A\u2192\u65E5\u672C\u8A9E", font)
    let metrics = shaped.lineMetrics()
    Swag.require(inline.atoms[0].ascent == metrics.ascent)
    Swag.require(inline.atoms[0].descent == metrics.descent)
    Swag.require(inline.atoms[0].position.height == metrics.height)
    Swag.require(inline.lines[0].height >= metrics.height)
    discard host.render(view)
    Swag.require(not inline.textBatches.isEmpty())
    let batch = &inline.textBatches[0]
    let expectedBaseline = inline.atoms[0].position.y + inline.atoms[0].ascent
    Swag.require(Math.isEqualEpsilon(batch.origin.y + font.ascent, expectedBaseline, 0.001))
    for glyph in batch.shaped.glyphs do
        Swag.require(glyph.glyphIndex != 0)
}

// Typeface overrides affect measured text and survive a zoom; empty slots resume the GUI font.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 400)
    let view   = Markdown.View.createText(&host.root, "iiii WWWW")
    let inline = unwrap view.blocks[0].inline
    discard inline.layout(600)
    let original = inline.atoms[0].position.width
    var style    = Markdown.Style.theme()
    style.bodyTypeFaces[0] = host.theme.res.defaultFsTypeFaceR
    view.setDocumentStyle(style)
    discard inline.layout(600)
    let mono = inline.atoms[0].position.width
    Swag.require(mono > original)
    style.bodyFontSize *= 2
    view.setDocumentStyle(style)
    discard inline.layout(600)
    Swag.require(inline.atoms[0].position.width > mono * 1.8)
    view.setDocumentStyle(Markdown.Style.theme())
    discard inline.layout(600)
    Swag.require(inline.atoms[0].position.width == original)
    Swag.require(Markdown.renderInline("word&nbsp;!") == "word\u00A0!")
}

// Styling boundaries are not word boundaries, even when only the punctuation would overflow.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 400)

    for source in ["prefix **word**, suffix", "prefix *word*, suffix", "prefix [word](target), suffix", "prefix `word`, suffix", "prefix **wo**rd, suffix", "prefix (**word**), suffix", "prefix $x$, suffix"]
    {
        let view   = Markdown.View.createText(&host.root, source)
        let inline = unwrap view.blocks[0].inline
        discard inline.layout(600)
        let end   = inline.atoms.count - 2
        let width = inline.atoms[end - 1].position.right() - 1
        inline.layoutWidth = 0
        discard inline.layout(width)
        Swag.require(inline.lines.count >= 2)
        Swag.require(inline.lines[0].last == 2)
        Swag.require(inline.lines[1].first == 2 and inline.lines[1].last >= end)
        view.destroy()
    }
}

// Emergency wrapping must not leave a comma as the final fragment of a long word.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 400)
    let view   = Markdown.View.createText(&host.root, "abcdefghijklmnopqrstuvwx, tail")
    let inline = unwrap view.blocks[0].inline
    discard inline.layout(90)
    Swag.require(inline.atoms[0].text == "abcdefghijklmnopqrstuvwx,")
    Swag.require(inline.text() == "abcdefghijklmnopqrstuvwx, tail")
}

// A blank-separated caption inside an HTML figure remains Markdown. Raw preformatted text and
// comments retain HTML semantics, including their literal punctuation.
#test
{
    let source = "<div align=\"center\">\n\n<img src=\"one.svg\" width=\"49%\"> <img src=\"two.svg\" width=\"49%\">\n\n> *FIG. 5 — **The center.** Two images, one caption.*\n\n</div>\n\nAfter."
    let blocks = Markdown.parseBlocks(source)
    Swag.require(blocks.count == 3)
    Swag.require(blocks[0].kind == .Html and Utf8.contains(blocks[0].text.toString(), "width=\"49%\""))
    Swag.require(Utf8.endsWith(blocks[0].text.toString(), "</div>"))
    Swag.require(blocks[1].kind == .Quote)
    Swag.require(blocks[1].text == "<i>FIG. 5 — <b>The center.</b> Two images, one caption.</i>")
    Swag.require(blocks[2].text == "After.")
    Swag.require(blocks[0].sourceOffset < blocks[1].sourceOffset and blocks[1].sourceOffset < blocks[2].sourceOffset)

    let raw = Markdown.parseBlocks("<div><pre>\n\n> *literal*\n\n</pre><!--\n\n> *hidden*\n--></div>")
    Swag.require(raw.count == 1 and raw[0].kind == .Html)
    Swag.require(Utf8.contains(raw[0].text.toString(), "> *literal*"))
    let hidden = Markdown.parseBlocks("<div hidden>\n\n> *Hidden caption*\n\n</div>")
    Swag.require(hidden.count == 1 and hidden[0].kind == .Html)
    let reference = Markdown.parseBlocks("[target]: https://example.com\n\n<div>\n\n> *A [link][target].*\n\n</div>")
    Swag.require(reference.count == 2 and reference[1].kind == .Quote)
    Swag.require(Utf8.contains(reference[1].text.toString(), "<a>link</a><t>https://example.com</t>"))
}

// HTML created after a document theme was selected must resolve its inherited text color again.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 400)
    let fileName = Testing.tempFilePath("markdown-themed-html-", ".md")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "<div>Readable HTML</div>")
    let view = Markdown.View.createFile(&host.root, fileName)
    view.setDocumentThemeColors("view_Bk 0xFFFFFFFF\nlabel_Text 0xFF333333")
    for 64 where view.isLoading() do
        host.fireTimers()
    view.resize(640, 400)
    view.applyLayout()
    view.layoutDocument()
    let html = unwrap view.blocks[0].html
    for style in html.layout.styles do
        Swag.require(style.color.argb == 0xFF333333)
}
