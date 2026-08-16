#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

private func htmlFixturePath()->String
{
    return Path.combine(Path.directoryName(#curlocation.fileName)!, "files/html/comprehensive.html")
}

#test
{
    let source = expect File.readAllText(htmlFixturePath())
    let rules  = parseHtmlCss(source)
    let body   = htmlBodyCssStyle(source, rules.toSlice())
    let blocks = parseHtmlBlocks(source, rules.toSlice())
    @assert(rules.count >= 6)
    @assert(body.background.a == 255 and body.maxWidth == 840)
    @assert(blocks.count >= 18)
    @assert(blocks[0].kind == .Heading1 and blocks[0].style.fontSize == 36)
    @assert(Utf8.contains(blocks.back().text.toString(), "marker"))
    var hasList, hasQuote, hasCode, hasTable, hasDetails, hasRule: bool
    for &block in blocks
    {
        switch block.kind
        {
        case .List:    hasList = true
        case .Quote:   hasQuote = true
        case .Code:    hasCode = true
        case .Table:   hasTable = true
        case .Details: hasDetails = true
        case .Rule:    hasRule = true
        }

        @assert(!Utf8.contains(block.text.toString(), "must not render"))
        @assert(!Utf8.contains(block.text.toString(), "hidden template text"))
    }

    @assert(hasList and hasQuote and hasCode and hasTable and hasDetails and hasRule)
}

// Documentation pages are read as documents: site navigation stays out of the block stream and
// Swag's generated code containers retain their code presentation.
#test
{
    var source: String = "<header><p>site title</p></header><aside><p>table of contents</p></aside>"
    source += "<main><div class=\"code-block\"><span>let answer = 42</span></div>"
    source += "<p>Visible documentation.</p></main><footer><p>site footer</p></footer>"
    var rules: Array'HtmlCssRule
    let blocks = parseHtmlBlocks(source.toString(), rules.toSlice())
    @assert(blocks.count == 2)
    @assert(blocks[0].kind == .Code)
    @assert(Utf8.contains(blocks[0].text.toString(), "let answer = 42"))
    @assert(blocks[1].kind == .Paragraph and blocks[1].text == "Visible documentation.")
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    let source = expect File.readAllText(htmlFixturePath())
    let view   = HtmlView.createText(&host.root, source.toString())
    view.resize(960, 680)
    view.applyLayout()
    view.layoutDocument()
    @assert(view.blocks.count >= 18)
    @assert(view.page.position.width == 840)
    @assert(view.page.backgroundStyle == view.backgroundStyle)
    Testing.assertContentFits(view)

    host.settleAnimations(view, 4)
    var image = host.render(view)
    Pixel.Testing.assertImageGolden(&image, "htmlview.document")
}

// Reveals a semantic block beyond the initial resident window of a multi-megabyte HTML document
// without parsing or retaining the whole file.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_large_html_%.html", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    let fixture       = expect File.readAllText(htmlFixturePath())
    let query         = "distant html verification marker"
    let fixtureOffset = Utf8.indexOf(fixture.toString(), query)
    @assert(fixtureOffset != Swag.U64.Max)
    var source: String = "<html><body>"
    for 28_000 do
        source += "<h2>Streamed section</h2><p>A paragraph remains outside the resident window.</p>"
    let offset = source.length + fixtureOffset
    source += fixture
    for 7_000 do
        source += "<p>A trailing paragraph keeps the document large.</p>"
    source += "</body></html>"
    @assert(source.length >= 2 * 1024 * 1024)
    discard expect File.writeAllBytes(fileName, @mkslice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    let view = HtmlView.createFile(&host.root, fileName)
    view.resize(960, 680)
    view.applyLayout()
    @assert(view.revealFileOffset(offset, query))

    var steps = 0'u32
    while !view.pendingSearch.isEmpty() and steps < 64
    {
        view.streamStep()
        steps += 1
    }

    @assert(view.pendingSearch.isEmpty())
    @assert(view.searchBlockIndex != Swag.U64.Max)
    @assert(view.bytesRead < view.fileSize)
    @assert(view.scroll.scrollableClientRect().height > view.scroll.paddedClientRect().height)
}

// A multi-megabyte streamed HTML document follows the complete focused keyboard navigation
// contract while retaining only the bounded source window needed around either boundary.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("sfilescope_html_stream_%.html", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var paragraph: String
    for 12 do
        paragraph += "A long paragraph stays on disk until the viewport approaches its rendered lines. "
    var source: String = "<main>"
    for 3_000
    {
        source += "<h2>Streamed heading</h2><p>"
        source += paragraph
        source += "</p>"
    }

    source += "</main>"
    @assert(source.length >= 2 * 1024 * 1024)
    discard expect File.writeAllBytes(fileName, @mkslice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()
    let view = HtmlView.createFile(&host.root, fileName)
    view.resize(960, 680)
    view.applyLayout()
    view.layoutDocument()
    view.streamStep()

    @assert(!view.blocks.isEmpty())
    @assert(view.stream.isOpen())
    @assert(expect view.stream.position() < source.length)
    @assert(view.scroll.scrollableClientRect().height > view.contentHeight)

    view.setInitialFocus(view)
    @assert(view.hasFocus())
    let lineStep = view.scroll.verticalScrollStep
    host.keyPress(Input.Key.Down)
    var navigationSteps = 0'u32
    while view.hasPendingY and navigationSteps < 64
    {
        host.fireTimers()
        navigationSteps += 1
    }

    @assert(!view.hasPendingY)
    @assert(Math.abs(view.scroll.scrollPosition().y - lineStep) <= 1)
    host.keyPress(Input.Key.Up)
    @assert(view.scroll.scrollPosition().y == 0)
    host.keyPress(Input.Key.PageDown)
    navigationSteps = 0
    while view.hasPendingY and navigationSteps < 64
    {
        host.fireTimers()
        navigationSteps += 1
    }

    @assert(!view.hasPendingY)
    let pagePosition = view.scroll.scrollPosition().y
    @assert(pagePosition > lineStep)
    host.keyPress(Input.Key.PageUp)
    @assert(view.scroll.scrollPosition().y == 0)

    view.scroll.setScrollPos(0, view.contentHeight)
    let oldPosition = view.scroll.scrollPosition()
    var block: HtmlBlock
    block.kind = .Paragraph
    block.text = "Another streamed paragraph."
    view.appendBlock(#move block)
    @assert(view.scroll.scrollPosition() == oldPosition)

    view.scroll.setScrollPos(0, 0)
    let beforeEnd = view.scroll.scrollPosition()
    host.keyPress(Input.Key.End)
    @assert(view.jumpToEnd)

    // End has one visible destination. The streamed seek must not first expose its estimated
    // position and then jump again after EOF is materialized.
    @assert(view.scroll.scrollPosition() == beforeEnd)
    var steps = 0'u32
    while view.isLoading() and steps < 4_000
    {
        view.streamStep()
        steps += 1
    }

    @assert(!view.isLoading())
    @assert(!view.jumpToEnd)
    @assert(view.scroll.scrollPosition().y > beforeEnd.y)
    host.keyPress(Input.Key.Home)
    @assert(view.residentStart == 0)
    @assert(view.scroll.scrollPosition().y == 0)
}

#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 240)
    defer host.shutdown()

    var source: String = "<main>"
    for 40 do
        source += "<p>A paragraph with enough content to occupy another line.</p>"
    source += "</main>"
    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(640, 240)
    view.applyLayout()
    view.layoutDocument()
    discard host.render(view)
    view.layoutDocument()
    @assert(view.focusPolicy == .Tab)
    @assert(view.scroll.scrollableClientRect().height > view.scroll.paddedClientRect().height)

    var end = KeyEvent{kind: .Pressed, key: .End}
    @assert(scrollDocumentWithKey(view.scroll, &end))
    @assert(view.scroll.scrollPosition().y > 0)
    var pageUp = KeyEvent{kind: .Pressed, key: .PageUp}
    let bottom = view.scroll.scrollPosition().y
    @assert(scrollDocumentWithKey(view.scroll, &pageUp))
    @assert(view.scroll.scrollPosition().y < bottom)
    var home = KeyEvent{kind: .Pressed, key: .Home}
    @assert(scrollDocumentWithKey(view.scroll, &home))
    @assert(view.scroll.scrollPosition().y == 0)
}
