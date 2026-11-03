#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

#test
{
    let source   = "---\ntitle: metadata\n---\n# **Guide** &amp; `code`\n\n```md\n# Not a heading\n```\n\nSubtitle\n--------\n\n### [Repeated](https://example.org)\n\n### Repeated\n\n#### ![Figure](figure.png) and <literal>\n"
    let headings = Markdown.parseHeadings(source)
    Swag.require(headings.count == 5)
    Swag.require(headings[0].title == "Guide & code" and headings[0].level == 1)
    Swag.require(headings[1].title == "Subtitle" and headings[1].level == 2)
    Swag.require(headings[2].title == "Repeated" and headings[3].title == "Repeated")
    Swag.require(headings[2].sourceOffset < headings[3].sourceOffset)
    Swag.require(headings[4].title == "Figure and <literal>")
    Swag.require(Utf8.startsWith(source[headings[1].sourceOffset to], "Subtitle"))
    Swag.require(Markdown.parseHeadings("Just a paragraph.").isEmpty())
    let bom = Markdown.parseHeadings("\uFEFF# Title\r\n\r\n## Subtitle\r\n")
    Swag.require(bom.count == 2 and bom[0].sourceOffset == 3 and bom[1].sourceOffset == 14)
}

// A byte-addressed outline lands on its exact heading, even outside the initial resident window.
#test
{
    var source: String = "# Repeated\n\n"
    for 1200 do
        source += "A paragraph before the destination, with enough text to fill the reading column.\n\n"
    let offset = source.length
    source += "## Repeated\n\n"
    for 20 do
        source += "A paragraph after the destination.\n\n"
    let fileName = Testing.tempFilePath("outline-markdown-", ".md")
    discard expect File.writeAllBytes(fileName, cast(const [..] u8, source.toString()))
    defer discard catch File.delete(fileName)
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    let view = Markdown.View.createFile(&host.root, fileName)
    view.resize(640, 360)
    view.applyLayout()
    let queued = view.revealHeading(offset)
    Swag.require(queued)
    Swag.require(not view.pendingSeek, "layout must not replace the heading jump with a scrollbar seek")

    // The first paint must show the destination; loading timers are deliberately withheld.
    discard host.render(view)
    Swag.require(not view.hasPendingTarget and view.retainedBlocks.isEmpty())
    Swag.require(view.blocks.count < 64, "a heading jump prepares its viewport, not the preceding section")
    var found: bool
    for block in view.blocks where block.sourceOffset == offset
    {
        found = true
        Swag.require(block.kind == .Heading2)
        Swag.require(Math.abs(view.scroll.scrollPosition().y - (block.wnd.position.y - view.documentStyle.topInset)) < 2)
    }

    Swag.require(found, "the requested heading must remain in the resident window")
    Swag.require(view.readingOffset() == offset)
    let position = view.scroll.scrollPosition()
    for 64 where view.isLoading() do
        host.fireTimers()
    Swag.require(view.scroll.scrollPosition() == position)
    var style = view.documentStyle
    style.bodyFontSize = 24
    view.setDocumentStyle(style)
    let first = view.revealHeading(0)
    Swag.require(first)
    for 256 where view.isLoading() do
        host.fireTimers()
    Swag.require(view.scroll.scrollPosition().y < 2)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    let source = "<html><body><h1>Guide &amp; help</h1><pre>h2 is text</pre><h2 style='display:none'>Hidden</h2><h2 style='visibility:hidden'>Invisible</h2><div style='height:900px'></div><h3><em>Repeated</em></h3><h3>Repeated</h3><div style='height:900px'></div></body></html>"
    let view   = HtmlView.createText(&host.root, source)
    view.resize(640, 360)
    view.applyLayout()
    let headings = view.headings()
    Swag.require(headings.count == 3)
    Swag.require(headings[0].title == "Guide & help" and headings[0].level == 1)
    Swag.require(headings[1].level == 3 and headings[1].title == "Repeated")
    let moved = view.revealFileOffset(headings[2].sourceOffset, "")
    Swag.require(moved)
    let node = view.nodeAtSourceOffset(headings[2].sourceOffset)
    let box  = view.boxOfNode(node)
    Swag.require(Math.abs(view.scroll.scrollPosition().y - (view.layout.constBox(box).rect.y - 24)) < 2)
    let before = view.scroll.scrollPosition().y
    view.setDocumentStyle({bodyFontSize: 24})
    let after = view.headings()
    Swag.require(after.count == 3 and after[2].sourceOffset == headings[2].sourceOffset)
    Swag.require(view.scroll.scrollPosition().y >= before)
}

// Named destinations and cycles are read independently of page rendering; cropping and rotation
// produce the same top-left page coordinates as the displayed content.
#test
{
    let path    = Path.combine(testSourceRoot(#curlocation), "datas/document-outline.pdf")
    var reader  = expect Pdf.Reader.open(path)
    let outline = reader.loadOutline()
    Swag.require(outline.count == 4)
    Swag.require(outline[0].title == "Chapter one" and outline[0].level == 1 and outline[0].pageIndex == 0)
    Swag.require(outline[1].title == "Section é" and outline[1].level == 2 and outline[1].pageIndex == 1)
    Swag.require(outline[1].position == Math.Point{24, 400})
    Swag.require(outline[2].pageIndex == 2)
    Swag.require(outline[2].position == Math.Point{980, 20})
    Swag.require(outline[3].pageIndex == Swag.U64.Max)
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    let view = PdfView.create(&host.root)
    var page = expect reader.loadPage(0)
    view.exchangeDocument(&reader, &page)
    view.resize(640, 360)
    view.applyLayout()
    view.setZoom(1)
    view.showPosition(outline[1].pageIndex, outline[1].position)
    Swag.require(view.pageIndex == 1)
    Swag.require(Math.abs(view.scroll.scrollPosition().y - (view.pageRect(1).y + 400 - 12)) < 2)
    view.setPageLayout(.Single)
    view.showPosition(1, {24, 400})
    Swag.require(view.pageIndex == 1 and view.scroll.scrollPosition().y >= 390)
}
