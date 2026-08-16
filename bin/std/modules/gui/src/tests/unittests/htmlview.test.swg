#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

private func htmlFixturePath()->String
{
    return Path.combine(Path.directoryName(#curlocation.fileName)!, "files/html/comprehensive.html")
}

private func parseDocument(source: string)->HtmlDocument
{
    var result = HtmlDocument.create()
    var parser: HtmlParser
    parser.start(&result)
    parser.feed(source)
    parser.finish()
    return result
}

// Returns the first element of a document carrying a tag, so a test can name what it inspects.
private func findTag(document: const *HtmlDocument, tag: HtmlTag)->u32
{
    for index in document.nodes.count where document.constNode(cast(u32) index).tag == tag do
        return cast(u32) index
    return HtmlNoNode
}

// The tree builder closes what a document leaves open and never lets a hidden element reach the
// visible tree.
#test
{
    let document = parseDocument("<html><body><p>First<p>Second<ul><li>a<li>b</ul><div class=\"x y\" id=\"z\">t</div></body></html>")

    let body = findTag(&document, .Body)
    @assert(body != HtmlNoNode)

    var paragraphs = 0'u32
    var items      = 0'u32
    for index in document.nodes.count
    {
        let node = document.constNode(cast(u32) index)
        if node.tag == .P do
            paragraphs += 1
        if node.tag == .Li do
            items += 1
    }

    // An unclosed paragraph ends where the next one begins instead of nesting inside it.
    @assert(paragraphs == 2 and items == 2)
    let first = findTag(&document, .P)
    @assert(document.constNode(first).parent == body)

    let division = findTag(&document, .Div)
    @assert(document.hasClass(division, "x") and document.hasClass(division, "y"))
    @assert(!document.hasClass(division, "z"))
    @assert(document.constNode(division).id == "z")
    @assert(document.attribute(division, "class") == "x y")
}

// Character references decode to their code points, including the numeric forms.
#test
{
    @assert(htmlDecodeText("a&amp;b").toString() == "a&b")
    @assert(htmlDecodeText("&lt;tag&gt;").toString() == "<tag>")
    @assert(htmlDecodeText("&#65;&#x42;").toString() == "AB")
    @assert(htmlDecodeText("caf&eacute;").toString() == "café")
    @assert(htmlDecodeText("&nosuchentity;").toString() == "&nosuchentity;")
    @assert(htmlDecodeText("a & b").toString() == "a & b")
}

// A raw-text element never contributes markup, whatever it contains.
#test
{
    let document = parseDocument("<style>p { color: red }</style><script>if (a<b) {}</script><p>after</p>")
    @assert(findTag(&document, .P) != HtmlNoNode)

    let style = findTag(&document, .Style)
    @assert(style != HtmlNoNode)
    @assert(Utf8.contains(document.constNode(document.constNode(style).children[0]).text.toString(), "color: red"))

    // A script body is text, so its `<` never opened an element.
    @assert(findTag(&document, .B) == HtmlNoNode)
}

// Reading a document in chunks produces the tree the whole source produces.
#test
{
    let source = expect File.readAllText(htmlFixturePath())
    let whole  = parseDocument(source.toString())

    var streamed = HtmlDocument.create()
    var parser: HtmlParser
    parser.start(&streamed)

    var offset = 0'u64
    while offset < source.length
    {
        let end = Math.min(offset + 7, source.length)
        parser.feed(source.toString()[offset until end])
        offset = end
    }

    parser.finish()
    @assert(streamed.nodes.count == whole.nodes.count)
    @assert(streamed.textContent(0) == whole.textContent(0))
}

// The cascade orders declarations by importance, then specificity, then source order, and
// resolves the custom properties a document defines.
#test
{
    var source: String = "<style>"
    source += ":root { --ink: #102030; --size: 20px }"
    source += "p { color: #ff0000; font-size: 10px }"
    source += ".note { color: var(--ink); font-size: var(--size) }"
    source += "#one { color: #00ff00 }"
    source += "p { color: #0000ff !important }"
    source += "div em { font-style: normal }"
    source += "</style>"
    source += "<p class=\"note\" id=\"one\">text</p><div><em>inner</em></div>"

    var host: Testing.HeadlessHost
    host.setup(800, 600)
    defer host.shutdown()

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(800, 600)
    view.applyLayout()
    view.rebuild()

    let paragraph = findTag(&view.document, .P)
    let style     = view.layout.styleOfNode(paragraph)

    // The important declaration wins over the identifier, and the custom property is expanded.
    @assert(style.color == Color.fromArgb(0xFF0000FF))
    @assert(style.fontSize == 20)

    let emphasis = findTag(&view.document, .Em)
    @assert(!view.layout.styleOfNode(emphasis).italic)
}

// Lengths read every unit a document uses, and math expressions keep what layout must resolve.
#test
{
    var pool:    HtmlValuePool
    var context: HtmlLengthContext
    context.fontSize       = 20
    context.rootFontSize   = 16
    context.viewportWidth  = 1000
    context.viewportHeight = 500
    context.basis          = 400
    context.hasBasis       = true

    @assert(htmlParseLength(&pool, "12px", context).length.resolve(&pool, context) == 12)
    @assert(htmlParseLength(&pool, "2em", context).length.resolve(&pool, context) == 40)
    @assert(htmlParseLength(&pool, "2rem", context).length.resolve(&pool, context) == 32)
    @assert(htmlParseLength(&pool, "50%", context).length.resolve(&pool, context) == 200)
    @assert(htmlParseLength(&pool, "10vw", context).length.resolve(&pool, context) == 100)
    @assert(htmlParseLength(&pool, "calc(100% - 44px)", context).length.resolve(&pool, context) == 356)
    @assert(htmlParseLength(&pool, "min(1560px, calc(100% - 44px))", context).length.resolve(&pool, context) == 356)
    @assert(htmlParseLength(&pool, "clamp(10px, 50%, 80px)", context).length.resolve(&pool, context) == 80)
    @assert(htmlParseLength(&pool, "auto", context).length.isAuto())
}

// Every color notation a document uses reads back as the same paint.
#test
{
    @assert(htmlParseColor("#f00").color == Color.fromArgb(0xFFFF0000))
    @assert(htmlParseColor("#00ff00").color == Color.fromArgb(0xFF00FF00))
    @assert(htmlParseColor("#0000ff80").color == Color.fromArgb(0x800000FF))
    @assert(htmlParseColor("rgb(255, 0, 0)").color == Color.fromArgb(0xFFFF0000))
    @assert(htmlParseColor("rgba(255 0 0 / 50%)").color.a == 128)
    @assert(htmlParseColor("hsl(0, 100%, 50%)").color == Color.fromArgb(0xFFFF0000))
    @assert(htmlParseColor("rebeccapurple").color == Color.fromArgb(0xFF663399))
    @assert(htmlParseColor("transparent").matched and !htmlParseColor("transparent").color.a)
    @assert(!htmlParseColor("inherit").matched)
}

// Blocks stack with collapsed margins, and a grid places its children over its declared tracks.
#test
{
    var source: String = "<style>"
    source += "body { margin: 0 }"
    source += ".stack > div { margin: 20px 0; height: 30px }"
    source += ".grid { display: grid; grid-template-columns: 100px minmax(0, 1fr); gap: 10px }"
    source += ".cell { height: 40px }"
    source += "</style>"
    source += "<div class=\"stack\"><div id=\"a\"></div><div id=\"b\"></div></div>"
    source += "<div class=\"grid\"><div class=\"cell\" id=\"c\"></div><div class=\"cell\" id=\"d\"></div></div>"

    var host: Testing.HeadlessHost
    host.setup(610, 600)
    defer host.shutdown()

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(610, 600)
    view.applyLayout()
    view.rebuild()

    let first  = view.layout.constBox(view.boxOfNode(view.elementById("a")))
    let second = view.layout.constBox(view.boxOfNode(view.elementById("b")))

    // Adjacent margins of 20px collapse into one gap of 20px, not two.
    @assert(second.rect.y - first.rect.bottom() == 20)

    let left  = view.layout.constBox(view.boxOfNode(view.elementById("c")))
    let right = view.layout.constBox(view.boxOfNode(view.elementById("d")))
    @assert(left.rect.width == 100)
    @assert(right.rect.x - left.rect.right() == 10)
    @assert(right.rect.width == view.scroll.paddedClientRect().width - 110)
}

// A flex row shares what is left over between the items that grow.
#test
{
    var source: String = "<style>body { margin: 0 }"
    source += ".row { display: flex; gap: 20px }"
    source += ".fixed { flex: none; width: 100px; height: 10px }"
    source += ".grow { flex: 1; height: 10px }"
    source += "</style>"
    source += "<div class=\"row\"><div class=\"fixed\" id=\"a\"></div><div class=\"grow\" id=\"b\"></div></div>"

    var host: Testing.HeadlessHost
    host.setup(520, 400)
    defer host.shutdown()

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(520, 400)
    view.applyLayout()
    view.rebuild()

    let fixed = view.layout.constBox(view.boxOfNode(view.elementById("a")))
    let grow  = view.layout.constBox(view.boxOfNode(view.elementById("b")))
    let width = view.scroll.paddedClientRect().width
    @assert(fixed.rect.width == 100)
    @assert(grow.rect.x == 120)
    @assert(Math.abs(grow.rect.width - (width - 120)) <= 0.5)
}

// Text wraps into as many lines as the measure allows, and a forced break starts a new one.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 400)
    defer host.shutdown()

    var source: String = "<style>body { margin: 0; font-size: 16px }</style><p id=\"p\">"
    for 40 do
        source += "word "
    source += "</p><p id=\"q\">one<br>two</p>"

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(400, 400)
    view.applyLayout()
    view.rebuild()

    let wrapped = view.layout.constBox(view.boxOfNode(view.elementById("p")))
    @assert(wrapped.lines.count > 3)
    for line in wrapped.lines where line.width > wrapped.content.width + 1 do
        @assert(false)

    let broken = view.layout.constBox(view.boxOfNode(view.elementById("q")))
    @assert(broken.lines.count == 2)
}

// A block stays inside the measure its ancestors set, however deep it sits.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 400)
    defer host.shutdown()

    var source: String = "<style>body { max-width: 840px } pre { background: #101010 }</style>"
    source += "<body><main><article><pre id=\"code\">one line of preformatted text</pre></article></main></body>"

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(960, 400)
    view.applyLayout()
    view.rebuild()

    let block = view.layout.constBox(view.boxOfNode(view.elementById("code")))
    @assert(block.rect.x == 8)
    @assert(block.rect.width == 840)
}

// A table sizes its columns from what their cells need.
#test
{
    var host: Testing.HeadlessHost
    host.setup(600, 400)
    defer host.shutdown()

    var source: String = "<style>body { margin: 0 } td { padding: 4px }</style>"
    source += "<table><tr><td id=\"a\">short</td><td id=\"b\">a considerably longer cell of text</td></tr>"
    source += "<tr><td>x</td><td>y</td></tr></table>"

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(600, 400)
    view.applyLayout()
    view.rebuild()

    let narrow = view.layout.constBox(view.boxOfNode(view.elementById("a")))
    let wide   = view.layout.constBox(view.boxOfNode(view.elementById("b")))
    @assert(wide.rect.width > narrow.rect.width)
    @assert(wide.rect.x == narrow.rect.right())
}

// A bounded overflow region moves its own contents and never paints them outside its viewport.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 180)
    defer host.shutdown()

    var source: String = "<style>"
    source += "body { margin: 0; background: #ffffff }"
    source += "#rail { width: 100px; height: 80px; overflow-y: auto; background: #00ff00 }"
    source += ".page { height: 80px } #first { background: #ff0000 } #second { background: #0000ff }"
    source += "</style>"
    source += "<div style=\"height: 40px\"></div>"
    source += "<aside id=\"rail\"><div class=\"page\" id=\"first\"></div><div class=\"page\" id=\"second\"></div></aside>"

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(240, 180)
    view.applyLayout()
    view.rebuild()
    discard host.render(view)

    let rail = view.boxOfNode(view.elementById("rail"))
    @assert(rail != HtmlNoNode and view.layout.constBox(rail).scrollable)
    @assert(view.layout.constBox(rail).rect.y == 40)
    @assert(view.painter().scrollableAt({20, 60}) == rail)
    @assert(view.scrollRegion(rail, 80))
    @assert(view.layout.constBox(rail).scrollTop == 80)

    var image = host.render(view)
    @assert(image.pixelColor(20, 60).argb == 0xFF0000FF)
    @assert(image.pixelColor(20, 30).argb != 0xFFFF0000 and image.pixelColor(20, 30).argb != 0xFF0000FF)
    @assert(image.pixelColor(20, 130).argb != 0xFFFF0000 and image.pixelColor(20, 130).argb != 0xFF0000FF)
}

// A positive z-index keeps a sticky header above siblings that occur later in the document.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 180)
    defer host.shutdown()

    var source: String = "<style>"
    source += "body { margin: 0 }"
    source += "header { position: sticky; z-index: 20; top: 0; height: 40px; background: #ff0000 }"
    source += "main { height: 400px; background: #0000ff }"
    source += "</style><header></header><main></main>"

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(240, 180)
    view.applyLayout()
    view.rebuild()
    view.scroll.setScrollPos(0, 80)

    var image = host.render(view)
    @assert(image.pixelColor(120, 20).argb == 0xFFFF0000)
    @assert(image.pixelColor(120, 80).argb == 0xFF0000FF)
    @assert(view.document.constNode(view.painter().nodeAt({120, 20})).tag == .Header)
}

// The complete fixture renders, and nothing a document hides reaches the drawn text.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let view = HtmlView.createText(&host.root, (expect File.readAllText(htmlFixturePath())).toString())
    view.resize(960, 680)
    view.applyLayout()
    view.rebuild()

    let text = view.document.textContent(0)
    @assert(Utf8.contains(text.toString(), "Heading level one"))
    @assert(Utf8.contains(text.toString(), "The distant html verification marker"))
    @assert(!Utf8.contains(text.toString(), "must not render"))

    // A hidden container is parsed and then left out of the box tree entirely.
    for index in view.layout.boxes.count
    {
        let node = view.layout.constBox(cast(u32) index).node
        if node == HtmlNoNode do
            continue
        @assert(view.document.constNode(node).tag != .Script)
        @assert(view.document.constNode(node).tag != .Template)
    }

    @assert(view.layout.documentHeight > 680)

    host.settleAnimations(view, 4)
    var image = host.render(view)
    Pixel.Testing.assertImageGolden(&image, "htmlview.document")
}

// A search over a streamed document lands on the box that draws the match, wherever it is in the
// file and however much of it has been read.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("gui_html_stream_%.html", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    let fixture       = expect File.readAllText(htmlFixturePath())
    let query         = "distant html verification marker"
    let fixtureOffset = Utf8.indexOf(fixture.toString(), query)
    @assert(fixtureOffset != Swag.U64.Max)

    var source: String = "<html><body>"
    for 24_000 do
        source += "<h2>Streamed section</h2><p>A paragraph stays outside the resident window.</p>"
    let offset = source.length + fixtureOffset
    source += fixture
    for 5_000 do
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
    while view.isLoading() and steps < 4_000
    {
        view.streamStep()
        steps += 1
    }

    @assert(!view.isLoading())
    @assert(view.pendingSearch.isEmpty())
    @assert(view.searchNode != HtmlNoNode)
    @assert(Utf8.contains(view.document.constNode(view.searchNode).text.toString(), query))

    // The match is what the viewport shows, not an estimate of where it might be.
    let box = view.boxOfNode(view.searchNode)
    @assert(box != HtmlNoNode)
    let top      = view.layout.constBox(box).rect.y
    let position = view.scroll.scrollPosition().y
    @assert(top >= position and top <= position + view.scroll.paddedClientRect().height)
}

// What a scroll position shows does not depend on how the reader got there.
//
// This is the contract the previous viewer could not keep: it held a moving window of source
// bytes and re-parsed it from a guessed offset, so travelling with the scrollbar rewrote the text
// and sometimes emptied the page. A laid-out document is scrolled, not re-read.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("gui_html_scroll_%.html", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source: String = "<html><body><style>p { margin: 6px 0 } h2 { color: #2266cc }</style>"
    for index in 4_000
    {
        source += Format.toString("<h2>Section %</h2><p>Paragraph % carries enough words to occupy more than one line of the viewport.</p>", index, index)
    }

    source += "</body></html>"
    discard expect File.writeAllBytes(fileName, @mkslice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(720, 480)
    defer host.shutdown()

    let view = HtmlView.createFile(&host.root, fileName)
    view.resize(720, 480)
    view.applyLayout()

    var steps = 0'u32
    while view.isLoading() and steps < 4_000
    {
        view.streamStep()
        steps += 1
    }

    @assert(!view.isLoading())

    // Three positions, visited downwards and then upwards; every one must draw the same pixels
    // both times, and none of them may be blank.
    let stops             = [400.0'f32, 5_000.0'f32, 20_000.0'f32]
    var downward: [3] u32 = undefined
    for index in @countof(stops)
    {
        view.scroll.setScrollPos(0, stops[index])
        var image = host.render(view)
        downward[index] = Hash.hashBytes32(image.pixels.toSlice())
    }

    for index in @countof(stops)
    {
        let reverse = @countof(stops) - index - 1
        view.scroll.setScrollPos(0, stops[reverse])
        var image = host.render(view)
        @assert(Hash.hashBytes32(image.pixels.toSlice()) == downward[reverse])
    }

    @assert(downward[0] != downward[1] and downward[1] != downward[2])
}

// The focused document answers the whole keyboard scrolling contract.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 240)
    defer host.shutdown()

    var source: String = "<main>"
    for 60 do
        source += "<p>A paragraph with enough content to occupy another line.</p>"
    source += "</main>"

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(640, 240)
    view.applyLayout()
    view.rebuild()
    discard host.render(view)

    @assert(view.focusPolicy == .Tab)
    @assert(view.scroll.scrollableClientRect().height > view.scroll.paddedClientRect().height)

    var end = KeyEvent{kind: .Pressed, key: .End}
    @assert(scrollDocumentWithKey(view.scroll, &end))
    let bottom = view.scroll.scrollPosition().y
    @assert(bottom > 0)

    var pageUp = KeyEvent{kind: .Pressed, key: .PageUp}
    @assert(scrollDocumentWithKey(view.scroll, &pageUp))
    @assert(view.scroll.scrollPosition().y < bottom)

    var home = KeyEvent{kind: .Pressed, key: .Home}
    @assert(scrollDocumentWithKey(view.scroll, &home))
    @assert(view.scroll.scrollPosition().y == 0)
}
