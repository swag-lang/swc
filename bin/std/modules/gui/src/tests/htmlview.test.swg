#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Pixel

func guiFixturePath(name: string)->String
{
    return Path.combine(Path.directoryName(#curlocation.fileName)!, Format.toString("datas/%", name).toString())
}

func htmlFixturePath()->String
{
    return guiFixturePath("html.comprehensive.html")
}

func parseDocument(source: string)->HtmlDocument
{
    var result = HtmlDocument.create()
    var parser: HtmlParser
    parser.start(&result)
    parser.feed(source)
    parser.finish()
    return result
}

// Returns the first element of a document carrying a tag, so a test can name what it inspects.
func findTag(document: const *HtmlDocument, tag: HtmlTag)->u32
{
    for index in document.nodes.count where document.constNode(cast(u32) index).tag == tag do
        return cast(u32) index
    return HtmlNoNode
}

// Returns the first element carrying a class used to name fixture structure.
func findClass(document: const *HtmlDocument, name: string)->u32
{
    for index in document.nodes.count where document.hasClass(cast(u32) index, name) do
        return cast(u32) index
    return HtmlNoNode
}

// Returns the position of the first laid-out text item matching `text` inside a box.
func findItemPos(view: *HtmlView, box: u32, text: string)->{ x: f32, y: f32, found: bool }
{
    var result: retval
    for item in view.layout.constBox(box).items
    {
        if item.kind != .Text or item.text.toString() != text do
            continue
        result.x     = item.x
        result.y     = item.y
        result.found = true
        return result
    }

    return result
}

// Returns the nth element carrying a tag, so a test can address repeated fixture structure.
func findNthTag(document: const *HtmlDocument, tag: HtmlTag, wanted: u32)->u32
{
    var seen = 0'u32
    for index in document.nodes.count where document.constNode(cast(u32) index).tag == tag
    {
        seen += 1
        if seen == wanted do
            return cast(u32) index
    }

    return HtmlNoNode
}

// Writes `bytes` to a temporary file, loads it whole through a view, and returns its text.
func loadTemporaryDocument(host: *Testing.HeadlessHost, bytes: const [..] u8, tag: string)->String
{
    let fileName = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("gui_html_charset_%_%.html", tag, Guid64.random()).toString())
    discard expect File.writeAllBytes(fileName, bytes)
    defer discard catch File.delete(fileName)

    let view = HtmlView.createFile(&host.root, fileName)
    view.resize(640, 480)
    view.applyLayout()

    var steps = 0'u32
    while view.isLoading() and steps < 100
    {
        view.streamStep()
        steps += 1
    }

    @assert(!view.isLoading())
    return view.document.textContent(0)
}

struct HtmlLinkHit
{
    point: Math.Point
    found: bool
}

// Finds a visible point inside a link after sticky and independently scrolled offsets apply.
func findVisibleLink(view: *HtmlView, url: string)->HtmlLinkHit
{
    let viewport = view.scroll.paddedClientRect()
    let painter  = view.painter()
    var result: retval
    var y        = 2.0'f32
    while y < viewport.height
    {
        var x = 2.0'f32
        while x < viewport.width
        {
            let point = Math.Point{x, y}
            if view.linkAt(painter.nodeAt(point)) == url
            {
                result.point = point
                result.found = true
                return result
            }

            x += 4
        }

        y += 4
    }

    return result
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

// Polygonal clip paths remain paintable decorations rather than being treated as unsupported
// masks, which is what gives documentation overview cards their cut corners and visible fill.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 80)
    defer host.shutdown()

    let view = HtmlView.createText(&host.root, "<style>.cut{width:80px;height:50px;background:#f00;clip-path:polygon(0 0,calc(100% - 12px) 0,100% 12px,100% 100%,12px 100%,0 calc(100% - 12px))}</style><div class='cut'></div>")
    view.resize(120, 80)
    view.applyLayout()
    view.rebuild()

    let node  = findClass(&view.document, "cut")
    let style = view.layout.constStyle(view.layout.constBox(view.boxOfNode(node)).style)
    @assert(style.clipPath != HtmlNoNode)
    @assert(!style.masked)

    var image = host.render(view)
    @assert(image.isValid())
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
    let translucent = htmlParseColor("color-mix(in srgb, #ff0000 25%, transparent)")
    @assert(translucent.matched and translucent.color.a == 64 and translucent.color.r == 255 and !translucent.color.g and !translucent.color.b)
    @assert(htmlParseColor("color-mix(in srgb, #0000ff 20%, #ffffff)").color == Color.fromArgb(0xFFCCCCFF))
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

// A terminal preserved newline ends the last line without creating another blank line.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 160)
    defer host.shutdown()

    let view = HtmlView.createText(&host.root, "<style>body{margin:0}#code{white-space:pre}</style><div id='code'><span>first\nsecond\n</span></div>")
    view.resize(400, 160)
    view.applyLayout()
    view.rebuild()

    let code = view.layout.constBox(view.boxOfNode(view.elementById("code")))
    @assert(code.lines.count == 2)
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

// A table cell aligns its contents inside the row height established by a taller sibling.
#test
{
    var host: Testing.HeadlessHost
    host.setup(300, 140)
    defer host.shutdown()

    var source: String = "<style>body { margin: 0 } td { padding: 4px } #bottom { vertical-align: bottom }</style>"
    source += "<table><tr><td><div style=\"height:80px\"></div></td><td id=\"bottom\">Bottom</td></tr></table>"

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(300, 140)
    view.applyLayout()
    view.rebuild()

    let cell = view.layout.constBox(view.boxOfNode(view.elementById("bottom")))
    @assert(!cell.children.isEmpty())
    let content = view.layout.constBox(cell.children[0])
    @assert(!content.items.isEmpty())
    @assert(content.items[0].y + content.items[0].ascent + content.items[0].descent >= cell.content.bottom() - 1)
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
    @assert(image.pixelColor(97, 90).argb == host.theme.colors.scrollBar_Box.argb)
    @assert(image.pixelColor(20, 30).argb != 0xFFFF0000 and image.pixelColor(20, 30).argb != 0xFF0000FF)
    @assert(image.pixelColor(20, 130).argb != 0xFFFF0000 and image.pixelColor(20, 130).argb != 0xFF0000FF)
}

// A tall inline image remains paintable after its typographic origin has left the viewport.
#test
{
    var host: Testing.HeadlessHost
    host.setup(120, 80)
    defer host.shutdown()

    let source = "<style>body{margin:0;background:#fff}p{margin:0}img{width:80px;height:160px;background:#f00}</style><p id='short'><img id='picture' src='missing.png'></p>"
    let view   = HtmlView.createText(&host.root, source)
    view.resize(120, 80)
    view.applyLayout()
    view.rebuild()
    view.scroll.setScrollPos(0, 40)

    let parent  = view.layout.constBox(view.boxOfNode(view.elementById("short")))
    let picture = view.layout.constBox(view.boxOfNode(view.elementById("picture")))
    @assert(picture.rect.y < view.scroll.scrollPosition().y)
    @assert(parent.paintBounds.bottom() == picture.rect.bottom())
    @assert(view.layout.documentHeight == picture.rect.bottom())
    var image = host.render(view)
    @assert(image.pixelColor(20, 20).argb == 0xFFFF0000)
}

// A CSS region scrollbar pages through its track and drags its thumb like a native vertical bar.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 180)
    defer host.shutdown()

    let source = "<style>body{margin:0}#rail{width:100px;height:100px;overflow-y:auto}.page{height:100px}</style><aside id='rail'><div class='page'></div><div class='page'></div><div class='page'></div></aside>"
    let view   = HtmlView.createText(&host.root, source)
    view.resize(240, 180)
    view.applyLayout()
    view.rebuild()
    discard host.render(view)

    let rail = view.boxOfNode(view.elementById("rail"))
    @assert(rail != HtmlNoNode)
    let bar = view.painter().scrollBarAt({96, 75})
    @assert(bar.box == rail and bar.track.contains(Math.Point{96, 75}))

    host.click({96, 75})
    @assert(view.layout.constBox(rail).scrollTop == 100)

    let moved = view.painter().scrollBarAt({96, 50})
    @assert(moved.box == rail and moved.thumb.y <= 50 and moved.thumb.bottom() >= 50)
    host.mouseDown({91, 50})
    host.moveMouse({91, 95})
    host.mouseUp({91, 95})
    @assert(view.layout.constBox(rail).scrollTop > 190)
}

// A viewport-relative rail has a definite height even though its document parent grows with its
// content. This is the two-pane shape used by generated module pages: the outer view owns the
// page scrollbar while the rail consumes the wheel independently.
#test
{
    var host: Testing.HeadlessHost
    host.setup(240, 180)
    defer host.shutdown()

    var source: String = "<style>"
    source += ":root { --header-height: 40px } body { margin: 0 }"
    source += "aside { height: calc(100vh - var(--header-height)); overflow-y: auto }"
    source += ".page { height: 140px }"
    source += "</style><div style=\"height:40px\"></div><aside id=\"rail\"><div class=\"page\"></div><div class=\"page\"></div></aside>"

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(240, 180)
    view.applyLayout()
    view.rebuild()
    discard host.render(view)

    let rail = view.boxOfNode(view.elementById("rail"))
    @assert(rail != HtmlNoNode)
    @assert(Math.abs(view.layout.constBox(rail).content.height - (view.layout.viewport.y - 40)) <= 1)
    @assert(view.layout.constBox(rail).scrollable)
    @assert(view.painter().scrollableAt({20, 80}) == rail)
    @assert(view.scrollRegion(rail, 70))
    @assert(view.layout.constBox(rail).scrollTop == 70)
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
    @assert(view.searchEnd - view.searchStart == @countof(query))

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

    // A pointer gesture on prose restores the document after another control temporarily owned
    // the keyboard, so later navigation keys cannot disappear into stale focus.
    host.focus(&host.root)
    @assert(!view.hasFocus())
    host.click({20, 20})
    @assert(view.hasFocus())
}

// An absolutely positioned generated rule is a box of its own, and a functional color paints it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 80)
    defer host.shutdown()

    var source: String = "<style>body { margin: 0; background: #ffffff }"
    source += "h2 { position: relative; margin: 0; padding-top: 14px }"
    source += "h2::before { content: ''; position: absolute; top: 0; left: 0; width: 32px; height: 4px; background: color-mix(in srgb, #ff0000 50%, #ffffff) }"
    source += "</style><h2 id='section'>Section</h2>"

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(160, 80)
    view.applyLayout()
    view.rebuild()

    let heading = view.layout.constBox(view.boxOfNode(view.elementById("section")))
    var bar     = HtmlNoNode
    for child in heading.children where view.layout.constStyle(view.layout.constBox(child).style).background.a do
        bar = child
    @assert(bar != HtmlNoNode)
    let decoration = view.layout.constBox(bar)
    @assert(decoration.rect.width == 32 and decoration.rect.height == 4)
    @assert(decoration.rect.x == heading.rect.x and decoration.rect.y == heading.rect.y)
    @assert(heading.content.y == decoration.rect.y + 14)
    var textBox = HtmlNoNode
    for child in heading.children where view.layout.constBox(child).items.count do
        textBox = child
    @assert(textBox != HtmlNoNode and view.layout.constBox(textBox).lines.front().top == heading.content.y)
    var image = host.render(view)
    @assert(image.pixelColor(cast(u32) decoration.rect.horzCenter(), cast(u32) decoration.rect.vertCenter()).argb == 0xFFFF8080)
}

// Every checked-in HTML fixture is a complete document that the streaming parser accepts.
#test
{
    const Names = ["html.comprehensive.html",
                   "html.flex-grid.html",
                   "html.frames.html",
                   "html.local-target.html",
                   "html.streaming-fragments.html",
                   "html.tables.html"]

    for name in Names
    {
        let source   = expect File.readAllText(guiFixturePath(name))
        let document = parseDocument(source.toString())
        @assert(document.nodes.count > 4)
        @assert(findTag(&document, .Body) != HtmlNoNode)
    }
}

// A flexible documentation header keeps all navigation links on its single browser-sized row.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 540)
    defer host.shutdown()

    let view = HtmlView.createFile(&host.root, guiFixturePath("html.flex-grid.html"))
    view.resize(960, 540)
    view.applyLayout()
    view.rebuild()

    let header = view.layout.constBox(view.boxOfNode(view.elementById("flex-header")))
    let brand  = view.layout.constBox(view.boxOfNode(findClass(&view.document, "brand")))
    let links  = view.layout.constBox(view.boxOfNode(view.elementById("header-links")))
    let github = view.layout.constBox(view.boxOfNode(view.elementById("github-link")))
    @assert(header.rect.height == 66)
    @assert(Math.abs(brand.rect.vertCenter() - header.rect.vertCenter()) <= 1)
    @assert(!links.children.isEmpty())
    @assert(Math.abs(github.rect.y - view.layout.constBox(links.children[0]).rect.y) <= 1)
}

// The left frame owns wheel input under the pointer at every page position, including when its
// own scrollbar is already at an edge. The document owns wheel input only over the right frame.
#test
{
    var host: Testing.HeadlessHost
    host.setup(720, 360)
    defer host.shutdown()

    let view = HtmlView.createFile(&host.root, guiFixturePath("html.frames.html"))
    view.resize(720, 360)
    view.applyLayout()
    view.rebuild()
    discard host.render(view)

    var rail = view.boxOfNode(view.elementById("frame-rail"))
    @assert(rail != HtmlNoNode and view.layout.constBox(rail).scrollable)
    view.scroll.setScrollPos(0, 520)
    let pageStart = view.scroll.scrollPosition().y

    host.mouseWheel({60, 100}, -1)
    @assert(view.layout.constBox(rail).scrollTop > 0)
    @assert(view.scroll.scrollPosition().y == pageStart)

    discard view.scrollRegion(rail, 100_000)
    let railEnd = view.layout.constBox(rail).scrollTop
    host.mouseWheel({60, 100}, -1)
    @assert(view.layout.constBox(rail).scrollTop == railEnd)
    @assert(view.scroll.scrollPosition().y == pageStart)

    host.mouseWheel({420, 180}, -1)
    @assert(view.scroll.scrollPosition().y > pageStart)
    @assert(view.layout.constBox(rail).scrollTop == railEnd)
}

// Clicking a fragment in the independently scrolled rail positions its target after the CSS
// scroll margin instead of hiding it under the sticky header.
#test
{
    var host: Testing.HeadlessHost
    host.setup(720, 360)
    defer host.shutdown()

    let view = HtmlView.createFile(&host.root, guiFixturePath("html.frames.html"))
    view.resize(720, 360)
    view.applyLayout()
    view.rebuild()
    view.scroll.setScrollPos(0, 500)
    discard host.render(view)

    let hit = findVisibleLink(view, "#frame-target-two")
    @assert(hit.found)
    host.click(hit.point)

    let target = view.layout.constBox(view.boxOfNode(view.elementById("frame-target-two")))
    @assert(Math.abs(target.rect.y - view.scroll.scrollPosition().y - 60) <= 1)
}

// A relative local link replaces the displayed file and follows its fragment in the new page.
#test
{
    var host: Testing.HeadlessHost
    host.setup(720, 360)
    defer host.shutdown()

    let view = HtmlView.createFile(&host.root, guiFixturePath("html.frames.html"))
    view.resize(720, 360)
    view.applyLayout()
    view.rebuild()

    let rail = view.boxOfNode(view.elementById("frame-rail"))
    discard view.scrollRegion(rail, 100_000)
    discard host.render(view)
    let hit = findVisibleLink(view, "html.local-target.html#local-target")
    @assert(hit.found)
    host.click(hit.point)

    @assert(Path.fileName(view.fileName) == "html.local-target.html")
    let target = view.layout.constBox(view.boxOfNode(view.elementById("local-target")))
    @assert(Math.abs(target.rect.y - view.scroll.scrollPosition().y - 68) <= 1)
}

// The generated Pixel API page stays progressive, preserves its independently scrolled rail
// across partial rebuilds, resolves a fragment from the next chunk, and keeps the browser's
// one-line header. The test deliberately stops after that second 48 KiB chunk: exercising a
// progressive frame must not turn every GUI configuration into a full megabyte-layout benchmark.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 540)
    defer host.shutdown()

    let path = guiFixturePath("std.pixel.html")
    @assert((expect File.info(path)).size > 1024 * 1024)
    let view = HtmlView.createFile(&host.root, path)
    view.resize(960, 540)
    view.applyLayout()
    view.rebuild()
    @assert(view.isLoading())

    let railNode = findClass(&view.document, "left")
    @assert(railNode != HtmlNoNode)
    var rail = view.boxOfNode(railNode)
    @assert(rail != HtmlNoNode and view.layout.constBox(rail).scrollable)
    @assert(view.elementById("api-reference") == HtmlNoNode)
    @assert(view.navigateToFragment("#api-reference"))
    @assert(view.scrollRegion(rail, 180))

    view.streamStep()
    @assert(view.isLoading())
    rail = view.boxOfNode(findClass(&view.document, "left"))
    @assert(rail != HtmlNoNode and view.layout.constBox(rail).scrollTop == 180)
    @assert(view.elementById("api-reference") != HtmlNoNode)

    let target = view.layout.constBox(view.boxOfNode(view.elementById("api-reference")))
    @assert(Math.abs(target.rect.y - view.scroll.scrollPosition().y - 82) <= 1)

    let headerNode = findClass(&view.document, "site-header")
    let linksNode  = findClass(&view.document, "site-links")
    let header     = view.layout.constBox(view.boxOfNode(headerNode))
    let links      = view.layout.constBox(view.boxOfNode(linksNode))
    @assert(header.rect.height <= 68)
    @assert(!links.children.isEmpty())
    let firstY = view.layout.constBox(links.children[0]).rect.y
    for child in links.children do
        @assert(Math.abs(view.layout.constBox(child).rect.y - firstY) <= 1)

    view.stopLoading()
}

// Pins the generated API page in the browser reference's light palette and wide viewport: the
// overview cut, typography, section ornaments, note fills, and table alignment all pass through
// the production HTML view.
#test
{
    var host: Testing.HeadlessHost
    host.setup(1660, 1324)
    defer host.shutdown()

    host.theme.setSwagLight()
    host.app.notifyThemeChanged()
    host.notify(.ThemeChanged)

    let view = HtmlView.createFile(&host.root, guiFixturePath("std.pixel.html"))
    view.resize(1660, 1324)
    view.applyLayout()
    view.rebuild()
    var steps: u64
    while view.isLoading() and steps < 4_000
    {
        view.streamStep()
        steps += 1
    }

    @assert(!view.isLoading())

    var image = host.render(view)
    Pixel.Testing.assertImageGolden(&image, "htmlview.pixel-api")
    view.stopLoading()
}

// A file-open failure stays inspectable even when no observer was connected during construction.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()

    let path = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("missing_gui_html_%.html", Guid64.random()).toString())
    let view = HtmlView.createFile(&host.root, path)
    @assert(!view.failureReason.isEmpty())
    @assert(!view.isLoading())
}

// A `>` inside a quoted attribute value belongs to the value, not to the tag.
#test
{
    let document = parseDocument("<p><a href=\"#x\" title=\"a > b\" data-note='1 > 0'>link</a> tail</p><p>second</p>")
    let anchor   = findTag(&document, .A)
    @assert(anchor != HtmlNoNode)
    @assert(document.attribute(anchor, "title") == "a > b")
    @assert(document.attribute(anchor, "data-note") == "1 > 0")
    @assert(document.textContent(anchor).toString() == "link")

    var paragraphs = 0'u32
    for index in document.nodes.count where document.constNode(cast(u32) index).tag == .P do
        paragraphs += 1
    @assert(paragraphs == 2)

    // A stray quote outside any value still lets the tag end at its `>`.
    let strays = parseDocument("<p foo\"bar>text</p>")
    let para   = findTag(&strays, .P)
    @assert(para != HtmlNoNode)
    @assert(strays.textContent(para).toString() == "text")
}

// The newline that immediately follows a `<pre>` or `<textarea>` start tag is not content, and
// only that one is dropped.
#test
{
    let document = parseDocument("<pre>\nkeep</pre><pre>\n\ntwo</pre><textarea>\nvalue</textarea>")
    @assert(document.textContent(findNthTag(&document, .Pre, 1)).toString() == "keep")
    @assert(document.textContent(findNthTag(&document, .Pre, 2)).toString() == "\ntwo")
    @assert(document.textContent(findTag(&document, .TextArea)).toString() == "value")

    // A tag between the two keeps the newline: the rule only ever applies to the very next token.
    let nested = parseDocument("<pre><code>\nkept</code></pre>")
    @assert(nested.textContent(findTag(&nested, .Code)).toString() == "\nkept")
}

// Both fixes hold when the source arrives in chunks that cut a quoted value and a dropped
// newline at every awkward position.
#test
{
    let source = "<p><a href=\"#x\" title=\"a > b\">link</a> tail</p><pre>\n    indented</pre>"

    var streamed = HtmlDocument.create()
    var parser: HtmlParser
    parser.start(&streamed)

    var offset = 0'u64
    while offset < @countof(source)
    {
        let end = Math.min(offset + 3, @countof(source))
        parser.feed(source[offset until end])
        offset = end
    }

    parser.finish()

    let anchor = findTag(&streamed, .A)
    @assert(streamed.attribute(anchor, "title") == "a > b")
    @assert(streamed.textContent(findTag(&streamed, .Pre)).toString() == "    indented")
}

// Preserved white space keeps the indentation a code line starts with; collapsed white space
// still drops it. This is the shape of every `.code-block` the generated documentation draws.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 300)
    defer host.shutdown()

    var source: String = "<style>body { margin: 0 } div { font-family: monospace }"
    source += ".keep { white-space: pre }"
    source += ".fold { white-space: pre-line }"
    source += "</style>"
    source += "<div class=\"keep\" id=\"k\">zero\n    four</div>"
    source += "<div class=\"fold\" id=\"f\">zero\n    four</div>"

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(400, 300)
    view.applyLayout()
    view.rebuild()

    let kept = view.boxOfNode(view.elementById("k"))
    let keptZero = findItemPos(view, kept, "zero")
    let keptFour = findItemPos(view, kept, "four")
    @assert(keptZero.found and keptFour.found)
    @assert(keptFour.y > keptZero.y)

    // The second line starts four monospace spaces in, not at the margin.
    @assert(keptFour.x > keptZero.x + 1)

    let folded = view.boxOfNode(view.elementById("f"))
    let foldedZero = findItemPos(view, folded, "zero")
    let foldedFour = findItemPos(view, folded, "four")
    @assert(foldedZero.found and foldedFour.found)
    @assert(foldedFour.y > foldedZero.y)
    @assert(Math.abs(foldedFour.x - foldedZero.x) < 0.5)
}

// `repeat()` expands to its full track list, alone and mixed with plain tracks.
#test
{
    var source: String = "<style>body { margin: 0 }"
    source += ".grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 10px }"
    source += ".mix { display: grid; grid-template-columns: repeat(2, 100px 1fr) }"
    source += ".cell { height: 20px }"
    source += "</style>"
    source += "<div class=\"grid\"><div class=\"cell\" id=\"a\"></div><div class=\"cell\" id=\"b\"></div><div class=\"cell\" id=\"c\"></div><div class=\"cell\" id=\"d\"></div></div>"
    source += "<div class=\"mix\"><div class=\"cell\" id=\"m1\"></div><div class=\"cell\" id=\"m2\"></div><div class=\"cell\" id=\"m3\"></div><div class=\"cell\" id=\"m4\"></div></div>"

    var host: Testing.HeadlessHost
    host.setup(620, 400)
    defer host.shutdown()

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(620, 400)
    view.applyLayout()
    view.rebuild()

    let width = view.scroll.paddedClientRect().width
    let track = (width - 20) / 3
    let a = view.layout.constBox(view.boxOfNode(view.elementById("a")))
    let b = view.layout.constBox(view.boxOfNode(view.elementById("b")))
    let c = view.layout.constBox(view.boxOfNode(view.elementById("c")))
    let d = view.layout.constBox(view.boxOfNode(view.elementById("d")))

    // Three columns share the row; the fourth item wraps to the next one.
    @assert(a.rect.y == b.rect.y and b.rect.y == c.rect.y)
    @assert(d.rect.y > a.rect.y)
    @assert(Math.abs(a.rect.width - track) <= 0.75)
    @assert(Math.abs(b.rect.x - a.rect.right() - 10) <= 0.75)
    @assert(Math.abs(c.rect.right() - width) <= 0.75)

    let flexible = (width - 200) / 2
    let m1 = view.layout.constBox(view.boxOfNode(view.elementById("m1")))
    let m2 = view.layout.constBox(view.boxOfNode(view.elementById("m2")))
    let m3 = view.layout.constBox(view.boxOfNode(view.elementById("m3")))
    let m4 = view.layout.constBox(view.boxOfNode(view.elementById("m4")))
    @assert(m1.rect.y == m4.rect.y)
    @assert(Math.abs(m1.rect.width - 100) <= 0.75)
    @assert(Math.abs(m2.rect.width - flexible) <= 0.75)
    @assert(Math.abs(m3.rect.width - 100) <= 0.75)
    @assert(Math.abs(m3.rect.x - m2.rect.right()) <= 0.75)
}

// Preserved white space draws the indentation of a code block line by line — the shape every
// `.code-block` region of the generated documentation relies on.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 220)
    defer host.shutdown()

    var source: String = "<style>body { margin: 0; background: #ffffff }"
    source += ".code { margin: 12px; padding: 10px; background: #eef2f6; border: 1px solid #90a0b0; font-family: monospace; font-size: 14px; white-space: pre; color: #102030 }"
    source += "</style>"
    source += "<div class=\"code\">func demo()\n{\n    if ready\n        run(1)\n}</div>"

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(360, 220)
    view.applyLayout()
    view.rebuild()

    host.settleAnimations(view, 4)
    var image = host.render(view)
    Pixel.Testing.assertImageGolden(&image, "htmlview.preserved-whitespace")
}

// The tables fixture renders through the production view, so a column-sizing or cell-alignment
// regression lands in this image before any reader sees it.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let view = HtmlView.createFile(&host.root, guiFixturePath("html.tables.html"))
    view.resize(960, 680)
    view.applyLayout()
    view.rebuild()

    var steps: u64
    while view.isLoading() and steps < 4_000
    {
        view.streamStep()
        steps += 1
    }

    @assert(!view.isLoading())
    host.settleAnimations(view, 4)
    var image = host.render(view)
    Pixel.Testing.assertImageGolden(&image, "htmlview.tables")
}

// An image embedded in the document as a `data:` URI decodes like a file image, so a
// self-contained export shows its figures. The payload is the pixel module's own fixture.
#test
{
    const Embedded = "iVBORw0KGgoAAAANSUhEUgAAACAAAAAgAQAAAABbAUdZAAAABGdBTUEAAYagMeiWXwAAAFtJREFUeJwtzLEJAzAMBdHr0gSySiALejRvkBU8gsGNCmFFB1Hx4IovqurSpIRszqklUwbnUzRXEuIRsiG/SyY9G0JzJSVei9qynm9qyjBpLp0pYW7pbzBl8L8fEIdJL9AvFMkAAAAASUVORK5CYII="

    var host: Testing.HeadlessHost
    host.setup(200, 150)
    defer host.shutdown()

    var source: String = "<style>body { margin: 0 }</style><img id=\"i\" src=\"data:image/png;base64,"
    source += Embedded
    source += "\">"

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(200, 150)
    view.applyLayout()
    view.rebuild()

    // The embedded picture provides its natural size, so the box is no broken-image placeholder.
    let box = view.layout.constBox(view.boxOfNode(view.elementById("i")))
    @assert(box.content.width == 32 and box.content.height == 32)
    @assert(view.images.entries.count == 1 and view.images.entries[0].loaded)
    discard host.render(view)
}

// A document's bytes decide its decoding: a `charset=` declaration, a byte-order mark, or the
// content itself. Assuming UTF-8 used to refuse every legacy page outright.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 480)
    defer host.shutdown()

    // Windows-1252 declared by its meta tag, with the first accent far beyond the probe: only
    // the declaration can answer, because everything the heuristic sees is plain ASCII.
    var declared: String = "<html><head><meta charset=\"windows-1252\"></head><body>"
    for 200 do
        declared += "<p>ascii filler paragraph</p>"
    declared += "<p>caf"
    declared.append(0xE9'u8)
    declared += "</p></body></html>"
    let declaredText = loadTemporaryDocument(&host, @mkslice(cast(const [*] u8) declared.buffer!, declared.length), "declared")
    @assert(Utf8.contains(declaredText.toString(), "café"))

    // No declaration: the byte pattern itself says code page 1252.
    var plain: String = "<html><body><p>tr"
    plain.append(0xE8'u8)
    plain += "s vite</p></body></html>"
    let plainText = loadTemporaryDocument(&host, @mkslice(cast(const [*] u8) plain.buffer!, plain.length), "plain")
    @assert(Utf8.contains(plainText.toString(), "très vite"))

    // UTF-16 LE behind its byte-order mark, which is content in no encoding.
    var wide: Array'u8
    wide.add(0xFF)
    wide.add(0xFE)
    for value in "<html><body><p>wide text</p></body></html>"
    {
        wide.add(value)
        wide.add(0)
    }

    let wideText = loadTemporaryDocument(&host, wide.toSlice(), "wide")
    @assert(Utf8.contains(wideText.toString(), "wide text"))
    @assert(!Utf8.contains(wideText.toString(), "ÿþ"))
}

// The flex and grid fixture renders through the production view, pinning wrap, alignment, and
// track sizing as pixels rather than as a handful of sampled rectangles.
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 540)
    defer host.shutdown()

    let view = HtmlView.createFile(&host.root, guiFixturePath("html.flex-grid.html"))
    view.resize(960, 540)
    view.applyLayout()
    view.rebuild()

    var steps: u64
    while view.isLoading() and steps < 4_000
    {
        view.streamStep()
        steps += 1
    }

    @assert(!view.isLoading())
    host.settleAnimations(view, 4)
    var image = host.render(view)
    Pixel.Testing.assertImageGolden(&image, "htmlview.flex-grid")
}

// Misnested formatting keeps its formatting: the close that pops an inline ancestor reopens the
// formatting elements it swallowed, the way every browser recovers `<b>one <i>two</b> three</i>`.
#test
{
    let document = parseDocument("<p><b>one <i class=\"x\">two</b> three</i> four</p>")
    let bold     = findTag(&document, .B)
    @assert(bold != HtmlNoNode)
    @assert(document.textContent(bold).toString() == "one two")

    // Two italic elements exist: the original inside the bold, the reopened one after it, and
    // the clone carries the original's attributes.
    let first  = findNthTag(&document, .I, 1)
    let second = findNthTag(&document, .I, 2)
    @assert(first != HtmlNoNode and second != HtmlNoNode)
    @assert(document.constNode(first).parent == bold)
    @assert(document.constNode(second).parent == document.constNode(bold).parent)
    @assert(document.textContent(second).toString() == " three")
    @assert(document.hasClass(second, "x"))

    let para = findTag(&document, .P)
    @assert(document.textContent(para).toString() == "one two three four")
}

// Content written inside the table structure but outside any cell renders before the table,
// where browsers foster-parent it, and the grid keeps only its rows.
#test
{
    let document = parseDocument("<div><table>stray <b>bold</b><tr><td>cell</td></tr></table></div>")
    let host     = findTag(&document, .Div)
    let table    = findTag(&document, .Table)
    let bold     = findTag(&document, .B)
    @assert(document.constNode(bold).parent == host)

    // Order under the host: the fostered text, the fostered bold run, then the table.
    let children = &document.constNode(host).children
    @assert(children.count == 3)
    @assert(document.constNode(children[0]).kind == .Text)
    @assert(document.constNode(children[0]).text.toString() == "stray ")
    @assert(children[1] == bold)
    @assert(children[2] == table)

    let cell = findTag(&document, .Td)
    @assert(document.textContent(cell).toString() == "cell")
    @assert(document.textContent(table).toString() == "cell")
}

// A block interrupts a paragraph even through its open inline children: the paragraph closes,
// and the block is its sibling rather than its grandchild.
#test
{
    let document = parseDocument("<p>lead <b>bold<div>block</div>")
    let para     = findTag(&document, .P)
    let block    = findTag(&document, .Div)
    @assert(document.constNode(block).parent == document.constNode(para).parent)
    @assert(document.textContent(para).toString() == "lead bold")
    @assert(document.textContent(block).toString() == "block")
}

// The recoveries hold when the source arrives in chunks that cut every token.
#test
{
    let source = "<div><table>stray<tr><td>cell</td></tr></table></div><p><b>one <i>two</b> three</i></p>"

    var streamed = HtmlDocument.create()
    var parser: HtmlParser
    parser.start(&streamed)

    var offset = 0'u64
    while offset < @countof(source)
    {
        let end = Math.min(offset + 3, @countof(source))
        parser.feed(source[offset until end])
        offset = end
    }

    parser.finish()

    let host  = findTag(&streamed, .Div)
    let table = findTag(&streamed, .Table)
    @assert(streamed.constNode(host).children.count == 2)
    @assert(streamed.constNode(streamed.constNode(host).children[0]).text.toString() == "stray")
    @assert(streamed.constNode(host).children[1] == table)
    @assert(streamed.textContent(table).toString() == "cell")

    let second = findNthTag(&streamed, .I, 2)
    @assert(second != HtmlNoNode)
    @assert(streamed.textContent(second).toString() == " three")
}

// A left float leaves the stack: the lines beside it shorten, the flow returns to the margin
// below it, and `clear` starts below the floats it names.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 300)
    defer host.shutdown()

    var source: String = "<style>body { margin: 0 } p { margin: 0; font-size: 16px; line-height: 20px }"
    source += ".fig { float: left; width: 120px; height: 40px }"
    source += "</style>"
    source += "<div class=\"fig\" id=\"f\"></div>"
    source += "<p id=\"t\">first alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau upsilon phi chi psi omega<br>last</p>"
    source += "<div id=\"c\" style=\"clear: left; height: 10px\"></div>"

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(400, 300)
    view.applyLayout()
    view.rebuild()

    // The float sits at the top left, and the paragraph's own box still starts at the same top.
    let fig = view.layout.constBox(view.boxOfNode(view.elementById("f")))
    @assert(fig.rect.x == 0 and fig.rect.y == 0)
    @assert(fig.rect.width == 120 and fig.rect.height == 40)

    let para = view.boxOfNode(view.elementById("t"))
    @assert(view.layout.constBox(para).rect.y == 0)

    // Lines beside the float start at its right edge; the forced last line, well past the
    // float's bottom, returns to the margin.
    let beside = findItemPos(view, para, "first")
    @assert(beside.found and beside.x >= 120)
    @assert(beside.y < 40)
    let below = findItemPos(view, para, "last")
    @assert(below.found and below.x < 1)
    @assert(below.y >= 38)

    // The cleared box starts below the float's bottom rather than at the flow position.
    let cleared = view.layout.constBox(view.boxOfNode(view.elementById("c")))
    @assert(cleared.rect.y >= 40)
}

// A right float hugs the right edge, and the text keeps the left one.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 300)
    defer host.shutdown()

    var source: String = "<style>body { margin: 0 } p { margin: 0; font-size: 16px; line-height: 20px }"
    source += ".fig { float: right; width: 120px; height: 40px }"
    source += "</style>"
    source += "<div class=\"fig\" id=\"f\"></div>"
    source += "<p id=\"t\">first words wrap on the narrowed measure beside the floated box</p>"

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(400, 300)
    view.applyLayout()
    view.rebuild()

    let fig = view.layout.constBox(view.boxOfNode(view.elementById("f")))
    @assert(fig.rect.y == 0)
    @assert(Math.abs(fig.rect.right() - 400) <= 0.5)
    @assert(fig.rect.width == 120)

    let first = findItemPos(view, view.boxOfNode(view.elementById("t")), "first")
    @assert(first.found and first.x < 1 and first.y < 40)
}

// The classic article arrangement as pixels: a floated figure, the text wrapping beside it and
// returning to the full measure below, and a cleared footer starting under the float.
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 240)
    defer host.shutdown()

    var source: String = "<html><head><style>body { margin: 0; background: #ffffff; color: #102030; font-size: 14px; height: 240px }"
    source += "p { margin: 6px }"
    source += ".fig { float: left; width: 110px; height: 70px; margin: 6px; background: #4a7fb5 }"
    source += ".end { clear: left; background: #dbe6f1 }"
    source += "</style></head><body>"
    source += "<div class=\"fig\"></div>"
    source += "<p>The paragraph wraps beside the floated figure and keeps every line inside the narrowed measure, then returns to the full column width once the flow has passed below the figure's bottom edge.</p>"
    source += "<p class=\"end\">A cleared footer starts below the float.</p>"
    source += "</body></html>"

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(360, 240)
    view.applyLayout()
    view.rebuild()

    host.settleAnimations(view, 4)
    var image = host.render(view)
    Pixel.Testing.assertImageGolden(&image, "htmlview.floats")
}

// Returns the right edge of the widest visible item of a box, so overflow tests read geometry.
func maxItemRight(view: *HtmlView, box: u32)->f32
{
    var result = 0.0'f32
    for item in view.layout.constBox(box).items where item.visible do
        result = Math.max(result, item.x + item.width)
    return result
}

func countTextItems(view: *HtmlView, box: u32)->u64
{
    var result = 0'u64
    for item in view.layout.constBox(box).items where item.kind == .Text do
        result += 1
    return result
}

// An unbreakable run wider than its column breaks at a character boundary under
// `overflow-wrap: break-word`, and a later wider layout re-joins the fragments.
#test
{
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    defer host.shutdown()

    var source: String = "<style>body { margin: 0 } p { margin: 0; overflow-wrap: break-word }</style>"
    source += "<p id=\"t\">aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa</p>"

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(120, 600)
    view.applyLayout()
    view.rebuild()

    let box = view.boxOfNode(view.elementById("t"))
    @assert(view.layout.constBox(box).lines.count >= 2)
    @assert(maxItemRight(view, box) <= 120.5)
    @assert(countTextItems(view, box) >= 2)

    // The split fragments merge back once the measure is wide enough for the whole run.
    view.resize(800, 600)
    view.applyLayout()
    view.placeDocument()
    @assert(view.layout.constBox(box).lines.count == 1)
    @assert(countTextItems(view, box) == 1)
}

// CJK text carries no spaces: every character is a break opportunity, and the paragraph stays
// inside its column instead of overflowing it as one run.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 300)
    defer host.shutdown()

    var source: String = "<style>body { margin: 0 } p { margin: 0; width: 100px }</style>"
    source += "<p id=\"c\">法国是一个位于西欧的国家法国是一个位于西欧的国家</p>"

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(400, 300)
    view.applyLayout()
    view.rebuild()

    let box = view.boxOfNode(view.elementById("c"))
    @assert(view.layout.constBox(box).lines.count >= 2)
    @assert(maxItemRight(view, box) <= 100.5)

    // `word-break: keep-all` restores the unbreakable run.
    let keep = HtmlView.createText(&host.root, "<style>body { margin: 0 } p { margin: 0; width: 100px; word-break: keep-all }</style><p id=\"c\">法国是一个位于西欧的国家法国是一个位于西欧的国家</p>")
    keep.resize(400, 300)
    keep.applyLayout()
    keep.rebuild()
    @assert(countTextItems(keep, keep.boxOfNode(keep.elementById("c"))) == 1)
}

// `word-break: break-all` fills each line to its edge, splitting the run mid-word.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 300)
    defer host.shutdown()

    var source: String = "<style>body { margin: 0 } p { margin: 0; width: 120px; word-break: break-all }</style>"
    source += "<p id=\"t\">alpha bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb tail</p>"

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(400, 300)
    view.applyLayout()
    view.rebuild()

    let box = view.boxOfNode(view.elementById("t"))
    @assert(view.layout.constBox(box).lines.count >= 2)
    @assert(maxItemRight(view, box) <= 120.5)
}

// `<wbr>` marks a soft break opportunity, and `&shy;` breaks with a visible hyphen only where
// the break was taken.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 300)
    defer host.shutdown()

    var source: String = "<style>body { margin: 0 } p { margin: 0; width: 140px; font-size: 16px }</style>"
    source += "<p id=\"w\">aaaaaaaaaa<wbr>bbbbbbbbbb</p>"
    source += "<p id=\"s\">cccccccccc&shy;dddddddddd</p>"
    source += "<p id=\"n\">eeeeeeeeee&shy;ff</p>"

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(400, 300)
    view.applyLayout()
    view.rebuild()

    let broken = view.boxOfNode(view.elementById("w"))
    let first  = findItemPos(view, broken, "aaaaaaaaaa")
    let second = findItemPos(view, broken, "bbbbbbbbbb")
    @assert(first.found and second.found)
    @assert(second.y > first.y)

    // The soft hyphen leaves the run, breaks it, and the head fragment draws its hyphen.
    let hyphenated = view.boxOfNode(view.elementById("s"))
    @assert(view.layout.constBox(hyphenated).lines.count == 2)
    var sawHyphen: bool
    for item in view.layout.constBox(hyphenated).items where item.kind == .Text and item.text.toString() == "cccccccccc"
    {
        sawHyphen = item.hyphenAtBreak
        break
    }

    @assert(sawHyphen)

    // A soft hyphen where no break is needed draws nothing and the line stays whole.
    let whole = view.boxOfNode(view.elementById("n"))
    @assert(view.layout.constBox(whole).lines.count == 1)
    for item in view.layout.constBox(whole).items do
        @assert(!item.hyphenAtBreak)
}

// The `font` shorthand expands into its longhands, including the `/line-height` form, and
// `word-spacing` widens each space of the line.
#test
{
    var host: Testing.HeadlessHost
    host.setup(600, 400)
    defer host.shutdown()

    var source: String = "<style>#f { font: italic 700 20px/2 monospace } #ws { word-spacing: 10px }</style>"
    source += "<p id=\"f\">styled</p>"
    source += "<p id=\"ws\">a b</p>"
    source += "<p id=\"nb\">a b</p>"

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(600, 400)
    view.applyLayout()
    view.rebuild()

    let styled = view.layout.styleOfNode(view.elementById("f"))
    @assert(styled.italic)
    @assert(styled.fontWeight == 700)
    @assert(styled.fontSize == 20)
    @assert(styled.lineHeight.kind == .Percent and styled.lineHeight.value == 2)
    @assert(styled.fontFamily == .Mono)

    var spaced, plain: f32
    for item in view.layout.constBox(view.boxOfNode(view.elementById("ws"))).items where item.kind == .Space do
        spaced = item.width
    for item in view.layout.constBox(view.boxOfNode(view.elementById("nb"))).items where item.kind == .Space do
        plain = item.width
    @assert(plain > 0)
    @assert(Math.abs(spaced - plain - 10) <= 0.01)
}

// Reports whether a parsed color lands within a small tolerance of an expected paint, which is
// what a conversion through another color space can promise.
func closeColor(value: HtmlColorValue, argb: u32, tolerance = 3's32)->bool
{
    if !value.matched do
        return false

    let expected = Pixel.Color.fromArgb(argb)
    let dr       = Math.abs(cast(s32) value.color.r - cast(s32) expected.r)
    let dg       = Math.abs(cast(s32) value.color.g - cast(s32) expected.g)
    let db       = Math.abs(cast(s32) value.color.b - cast(s32) expected.b)
    let da       = Math.abs(cast(s32) value.color.a - cast(s32) expected.a)
    return dr <= tolerance and dg <= tolerance and db <= tolerance and da <= tolerance
}

// The modern color notations convert to sRGB: the OK family, the Lab family, `hwb()`, the
// `color()` function, and hue units other than degrees.
#test
{
    @assert(closeColor(htmlParseColor("oklch(0.62796 0.25768 29.234)"), 0xFFFF0000))
    @assert(closeColor(htmlParseColor("oklab(0.62796 0.22486 0.12585)"), 0xFFFF0000))
    @assert(closeColor(htmlParseColor("oklch(100% 0 0)"), 0xFFFFFFFF))
    @assert(closeColor(htmlParseColor("lab(54.29 80.805 69.891)"), 0xFFFF0000))
    @assert(closeColor(htmlParseColor("lch(54.29 106.84 40.858)"), 0xFFFF0000))
    @assert(closeColor(htmlParseColor("hwb(120 0% 0%)"), 0xFF00FF00))
    @assert(closeColor(htmlParseColor("hwb(0 100% 0%)"), 0xFFFFFFFF))
    @assert(closeColor(htmlParseColor("hwb(0 40% 60%)"), 0xFF666666))
    @assert(closeColor(htmlParseColor("color(srgb 1 0 0)"), 0xFFFF0000))
    @assert(closeColor(htmlParseColor("color(srgb-linear 1 0 0)"), 0xFFFF0000))
    @assert(closeColor(htmlParseColor("color(display-p3 1 0 0)"), 0xFFFF0000, 12))
    @assert(closeColor(htmlParseColor("hsl(0.5turn 100% 50%)"), 0xFF00FFFF))
    @assert(closeColor(htmlParseColor("hsl(3.14159rad 100% 50%)"), 0xFF00FFFF))

    // Alpha rides behind the slash whatever the notation.
    let translucent = htmlParseColor("oklch(0.62796 0.25768 29.234 / 50%)")
    @assert(translucent.matched and Math.abs(cast(s32) translucent.color.a - 128) <= 1)

    // An out-of-gamut color clamps to the gamut edge instead of wrapping.
    let vivid = htmlParseColor("oklch(0.9 0.37 145)")
    @assert(vivid.matched and vivid.color.g == 255)

    // An unknown color space is refused, so the cascade keeps its previous value.
    @assert(!htmlParseColor("color(rec2020 1 0 0)").matched)
}

// The full `an+b` grammar matches, and the `-of-type` selectors count within their type.
#test
{
    var source: String = "<style>"
    source += "li { color: #000000 }"
    source += "li:nth-child(3n) { color: #ff0000 }"
    source += "li:nth-child(-n+2) { font-weight: 700 }"
    source += "p:nth-of-type(2) { color: #00ff00 }"
    source += "span:first-of-type { color: #0000ff }"
    source += "</style>"
    source += "<ul><li>1</li><li>2</li><li>3</li><li>4</li><li>5</li><li>6</li></ul>"
    source += "<div><p>one</p><span>s1</span><p>two</p><span>s2</span></div>"

    var host: Testing.HeadlessHost
    host.setup(600, 400)
    defer host.shutdown()

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(600, 400)
    view.applyLayout()
    view.rebuild()

    let red   = Pixel.Color.fromArgb(0xFFFF0000)
    let black = Pixel.Color.fromArgb(0xFF000000)
    for wanted in 6'u32
    {
        let item  = findNthTag(&view.document, .Li, wanted + 1)
        let style = view.layout.styleOfNode(item)
        @assert(style.color == ((wanted + 1) % 3 == 0 ? red : black))
        @assert(style.fontWeight == (wanted < 2 ? 700 : 400))
    }

    @assert(view.layout.styleOfNode(findNthTag(&view.document, .P, 1)).color != Pixel.Color.fromArgb(0xFF00FF00))
    @assert(view.layout.styleOfNode(findNthTag(&view.document, .P, 2)).color == Pixel.Color.fromArgb(0xFF00FF00))
    @assert(view.layout.styleOfNode(findNthTag(&view.document, .Span, 1)).color == Pixel.Color.fromArgb(0xFF0000FF))
    @assert(view.layout.styleOfNode(findNthTag(&view.document, .Span, 2)).color != Pixel.Color.fromArgb(0xFF0000FF))
}

// A hostile document nested thousands of elements deep flattens at the depth bound instead of
// walking the recursive passes off the native stack, and its content stays readable.
#test
{
    var source: String
    for 4000 do
        source += "<div>"
    source += "deep text"

    let document = parseDocument(source.toString())
    @assert(Utf8.contains(document.textContent(0).toString(), "deep text"))

    var deepest = 0'u64
    for index in document.nodes.count
    {
        var depth = 0'u64
        var walk  = document.constNode(cast(u32) index).parent
        while walk != HtmlNoNode
        {
            depth += 1
            walk  = document.constNode(walk).parent
        }

        deepest = Math.max(deepest, depth)
    }

    @assert(deepest <= HtmlMaxElementDepth + 1)

    // The whole pipeline survives the same document: styling, box building, layout, painting.
    var host: Testing.HeadlessHost
    host.setup(320, 240)
    defer host.shutdown()

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(320, 240)
    view.applyLayout()
    view.rebuild()
    discard host.render(view)
    @assert(Utf8.contains(view.document.textContent(0).toString(), "deep text"))
}
