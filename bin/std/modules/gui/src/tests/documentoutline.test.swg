#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

#test
{
    let source   = "---\ntitle: metadata\n---\n# **Guide** &amp; `code`\n\n```md\n# Not a heading\n```\n\nSubtitle\n--------\n\n### [Repeated](https://example.org)\n\n### Repeated\n\n#### ![Figure](figure.png) and <literal>\n"
    let headings = Markdown.parseHeadings(source)
    Swag.assert(headings.count == 5)
    Swag.assert(headings[0].title == "Guide & code" and headings[0].level == 1)
    Swag.assert(headings[1].title == "Subtitle" and headings[1].level == 2)
    Swag.assert(headings[2].title == "Repeated" and headings[3].title == "Repeated")
    Swag.assert(headings[2].sourceOffset < headings[3].sourceOffset)
    Swag.assert(headings[4].title == "Figure and <literal>")
    Swag.assert(Utf8.startsWith(source[headings[1].sourceOffset to], "Subtitle"))
    Swag.assert(Markdown.parseHeadings("Just a paragraph.").isEmpty())
    let bom = Markdown.parseHeadings("\uFEFF# Title\r\n\r\n## Subtitle\r\n")
    Swag.assert(bom.count == 2 and bom[0].sourceOffset == 3 and bom[1].sourceOffset == 14)
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
    discard expect File.writeAllBytes(fileName, cast(const [..] u8) source.toString())
    defer discard catch File.delete(fileName)
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()
    let view = Markdown.View.createFile(&host.root, fileName)
    view.resize(640, 360)
    view.applyLayout()
    let queued = view.revealHeading(offset)
    Swag.assert(queued)

    // The first paint must show the destination; loading timers are deliberately withheld.
    discard host.render(view)
    Swag.assert(not view.hasPendingTarget and view.retainedBlocks.isEmpty())
    var found: bool
    for block in view.blocks where block.sourceOffset == offset
    {
        found = true
        Swag.assert(block.kind == .Heading2)
        Swag.assert(Math.abs(view.scroll.scrollPosition().y - (block.wnd.position.y - view.documentStyle.topInset)) < 2)
    }

    Swag.assert(found)
    let position = view.scroll.scrollPosition()
    for 64 where view.isLoading() do
        host.fireTimers()
    Swag.assert(view.scroll.scrollPosition() == position)
    var style = view.documentStyle
    style.bodyFontSize = 24
    view.setDocumentStyle(style)
    let first = view.revealHeading(0)
    Swag.assert(first)
    for 256 where view.isLoading() do
        host.fireTimers()
    Swag.assert(view.scroll.scrollPosition().y < 2)
}

// A heading click owns its position, including during a wheel glide or reverse prefetch.
#test
{
    let fileName = Testing.tempFilePath("outline-heading-scroll-", ".md")
    defer discard catch File.delete(fileName)
    var source:  String
    var offsets: Array'u64
    for index in 4_000
    {
        offsets.add(source.length)
        source += Format.toString("## Section %\n\nA paragraph to retain while the document scrolls.\n\n", index)
    }

    for 20 do
        source += "A closing paragraph after the last heading.\n\n"
    discard expect File.writeAllBytes(fileName, cast(const [..] u8) source.toString())
    var host: Testing.HeadlessHost
    host.setup(720, 480)
    defer host.shutdown()
    let view = Markdown.View.createFile(&host.root, fileName)
    view.resize(720, 480)
    view.applyLayout()
    for 64 where view.isLoading() do
        host.fireTimers()

    for index in [2_000'u64, 2_002, 500, 502, 3_999, 0]
    {
        host.setReducedMotion(false)
        host.mouseWheel({360, 240}, -1)
        let revealed = view.revealHeading(offsets[index])
        Swag.assert(revealed)
        discard host.render(view)
        Swag.assert(not view.hasPendingTarget and not view.pendingSeek and not view.waitingScroll and view.retainedBlocks.isEmpty())
        var found: bool
        for block in view.blocks where block.sourceOffset == offsets[index]
        {
            found = true
            Swag.assert(block.wnd.isVisible())
            Swag.assert(Math.abs(block.wnd.surfaceRect().y - view.scroll.surfaceRect().y - view.documentStyle.topInset) <= 1)
        }

        Swag.assert(found)
        let position = view.scroll.scrollPosition()
        for 64 where view.isLoading() do
            host.fireTimers()
        host.finishAnimations()
        discard host.render(view)
        Swag.assert(view.scroll.scrollPosition() == position)

        // Crossing the new resident boundary must move by the wheel distance, without a jump
        // when the preceding blocks replace the viewport. Returning keeps the same heading.
        host.setReducedMotion(true)
        let direction = index ? 1 : -1
        for delta in [direction, -direction]
        {
            let before = view.scroll.scrollPosition().y
            host.mouseWheel({360, 240}, delta)
            for 2
            {
                discard host.render(view)
                host.finishAnimations()
            }

            Swag.assert(Math.abs(view.scroll.scrollPosition().y - before + delta * view.scroll.verticalScrollStep * 3) <= 1, Format.toString("section=% wheel=% before=% after=%", index, delta, before, view.scroll.scrollPosition().y).toString())
        }

        Swag.assert(view.scroll.scrollPosition() == position)
    }

    // The byte-to-height estimate is deliberately different from the true first-page geometry.
    // A reverse overlap must still expose byte zero, with no gap or stalled wheel above it.
    let away = view.revealHeading(offsets[2_000])
    Swag.assert(away)
    discard host.render(view)
    let nearStart = view.revealHeading(offsets[2])
    Swag.assert(nearStart)
    discard host.render(view)
    Swag.assert(view.blocks[0].sourceOffset == offsets[2])
    for 4
    {
        var before: f32
        for block in view.blocks where block.sourceOffset == offsets[2] do
            before = block.wnd.surfaceRect().y
        host.mouseWheel({360, 240}, 1)
        discard host.render(view)
        host.finishAnimations()
        for block in view.blocks where block.sourceOffset == offsets[2]
        {
            let distance = block.wnd.surfaceRect().y - before
            Swag.assert(distance >= -1 and distance <= view.scroll.verticalScrollStep * 3 + 1)
        }
    }

    Swag.assert(view.residentStart == 0 and view.virtualOrigin == 0 and view.scroll.scrollPosition().y == 0 and not view.waitingScroll)
    Swag.assert(view.blocks[0].sourceOffset == 0)
    Swag.assert(Math.abs(view.blocks[0].wnd.surfaceRect().y - view.scroll.surfaceRect().y - view.documentStyle.topInset) <= 1)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()
    let source = "<html><body><h1>Guide &amp; help</h1><pre>h2 is text</pre><h2 style='display:none'>Hidden</h2><h2 style='visibility:hidden'>Invisible</h2><div style='height:900px'></div><h3><em>Repeated</em></h3><h3>Repeated</h3><div style='height:900px'></div></body></html>"
    let view   = HtmlView.createText(&host.root, source)
    view.resize(640, 360)
    view.applyLayout()
    let headings = view.headings()
    Swag.assert(headings.count == 3)
    Swag.assert(headings[0].title == "Guide & help" and headings[0].level == 1)
    Swag.assert(headings[1].level == 3 and headings[1].title == "Repeated")
    let moved = view.revealFileOffset(headings[2].sourceOffset, "")
    Swag.assert(moved)
    let node = view.nodeAtSourceOffset(headings[2].sourceOffset)
    let box  = view.boxOfNode(node)
    Swag.assert(Math.abs(view.scroll.scrollPosition().y - (view.layout.constBox(box).rect.y - 24)) < 2)
    let before = view.scroll.scrollPosition().y
    view.setDocumentStyle({bodyFontSize: 24})
    let after = view.headings()
    Swag.assert(after.count == 3 and after[2].sourceOffset == headings[2].sourceOffset)
    Swag.assert(view.scroll.scrollPosition().y >= before)
}

// Named destinations and cycles are read independently of page rendering; cropping and rotation
// produce the same top-left page coordinates as the displayed content.
#test
{
    let path    = Path.combine(Path.directoryName(#curlocation.fileName)!, "datas/document-outline.pdf")
    var reader  = expect Pdf.Reader.open(path)
    let outline = reader.loadOutline()
    Swag.assert(outline.count == 4)
    Swag.assert(outline[0].title == "Chapter one" and outline[0].level == 1 and outline[0].pageIndex == 0)
    Swag.assert(outline[1].title == "Section é" and outline[1].level == 2 and outline[1].pageIndex == 1)
    Swag.assert(outline[1].position == Math.Point{24, 400})
    Swag.assert(outline[2].pageIndex == 2 and outline[2].position == Math.Point{980, 20})
    Swag.assert(outline[3].pageIndex == Swag.U64.Max)
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()
    let view = PdfView.create(&host.root)
    var page = expect reader.loadPage(0)
    view.exchangeDocument(&reader, &page)
    view.resize(640, 360)
    view.applyLayout()
    view.setZoom(1)
    view.showPosition(outline[1].pageIndex, outline[1].position)
    Swag.assert(view.pageIndex == 1)
    Swag.assert(Math.abs(view.scroll.scrollPosition().y - (view.pageRect(1).y + 400 - 12)) < 2)
    view.setPageLayout(.Single)
    view.showPosition(1, {24, 400})
    Swag.assert(view.pageIndex == 1 and view.scroll.scrollPosition().y >= 390)
}
