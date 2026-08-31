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

    Swag.assert(!view.isLoading())
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
    Swag.assert(body != HtmlNoNode)

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
    Swag.assert(paragraphs == 2 and items == 2)
    let first = findTag(&document, .P)
    Swag.assert(document.constNode(first).parent == body)

    let division = findTag(&document, .Div)
    Swag.assert(document.hasClass(division, "x") and document.hasClass(division, "y"))
    Swag.assert(!document.hasClass(division, "z"))
    Swag.assert(document.id(division) == "z")
    Swag.assert(document.attribute(division, "class") == "x y")
}

// Character references decode to their code points, including the numeric forms.
#test
{
    Swag.assert(htmlDecodeText("a&amp;b").toString() == "a&b")
    Swag.assert(htmlDecodeText("&lt;tag&gt;").toString() == "<tag>")
    Swag.assert(htmlDecodeText("&#65;&#x42;").toString() == "AB")
    Swag.assert(htmlDecodeText("caf&eacute;").toString() == "café")
    Swag.assert(htmlDecodeText("&nosuchentity;").toString() == "&nosuchentity;")
    Swag.assert(htmlDecodeText("a & b").toString() == "a & b")
}

// A raw-text element never contributes markup, whatever it contains.
#test
{
    let document = parseDocument("<style>p { color: red }</style><script>if (a<b) {}</script><p>after</p>")
    Swag.assert(findTag(&document, .P) != HtmlNoNode)

    let style = findTag(&document, .Style)
    Swag.assert(style != HtmlNoNode)
    Swag.assert(Utf8.contains(document.textOf(document.childAt(style, 0)), "color: red"))

    // A script body is text, so its `<` never opened an element.
    Swag.assert(findTag(&document, .B) == HtmlNoNode)
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
    Swag.assert(streamed.nodes.count == whole.nodes.count)
    Swag.assert(streamed.textContent(0) == whole.textContent(0))
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
    Swag.assert(style.color == Color.fromArgb(0xFF0000FF))
    Swag.assert(style.fontSize == 20)

    let emphasis = findTag(&view.document, .Em)
    Swag.assert(!view.layout.styleOfNode(emphasis).italic)
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

    Swag.assert(htmlParseLength(&pool, "12px", context).length.resolve(&pool, context) == 12)
    Swag.assert(htmlParseLength(&pool, "2em", context).length.resolve(&pool, context) == 40)
    Swag.assert(htmlParseLength(&pool, "2rem", context).length.resolve(&pool, context) == 32)
    Swag.assert(htmlParseLength(&pool, "50%", context).length.resolve(&pool, context) == 200)
    Swag.assert(htmlParseLength(&pool, "10vw", context).length.resolve(&pool, context) == 100)
    Swag.assert(htmlParseLength(&pool, "calc(100% - 44px)", context).length.resolve(&pool, context) == 356)
    Swag.assert(htmlParseLength(&pool, "min(1560px, calc(100% - 44px))", context).length.resolve(&pool, context) == 356)
    Swag.assert(htmlParseLength(&pool, "clamp(10px, 50%, 80px)", context).length.resolve(&pool, context) == 80)
    Swag.assert(htmlParseLength(&pool, "auto", context).length.isAuto())
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
    Swag.assert(style.clipPath != HtmlNoNode)
    Swag.assert(!style.masked)

    var image = host.render(view)
    Swag.assert(image.isValid())
}

// Every color notation a document uses reads back as the same paint.
#test
{
    Swag.assert(htmlParseColor("#f00").color == Color.fromArgb(0xFFFF0000))
    Swag.assert(htmlParseColor("#00ff00").color == Color.fromArgb(0xFF00FF00))
    Swag.assert(htmlParseColor("#0000ff80").color == Color.fromArgb(0x800000FF))
    Swag.assert(htmlParseColor("rgb(255, 0, 0)").color == Color.fromArgb(0xFFFF0000))
    Swag.assert(htmlParseColor("rgba(255 0 0 / 50%)").color.a == 128)
    Swag.assert(htmlParseColor("hsl(0, 100%, 50%)").color == Color.fromArgb(0xFFFF0000))
    let translucent = htmlParseColor("color-mix(in srgb, #ff0000 25%, transparent)")
    Swag.assert(translucent.matched and translucent.color.a == 64 and translucent.color.r == 255 and !translucent.color.g and !translucent.color.b)
    Swag.assert(htmlParseColor("color-mix(in srgb, #0000ff 20%, #ffffff)").color == Color.fromArgb(0xFFCCCCFF))
    Swag.assert(htmlParseColor("rebeccapurple").color == Color.fromArgb(0xFF663399))
    Swag.assert(htmlParseColor("transparent").matched and !htmlParseColor("transparent").color.a)
    Swag.assert(!htmlParseColor("inherit").matched)
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
    Swag.assert(second.rect.y - first.rect.bottom() == 20)

    let left  = view.layout.constBox(view.boxOfNode(view.elementById("c")))
    let right = view.layout.constBox(view.boxOfNode(view.elementById("d")))
    Swag.assert(left.rect.width == 100)
    Swag.assert(right.rect.x - left.rect.right() == 10)
    Swag.assert(right.rect.width == view.scroll.paddedClientRect().width - 110)
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
    Swag.assert(fixed.rect.width == 100)
    Swag.assert(grow.rect.x == 120)
    Swag.assert(Math.abs(grow.rect.width - (width - 120)) <= 0.5)
}

// Text wraps into as many lines as the measure allows, and a forced break starts a new one.
#test
{
    var host: Testing.HeadlessHost
    host.setup(400, 400)
    defer host.shutdown()

    var source: String = "<style>body { margin: 0; font-size: 16px }</style><p id=\"p\">"
    for 400 do
        source += "word "
    source += "</p><p id=\"q\">one<br>two</p>"

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(400, 400)
    view.applyLayout()
    view.rebuild()

    let wrapped = view.layout.constBox(view.boxOfNode(view.elementById("p")))
    Swag.assert(wrapped.lines.count > 20)
    for line in wrapped.lines where line.width > wrapped.content.width + 1 do
        Swag.assert(false)

    // Painting and hit testing use the line index instead of scanning every run in the block.
    let lineIndex = 12'u64
    let range     = htmlLineItemRange(wrapped, wrapped.lines[lineIndex].top, wrapped.lines[lineIndex].top + 1)
    Swag.assert(range.first == wrapped.lines[lineIndex - 1].first)
    Swag.assert(range.last == wrapped.lines[lineIndex + 1].last)
    Swag.assert(range.last - range.first < wrapped.items.count / 4)

    let broken = view.layout.constBox(view.boxOfNode(view.elementById("q")))
    Swag.assert(broken.lines.count == 2)
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
    Swag.assert(code.lines.count == 2)
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
    Swag.assert(block.rect.x == 8)
    Swag.assert(block.rect.width == 840)
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
    Swag.assert(wide.rect.width > narrow.rect.width)
    Swag.assert(wide.rect.x == narrow.rect.right())
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
    Swag.assert(!cell.children.isEmpty())
    let content = view.layout.constBox(cell.children[0])
    Swag.assert(!content.items.isEmpty())
    Swag.assert(content.items[0].y + content.items[0].ascent + content.items[0].descent >= cell.content.bottom() - 1)
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
    Swag.assert(rail != HtmlNoNode and view.layout.constBox(rail).scrollable)
    Swag.assert(view.layout.constBox(rail).rect.y == 40)
    Swag.assert(view.painter().scrollableAt({20, 60}) == rail)
    Swag.assert(view.scrollRegion(rail, 80))
    Swag.assert(view.layout.constBox(rail).scrollTop == 80)

    var image = host.render(view)
    Swag.assert(image.pixelColor(20, 60).argb == 0xFF0000FF)
    Swag.assert(image.pixelColor(97, 90).argb == host.theme.colors.scrollBar_Box.argb)
    Swag.assert(image.pixelColor(20, 30).argb != 0xFFFF0000 and image.pixelColor(20, 30).argb != 0xFF0000FF)
    Swag.assert(image.pixelColor(20, 130).argb != 0xFFFF0000 and image.pixelColor(20, 130).argb != 0xFF0000FF)
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
    Swag.assert(picture.rect.y < view.scroll.scrollPosition().y)
    Swag.assert(parent.paintBounds.bottom() == picture.rect.bottom())
    Swag.assert(view.layout.documentHeight == picture.rect.bottom())
    var image = host.render(view)
    Swag.assert(image.pixelColor(20, 20).argb == 0xFFFF0000)
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
    Swag.assert(rail != HtmlNoNode)
    let bar = view.painter().scrollBarAt({96, 75})
    Swag.assert(bar.box == rail and bar.track.contains(Math.Point{96, 75}))

    host.click({96, 75})
    Swag.assert(view.layout.constBox(rail).scrollTop == 100)

    let moved = view.painter().scrollBarAt({96, 50})
    Swag.assert(moved.box == rail and moved.thumb.y <= 50 and moved.thumb.bottom() >= 50)
    host.mouseDown({91, 50})
    host.moveMouse({91, 95})
    host.mouseUp({91, 95})
    Swag.assert(view.layout.constBox(rail).scrollTop > 190)
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
    Swag.assert(rail != HtmlNoNode)
    Swag.assert(Math.abs(view.layout.constBox(rail).content.height - (view.layout.viewport.y - 40)) <= 1)
    Swag.assert(view.layout.constBox(rail).scrollable)
    Swag.assert(view.painter().scrollableAt({20, 80}) == rail)
    Swag.assert(view.scrollRegion(rail, 70))
    Swag.assert(view.layout.constBox(rail).scrollTop == 70)
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
    Swag.assert(image.pixelColor(120, 20).argb == 0xFFFF0000)
    Swag.assert(image.pixelColor(120, 80).argb == 0xFF0000FF)
    Swag.assert(view.document.constNode(view.painter().nodeAt({120, 20})).tag == .Header)
}

// The complete fixture renders, and nothing a document hides reaches the drawn text.
#[Swag.TestTag("golden")]
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
    Swag.assert(Utf8.contains(text.toString(), "Heading level one"))
    Swag.assert(Utf8.contains(text.toString(), "The distant html verification marker"))
    Swag.assert(!Utf8.contains(text.toString(), "must not render"))

    // A hidden container is parsed and then left out of the box tree entirely.
    for index in view.layout.boxes.count
    {
        let node = view.layout.constBox(cast(u32) index).node
        if node == HtmlNoNode do
            continue
        Swag.assert(view.document.constNode(node).tag != .Script)
        Swag.assert(view.document.constNode(node).tag != .Template)
    }

    Swag.assert(view.layout.documentHeight > 680)

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
    Swag.assert(fixtureOffset != Swag.U64.Max)

    var source: String = "<html><body>"
    for 24_000 do
        source += "<h2>Streamed section</h2><p>A paragraph stays outside the resident window.</p>"
    let offset = source.length + fixtureOffset
    source += fixture
    for 5_000 do
        source += "<p>A trailing paragraph keeps the document large.</p>"
    source += "</body></html>"
    Swag.assert(source.length >= 2 * 1024 * 1024)
    discard expect File.writeAllBytes(fileName, Swag.makeSlice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let view = HtmlView.createFile(&host.root, fileName)
    view.resize(960, 680)
    view.applyLayout()
    Swag.assert(view.revealFileOffset(offset, query))

    var steps = 0'u32
    while view.isLoading() and steps < 4_000
    {
        view.streamStep()
        steps += 1
    }

    Swag.assert(!view.isLoading())
    Swag.assert(view.pendingSearch.isEmpty())
    Swag.assert(view.searchNode != HtmlNoNode)
    Swag.assert(Utf8.contains(view.document.textOf(view.searchNode), query))
    Swag.assert(view.searchEnd - view.searchStart == query.count)

    // The match is what the viewport shows, not an estimate of where it might be.
    let box = view.boxOfNode(view.searchNode)
    Swag.assert(box != HtmlNoNode)
    let top      = view.layout.constBox(box).rect.y + (view.virtualSource ? view.virtualOrigin : 0)
    let position = view.scroll.scrollPosition().y
    Swag.assert(top >= position and top <= position + view.scroll.paddedClientRect().height)
}

// Progressive refreshes spread out fourfold, so a large generated page does not repeatedly
// rebuild almost the same prefix while the reader is still interacting with it.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("gui_html_refresh_%.html", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source: String = "<pre>"
    for 2_400 do
        source += "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ repeated source line\n"
    source += "</pre>"
    Swag.assert(source.length > 192 * 1024)
    discard expect File.writeAllBytes(fileName, Swag.makeSlice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(640, 360)
    defer host.shutdown()

    let view = HtmlView.createFile(&host.root, fileName)
    view.resize(640, 360)
    view.applyLayout()
    while view.bytesRead < 192 * 1024 do
        view.streamStep()

    Swag.assert(view.nextRefresh == view.bytesRead * 4)
    view.stopLoading()
}

// Painting a search hit survives every split of the match across inline items: an item that
// begins inside the hit has an empty prefix, which must never reach String.opSlice.
#test
{
    var host: Testing.HeadlessHost
    host.setup(220, 240)
    defer host.shutdown()

    let view = HtmlView.createText(&host.root, "<p>alpha beta gamma delta epsilon zeta</p>")
    view.resize(220, 240)
    view.applyLayout()
    view.rebuild()

    // One hit covering a whole item, then one the narrow viewport can split across a wrap.
    Swag.assert(view.findText("alpha"))
    discard host.render(view)
    Swag.assert(view.findText("gamma delta"))
    discard host.render(view)
}

// A source-backed reveal marks the requested occurrence, not the first equal word in its node.
#test
{
    var host: Testing.HeadlessHost
    host.setup(320, 180)
    defer host.shutdown()

    const Source = "<p>same same same</p>"
    let second = Utf8.indexOf(Source, "same", Utf8.indexOf(Source, "same") + 1)
    let view   = HtmlView.createText(&host.root, Source)
    view.resize(320, 180)
    view.applyLayout()
    view.rebuild()

    Swag.assert(view.revealFileOffset(second, "same"))
    Swag.assert(view.searchNode != HtmlNoNode and view.searchStart == 5 and view.searchEnd == 9)
    var bounds: Math.Rectangle
    Swag.assert(view.searchMatchRect(&bounds) and !bounds.isEmpty())
    view.clearSearch()
    Swag.assert(!view.searchMatchRect(&bounds))
}

// A real generated Rustdoc page keeps its full production scale. Its highlighted source expands
// to hundreds of thousands of nodes, and its structural selectors used to rescan tens of
// thousands of siblings for each match. Small documents cannot expose that failure mode.
#test
{
    let allocator = Swag.defaultAllocator()
    let initial   = allocator.stats()

    var host: Testing.HeadlessHost
    host.setup(960, 680)
    defer host.shutdown()

    let path = guiFixturePath("html.rustdoc-large.html")
    let view = HtmlView.createFile(&host.root, path)
    view.resize(960, 680)
    view.applyLayout()

    Swag.assert(view.fileSize == 8_153_570)
    Swag.assert(view.virtualSource)
    Swag.assert(view.sourceDone)
    Swag.assert(view.virtualWindowEnd - view.virtualWindowStart < 256 * 1024)
    Swag.assert(view.document.nodes.count < 20_000)
    Swag.assert(view.layout.boxes.count < 10_000)
    Swag.assert(view.layout.styles.count < 10_000)
    Swag.assert(view.virtualHeight > view.layout.documentHeight * 10)

    // Visiting the middle replaces the resident document instead of appending to it. Returning
    // to the same source offset materializes the same bounded window and the same pixels.
    let middle = view.fileSize / 2
    Swag.assert(view.revealFileOffset(middle, ""))
    let middleStart = view.virtualWindowStart
    let middleEnd   = view.virtualWindowEnd
    let first       = Hash.hashBytes32(host.render(view).pixels.toSlice())
    Swag.assert(middleStart < middle and middleEnd > middle)
    Swag.assert(middle - middleStart > (middleEnd - middleStart) / 4)
    Swag.assert(middleEnd - middle > (middleEnd - middleStart) / 4)
    Swag.assert(!view.virtualPendingSeek)
    Swag.assert(view.document.nodes.count < 20_000)

    Swag.assert(view.revealFileOffset(view.virtualContentStart, ""))
    Swag.assert(view.revealFileOffset(middle, ""))
    Swag.assert(view.virtualWindowStart == middleStart and view.virtualWindowEnd == middleEnd)
    let second = Hash.hashBytes32(host.render(view).pixels.toSlice())
    Swag.assert(second == first)

    let resident = allocator.stats()
    Swag.assert(resident.sizeAlloc < initial.sizeAlloc + 128 * 1024 * 1024)
}

// Large ordinary HTML is bounded too, even when it has no generated-source `<pre>` shape. The
// generic window may start at a recovery boundary, but it must never make file size become DOM
// size and revisiting one byte offset must choose the same resident source.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("gui_html_large_window_%.html", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source: String = "<html><head><style>p { margin: 4px }</style></head><body>"
    for index in 28_000 do
        source += Format.toString("<p id='row-%'>Paragraph % carries enough ordinary HTML to exercise a generic resident window.</p>\n", index, index)
    source += "</body></html>"
    Swag.assert(source.length > 2 * 1024 * 1024)
    discard expect File.writeAllBytes(fileName, Swag.makeSlice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(720, 480)
    defer host.shutdown()

    let view = HtmlView.createFile(&host.root, fileName)
    view.resize(720, 480)
    view.applyLayout()
    Swag.assert(view.virtualSource and !view.virtualPreformatted)
    Swag.assert(view.document.nodes.count < 20_000)

    let middle = view.fileSize / 2
    Swag.assert(view.revealFileOffset(middle, ""))
    let residentStart = view.virtualWindowStart
    let residentEnd   = view.virtualWindowEnd
    Swag.assert(residentStart < middle and residentEnd > middle)
    Swag.assert(view.document.nodes.count < 20_000)
    Swag.assert(view.revealFileOffset(view.virtualContentStart, ""))
    Swag.assert(view.revealFileOffset(middle, ""))
    Swag.assert(view.virtualWindowStart == residentStart and view.virtualWindowEnd == residentEnd)
}

// What a scroll position shows does not depend on how the reader got there.
//
// This is the contract the previous viewer could not keep: its scroll-to-byte estimate changed as
// it moved the resident source window, so travelling with the scrollbar rewrote the text and
// sometimes emptied the page. A virtual window must map a position deterministically.
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
    discard expect File.writeAllBytes(fileName, Swag.makeSlice(cast(const [*] u8) source.buffer!, source.length))

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

    Swag.assert(!view.isLoading())

    // Three positions, visited downwards and then upwards; every one must draw the same pixels
    // both times, and none of them may be blank.
    let stops             = [400.0'f32, 5_000.0'f32, 20_000.0'f32]
    var downward: [3] u32 = undefined
    for index in stops.count
    {
        view.scroll.setScrollPos(0, stops[index])
        var image = host.render(view)
        downward[index] = Hash.hashBytes32(image.pixels.toSlice())
    }

    for index in stops.count
    {
        let reverse = stops.count - index - 1
        view.scroll.setScrollPos(0, stops[reverse])
        var image = host.render(view)
        Swag.assert(Hash.hashBytes32(image.pixels.toSlice()) == downward[reverse])
    }

    Swag.assert(downward[0] != downward[1] and downward[1] != downward[2])
}

// A virtual HTML document follows the latest scrollbar position through repeated long seeks and
// reversals. Revisiting a stop must materialize the same source window and the same pixels.
#test
{
    let tempDirectory = Env.getSpecialDirectory(.Temp)
    let fileName      = Path.combine(tempDirectory.toString(), Format.toString("gui_html_virtual_scrub_%.html", Guid64.random()).toString())
    defer discard catch File.delete(fileName)

    var source: String = "<html><body><style>p { margin: 4px } h2 { color: #2255aa }</style>"
    for index in 32_000 do
        source += Format.toString("<h2>Scrub section %</h2><p>Unique paragraph % keeps a virtual seek visible and deterministic.</p>\n", index, index)
    source += "</body></html>"
    Swag.assert(source.length > 2 * 1024 * 1024)
    discard expect File.writeAllBytes(fileName, Swag.makeSlice(cast(const [*] u8) source.buffer!, source.length))

    var host: Testing.HeadlessHost
    host.setup(720, 480)
    defer host.shutdown()
    let view = HtmlView.createFile(&host.root, fileName)
    view.resize(720, 480)
    view.applyLayout()
    Swag.assert(view.virtualSource and view.virtualHeight > 0)

    // Returning to the resident window before the timer fires cancels the obsolete long seek.
    let residentY = view.scroll.scrollPosition().y
    view.scroll.setScrollPos(0, view.virtualHeight * 0.85)
    Swag.assert(view.virtualPendingSeek)
    view.scroll.setScrollPos(0, residentY)
    Swag.assert(!view.virtualPendingSeek)

    // Two gestures before the timer fires coalesce to the newest request.
    view.scroll.setScrollPos(0, view.virtualHeight * 0.85)
    view.scroll.setScrollPos(0, view.virtualHeight * 0.15)
    Swag.assert(view.virtualPendingSeek and view.loadTimer != null)
    host.fireTimer(view.loadTimer)
    let lowOffset = view.virtualContentStart + cast(u64) (0.15 * cast(f32) (view.fileSize - view.virtualContentStart))
    Swag.assert(view.virtualWindowStart <= lowOffset and view.virtualWindowEnd >= lowOffset)
    Swag.assert(!view.virtualPendingSeek)

    let ratios             = [0.15'f32, 0.75'f32, 0.35'f32, 0.9'f32]
    var firstPass: [4] u32 = undefined
    for ratio, index in ratios
    {
        view.scroll.setScrollPos(0, view.virtualHeight * ratio)
        if view.virtualPendingSeek
        {
            Swag.assert(view.loadTimer != null)
            host.fireTimer(view.loadTimer)
        }

        Swag.assert(!view.virtualPendingSeek)
        Swag.assert(view.layout.boxes.count > 1)
        var image = host.render(view)
        firstPass[index] = Hash.hashBytes32(image.pixels.toSlice())
    }

    for index in ratios.count
    {
        let reverse = ratios.count - index - 1
        view.scroll.setScrollPos(0, view.virtualHeight * ratios[reverse])
        if view.virtualPendingSeek
        {
            Swag.assert(view.loadTimer != null)
            host.fireTimer(view.loadTimer)
        }

        var image = host.render(view)
        Swag.assert(Hash.hashBytes32(image.pixels.toSlice()) == firstPass[reverse])
    }
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

    Swag.assert(view.focusPolicy == .Tab)
    Swag.assert(view.scroll.scrollableClientRect().height > view.scroll.paddedClientRect().height)

    var end = KeyEvent{kind: .Pressed, key: .End}
    Swag.assert(scrollDocumentWithKey(view.scroll, &end))
    let bottom = view.scroll.scrollPosition().y
    Swag.assert(bottom > 0)

    var pageUp = KeyEvent{kind: .Pressed, key: .PageUp}
    Swag.assert(scrollDocumentWithKey(view.scroll, &pageUp))
    Swag.assert(view.scroll.scrollPosition().y < bottom)

    var home = KeyEvent{kind: .Pressed, key: .Home}
    Swag.assert(scrollDocumentWithKey(view.scroll, &home))
    Swag.assert(view.scroll.scrollPosition().y == 0)

    // A pointer gesture on prose restores the document after another control temporarily owned
    // the keyboard, so later navigation keys cannot disappear into stale focus.
    host.focus(&host.root)
    Swag.assert(!view.hasFocus())
    host.click({20, 20})
    Swag.assert(view.hasFocus())
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
    Swag.assert(bar != HtmlNoNode)
    let decoration = view.layout.constBox(bar)
    Swag.assert(decoration.rect.width == 32 and decoration.rect.height == 4)
    Swag.assert(decoration.rect.x == heading.rect.x and decoration.rect.y == heading.rect.y)
    Swag.assert(heading.content.y == decoration.rect.y + 14)
    var textBox = HtmlNoNode
    for child in heading.children where view.layout.constBox(child).items.count do
        textBox = child
    Swag.assert(textBox != HtmlNoNode and view.layout.constBox(textBox).lines.front().top == heading.content.y)
    var image = host.render(view)
    Swag.assert(image.pixelColor(cast(u32) decoration.rect.horzCenter(), cast(u32) decoration.rect.vertCenter()).argb == 0xFFFF8080)
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
        Swag.assert(document.nodes.count > 4)
        Swag.assert(findTag(&document, .Body) != HtmlNoNode)
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
    Swag.assert(header.rect.height == 66)
    Swag.assert(Math.abs(brand.rect.vertCenter() - header.rect.vertCenter()) <= 1)
    Swag.assert(!links.children.isEmpty())
    Swag.assert(Math.abs(github.rect.y - view.layout.constBox(links.children[0]).rect.y) <= 1)
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
    Swag.assert(rail != HtmlNoNode and view.layout.constBox(rail).scrollable)
    view.scroll.setScrollPos(0, 520)
    let pageStart = view.scroll.scrollPosition().y

    host.mouseWheel({60, 100}, -1)
    Swag.assert(view.layout.constBox(rail).scrollTop > 0)
    Swag.assert(view.scroll.scrollPosition().y == pageStart)

    discard view.scrollRegion(rail, 100_000)
    let railEnd = view.layout.constBox(rail).scrollTop
    host.mouseWheel({60, 100}, -1)
    Swag.assert(view.layout.constBox(rail).scrollTop == railEnd)
    Swag.assert(view.scroll.scrollPosition().y == pageStart)

    host.mouseWheel({420, 180}, -1)
    Swag.assert(view.scroll.scrollPosition().y > pageStart)
    Swag.assert(view.layout.constBox(rail).scrollTop == railEnd)
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
    Swag.assert(hit.found)
    host.click(hit.point)

    let target = view.layout.constBox(view.boxOfNode(view.elementById("frame-target-two")))
    Swag.assert(Math.abs(target.rect.y - view.scroll.scrollPosition().y - 60) <= 1)
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
    Swag.assert(hit.found)
    host.click(hit.point)

    Swag.assert(Path.fileName(view.fileName) == "html.local-target.html")
    let target = view.layout.constBox(view.boxOfNode(view.elementById("local-target")))
    Swag.assert(Math.abs(target.rect.y - view.scroll.scrollPosition().y - 68) <= 1)
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
    Swag.assert((expect File.info(path)).size > 1024 * 1024)
    let view = HtmlView.createFile(&host.root, path)
    view.resize(960, 540)
    view.applyLayout()
    view.rebuild()
    Swag.assert(view.isLoading())

    let railNode = findClass(&view.document, "left")
    Swag.assert(railNode != HtmlNoNode)
    var rail = view.boxOfNode(railNode)
    Swag.assert(rail != HtmlNoNode and view.layout.constBox(rail).scrollable)
    Swag.assert(view.elementById("api-reference") == HtmlNoNode)
    Swag.assert(view.navigateToFragment("#api-reference"))
    Swag.assert(view.scrollRegion(rail, 180))

    view.streamStep()
    Swag.assert(view.isLoading())
    rail = view.boxOfNode(findClass(&view.document, "left"))
    Swag.assert(rail != HtmlNoNode and view.layout.constBox(rail).scrollTop == 180)
    Swag.assert(view.elementById("api-reference") != HtmlNoNode)

    let target = view.layout.constBox(view.boxOfNode(view.elementById("api-reference")))
    Swag.assert(Math.abs(target.rect.y - view.scroll.scrollPosition().y - 82) <= 1)

    let headerNode = findClass(&view.document, "site-header")
    let linksNode  = findClass(&view.document, "site-links")
    let header     = view.layout.constBox(view.boxOfNode(headerNode))
    let links      = view.layout.constBox(view.boxOfNode(linksNode))
    Swag.assert(header.rect.height <= 68)
    Swag.assert(!links.children.isEmpty())
    let firstY = view.layout.constBox(links.children[0]).rect.y
    for child in links.children do
        Swag.assert(Math.abs(view.layout.constBox(child).rect.y - firstY) <= 1)

    view.stopLoading()
}

// Pins the generated API page in the browser reference's light palette and wide viewport: the
// overview cut, typography, section ornaments, note fills, and table alignment all pass through
// the production HTML view.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(1660, 1324)
    defer host.shutdown()

    host.theme.setLight()
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

    Swag.assert(!view.isLoading())

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
    Swag.assert(!view.failureReason.isEmpty())
    Swag.assert(!view.isLoading())
}

// A `>` inside a quoted attribute value belongs to the value, not to the tag.
#test
{
    let document = parseDocument("<p><a href=\"#x\" title=\"a > b\" data-note='1 > 0'>link</a> tail</p><p>second</p>")
    let anchor   = findTag(&document, .A)
    Swag.assert(anchor != HtmlNoNode)
    Swag.assert(document.attribute(anchor, "title") == "a > b")
    Swag.assert(document.attribute(anchor, "data-note") == "1 > 0")
    Swag.assert(document.textContent(anchor).toString() == "link")

    var paragraphs = 0'u32
    for index in document.nodes.count where document.constNode(cast(u32) index).tag == .P do
        paragraphs += 1
    Swag.assert(paragraphs == 2)

    // A stray quote outside any value still lets the tag end at its `>`.
    let strays = parseDocument("<p foo\"bar>text</p>")
    let para   = findTag(&strays, .P)
    Swag.assert(para != HtmlNoNode)
    Swag.assert(strays.textContent(para).toString() == "text")
}

// The newline that immediately follows a `<pre>` or `<textarea>` start tag is not content, and
// only that one is dropped.
#test
{
    let document = parseDocument("<pre>\nkeep</pre><pre>\n\ntwo</pre><textarea>\nvalue</textarea>")
    Swag.assert(document.textContent(findNthTag(&document, .Pre, 1)).toString() == "keep")
    Swag.assert(document.textContent(findNthTag(&document, .Pre, 2)).toString() == "\ntwo")
    Swag.assert(document.textContent(findTag(&document, .TextArea)).toString() == "value")

    // A tag between the two keeps the newline: the rule only ever applies to the very next token.
    let nested = parseDocument("<pre><code>\nkept</code></pre>")
    Swag.assert(nested.textContent(findTag(&nested, .Code)).toString() == "\nkept")
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
    while offset < source.count
    {
        let end = Math.min(offset + 3, source.count)
        parser.feed(source[offset until end])
        offset = end
    }

    parser.finish()

    let anchor = findTag(&streamed, .A)
    Swag.assert(streamed.attribute(anchor, "title") == "a > b")
    Swag.assert(streamed.textContent(findTag(&streamed, .Pre)).toString() == "    indented")
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

    let kept     = view.boxOfNode(view.elementById("k"))
    let keptZero = findItemPos(view, kept, "zero")
    let keptFour = findItemPos(view, kept, "four")
    Swag.assert(keptZero.found and keptFour.found)
    Swag.assert(keptFour.y > keptZero.y)

    // The second line starts four monospace spaces in, not at the margin.
    Swag.assert(keptFour.x > keptZero.x + 1)

    let folded     = view.boxOfNode(view.elementById("f"))
    let foldedZero = findItemPos(view, folded, "zero")
    let foldedFour = findItemPos(view, folded, "four")
    Swag.assert(foldedZero.found and foldedFour.found)
    Swag.assert(foldedFour.y > foldedZero.y)
    Swag.assert(Math.abs(foldedFour.x - foldedZero.x) < 0.5)
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
    let a     = view.layout.constBox(view.boxOfNode(view.elementById("a")))
    let b     = view.layout.constBox(view.boxOfNode(view.elementById("b")))
    let c     = view.layout.constBox(view.boxOfNode(view.elementById("c")))
    let d     = view.layout.constBox(view.boxOfNode(view.elementById("d")))

    // Three columns share the row; the fourth item wraps to the next one.
    Swag.assert(a.rect.y == b.rect.y and b.rect.y == c.rect.y)
    Swag.assert(d.rect.y > a.rect.y)
    Swag.assert(Math.abs(a.rect.width - track) <= 0.75)
    Swag.assert(Math.abs(b.rect.x - a.rect.right() - 10) <= 0.75)
    Swag.assert(Math.abs(c.rect.right() - width) <= 0.75)

    let flexible = (width - 200) / 2
    let m1       = view.layout.constBox(view.boxOfNode(view.elementById("m1")))
    let m2       = view.layout.constBox(view.boxOfNode(view.elementById("m2")))
    let m3       = view.layout.constBox(view.boxOfNode(view.elementById("m3")))
    let m4       = view.layout.constBox(view.boxOfNode(view.elementById("m4")))
    Swag.assert(m1.rect.y == m4.rect.y)
    Swag.assert(Math.abs(m1.rect.width - 100) <= 0.75)
    Swag.assert(Math.abs(m2.rect.width - flexible) <= 0.75)
    Swag.assert(Math.abs(m3.rect.width - 100) <= 0.75)
    Swag.assert(Math.abs(m3.rect.x - m2.rect.right()) <= 0.75)
}

// Preserved white space draws the indentation of a code block line by line — the shape every
// `.code-block` region of the generated documentation relies on.
#[Swag.TestTag("golden")]
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
#[Swag.TestTag("golden")]
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

    Swag.assert(!view.isLoading())
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
    Swag.assert(box.content.width == 32 and box.content.height == 32)
    Swag.assert(view.images.entries.count == 1 and view.images.entries[0].loaded)
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
    let declaredText = loadTemporaryDocument(&host, Swag.makeSlice(cast(const [*] u8) declared.buffer!, declared.length), "declared")
    Swag.assert(Utf8.contains(declaredText.toString(), "café"))

    // No declaration: the byte pattern itself says code page 1252.
    var plain: String = "<html><body><p>tr"
    plain.append(0xE8'u8)
    plain += "s vite</p></body></html>"
    let plainText = loadTemporaryDocument(&host, Swag.makeSlice(cast(const [*] u8) plain.buffer!, plain.length), "plain")
    Swag.assert(Utf8.contains(plainText.toString(), "très vite"))

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
    Swag.assert(Utf8.contains(wideText.toString(), "wide text"))
    Swag.assert(!Utf8.contains(wideText.toString(), "ÿþ"))
}

// The flex and grid fixture renders through the production view, pinning wrap, alignment, and
// track sizing as pixels rather than as a handful of sampled rectangles.
#[Swag.TestTag("golden")]
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

    Swag.assert(!view.isLoading())
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
    Swag.assert(bold != HtmlNoNode)
    Swag.assert(document.textContent(bold).toString() == "one two")

    // Two italic elements exist: the original inside the bold, the reopened one after it, and
    // the clone carries the original's attributes.
    let first  = findNthTag(&document, .I, 1)
    let second = findNthTag(&document, .I, 2)
    Swag.assert(first != HtmlNoNode and second != HtmlNoNode)
    Swag.assert(document.constNode(first).parent == bold)
    Swag.assert(document.constNode(second).parent == document.constNode(bold).parent)
    Swag.assert(document.textContent(second).toString() == " three")
    Swag.assert(document.hasClass(second, "x"))

    let para = findTag(&document, .P)
    Swag.assert(document.textContent(para).toString() == "one two three four")
}

// A source that writes no `<html>`, `<head>` or `<body>` is the same document as one that does.
// This is what makes a page's own `body { ... }` rules apply to a fragment.
#test
{
    let document = parseDocument("<style>body { margin: 0 }</style>text<p>content</p>")
    let html     = findTag(&document, .Html)
    let head     = findTag(&document, .Head)
    let body     = findTag(&document, .Body)
    Swag.assert(html != HtmlNoNode and head != HtmlNoNode and body != HtmlNoNode)
    Swag.assert(document.constNode(html).parent == 0)
    Swag.assert(document.constNode(head).parent == html)
    Swag.assert(document.constNode(body).parent == html)

    // A `<style>` belongs to the head, and the text that follows it starts the body.
    Swag.assert(document.constNode(findTag(&document, .Style)).parent == head)
    Swag.assert(document.constNode(findTag(&document, .P)).parent == body)
    Swag.assert(document.textContent(body).toString() == "textcontent")

    // A written section is the section the document already has, whatever a malformed page repeats.
    let written = parseDocument("<html lang='en'><body class='page'><p>one</p></body><p>two</p><body class='again'>")
    Swag.assert(written.constNode(findTag(&written, .Html)).attributes.count == 1)
    let onlyBody = findTag(&written, .Body)
    Swag.assert(written.attribute(onlyBody, "class") == "page")
    for index in written.nodes.count where index != cast(u64) onlyBody do
        Swag.assert(written.constNode(cast(u32) index).tag != .Body)
    Swag.assert(written.textContent(onlyBody).toString() == "onetwo")
}

// Character references resolve against the standard's complete list, including the two-code-point
// ones and the legacy spellings a document writes without their semicolon.
#test
{
    let document = parseDocument("<p>&boxplus; &NotEqualTilde; &copy; &copy 2026 &notit; &unknownref;</p>")
    let text     = document.textContent(findTag(&document, .P))
    Swag.assert(text == "\u229E \u2242\u0338 \u00A9 \u00A9 2026 \u00ACit; &unknownref;")

    // Inside an attribute value a legacy spelling stays literal when a name or an `=` follows it,
    // which is what keeps a query string intact.
    let query = parseDocument("<a href=\"?a=1&copy=2&amp;b=3\" title=\"&copy 2026\">x</a>")
    let link  = findTag(&query, .A)
    Swag.assert(query.attribute(link, "href") == "?a=1&copy=2&b=3")
    Swag.assert(query.attribute(link, "title") == "\u00A9 2026")
}

// The background a document asks for covers the canvas, not just the box that carries it: a page
// that sets a white ground is white everywhere, including under and beside its content.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 120)
    defer host.shutdown()

    let view = HtmlView.createText(&host.root, "<style>body { background: #ff0000 } p { background: #0000ff; margin: 0 }</style><p>x</p>")
    view.resize(160, 120)
    view.applyLayout()
    view.rebuild()

    var image = host.render(view)
    Swag.assert(image.pixelColor(150, 110).argb == 0xFFFF0000)
    Swag.assert(image.pixelColor(4, 4).argb == 0xFFFF0000)

    // The body's own box no longer repaints what the canvas already carries, and the paragraph
    // still paints over it.
    Swag.assert(image.pixelColor(20, 12).argb == 0xFF0000FF)
}

// Content written inside the table structure but outside any cell renders before the table,
// where browsers foster-parent it, and the grid keeps only its rows.
#test
{
    let document = parseDocument("<div><table>stray <b>bold</b><tr><td>cell</td></tr></table></div>")
    let host     = findTag(&document, .Div)
    let table    = findTag(&document, .Table)
    let bold     = findTag(&document, .B)
    Swag.assert(document.constNode(bold).parent == host)

    // Order under the host: the fostered text, the fostered bold run, then the table.
    Swag.assert(document.childCount(host) == 3)
    Swag.assert(document.constNode(document.childAt(host, 0)).kind == .Text)
    Swag.assert(document.textOf(document.childAt(host, 0)) == "stray ")
    Swag.assert(document.childAt(host, 1) == bold)
    Swag.assert(document.childAt(host, 2) == table)

    let cell = findTag(&document, .Td)
    Swag.assert(document.textContent(cell).toString() == "cell")
    Swag.assert(document.textContent(table).toString() == "cell")
}

// A block interrupts a paragraph even through its open inline children: the paragraph closes,
// and the block is its sibling rather than its grandchild.
#test
{
    let document = parseDocument("<p>lead <b>bold<div>block</div>")
    let para     = findTag(&document, .P)
    let block    = findTag(&document, .Div)
    Swag.assert(document.constNode(block).parent == document.constNode(para).parent)
    Swag.assert(document.textContent(para).toString() == "lead bold")
    Swag.assert(document.textContent(block).toString() == "block")
}

// The recoveries hold when the source arrives in chunks that cut every token.
#test
{
    let source = "<div><table>stray<tr><td>cell</td></tr></table></div><p><b>one <i>two</b> three</i></p>"

    var streamed = HtmlDocument.create()
    var parser: HtmlParser
    parser.start(&streamed)

    var offset = 0'u64
    while offset < source.count
    {
        let end = Math.min(offset + 3, source.count)
        parser.feed(source[offset until end])
        offset = end
    }

    parser.finish()

    let host  = findTag(&streamed, .Div)
    let table = findTag(&streamed, .Table)
    Swag.assert(streamed.childCount(host) == 2)
    Swag.assert(streamed.textOf(streamed.childAt(host, 0)) == "stray")
    Swag.assert(streamed.childAt(host, 1) == table)
    Swag.assert(streamed.textContent(table).toString() == "cell")

    let second = findNthTag(&streamed, .I, 2)
    Swag.assert(second != HtmlNoNode)
    Swag.assert(streamed.textContent(second).toString() == " three")
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
    Swag.assert(fig.rect.x == 0 and fig.rect.y == 0)
    Swag.assert(fig.rect.width == 120 and fig.rect.height == 40)

    let para = view.boxOfNode(view.elementById("t"))
    Swag.assert(view.layout.constBox(para).rect.y == 0)

    // Lines beside the float start at its right edge; the forced last line, well past the
    // float's bottom, returns to the margin.
    let beside = findItemPos(view, para, "first")
    Swag.assert(beside.found and beside.x >= 120)
    Swag.assert(beside.y < 40)
    let below = findItemPos(view, para, "last")
    Swag.assert(below.found and below.x < 1)
    Swag.assert(below.y >= 38)

    // The cleared box starts below the float's bottom rather than at the flow position.
    let cleared = view.layout.constBox(view.boxOfNode(view.elementById("c")))
    Swag.assert(cleared.rect.y >= 40)
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
    Swag.assert(fig.rect.y == 0)
    Swag.assert(Math.abs(fig.rect.right() - 400) <= 0.5)
    Swag.assert(fig.rect.width == 120)

    let first = findItemPos(view, view.boxOfNode(view.elementById("t")), "first")
    Swag.assert(first.found and first.x < 1 and first.y < 40)
}

// The classic article arrangement as pixels: a floated figure, the text wrapping beside it and
// returning to the full measure below, and a cleared footer starting under the float.
#[Swag.TestTag("golden")]
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
    Swag.assert(view.layout.constBox(box).lines.count >= 2)
    Swag.assert(maxItemRight(view, box) <= 120.5)
    Swag.assert(countTextItems(view, box) >= 2)

    // The split fragments merge back once the measure is wide enough for the whole run.
    view.resize(800, 600)
    view.applyLayout()
    view.placeDocument()
    Swag.assert(view.layout.constBox(box).lines.count == 1)
    Swag.assert(countTextItems(view, box) == 1)
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
    Swag.assert(view.layout.constBox(box).lines.count >= 2)
    Swag.assert(maxItemRight(view, box) <= 100.5)

    // `word-break: keep-all` restores the unbreakable run.
    let keep = HtmlView.createText(&host.root, "<style>body { margin: 0 } p { margin: 0; width: 100px; word-break: keep-all }</style><p id=\"c\">法国是一个位于西欧的国家法国是一个位于西欧的国家</p>")
    keep.resize(400, 300)
    keep.applyLayout()
    keep.rebuild()
    Swag.assert(countTextItems(keep, keep.boxOfNode(keep.elementById("c"))) == 1)
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
    Swag.assert(view.layout.constBox(box).lines.count >= 2)
    Swag.assert(maxItemRight(view, box) <= 120.5)
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
    Swag.assert(first.found and second.found)
    Swag.assert(second.y > first.y)

    // The soft hyphen leaves the run, breaks it, and the head fragment draws its hyphen.
    let hyphenated = view.boxOfNode(view.elementById("s"))
    Swag.assert(view.layout.constBox(hyphenated).lines.count == 2)
    var sawHyphen: bool
    for item in view.layout.constBox(hyphenated).items where item.kind == .Text and item.text.toString() == "cccccccccc"
    {
        sawHyphen = item.hyphenAtBreak
        break
    }

    Swag.assert(sawHyphen)

    // A soft hyphen where no break is needed draws nothing and the line stays whole.
    let whole = view.boxOfNode(view.elementById("n"))
    Swag.assert(view.layout.constBox(whole).lines.count == 1)
    for item in view.layout.constBox(whole).items do
        Swag.assert(!item.hyphenAtBreak)
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
    Swag.assert(styled.italic)
    Swag.assert(styled.fontWeight == 700)
    Swag.assert(styled.fontSize == 20)
    Swag.assert(styled.lineHeight.kind == .Percent and styled.lineHeight.value == 2)
    Swag.assert(styled.fontFamily == .Mono)

    var spaced, plain: f32
    for item in view.layout.constBox(view.boxOfNode(view.elementById("ws"))).items where item.kind == .Space do
        spaced = item.width
    for item in view.layout.constBox(view.boxOfNode(view.elementById("nb"))).items where item.kind == .Space do
        plain = item.width
    Swag.assert(plain > 0)
    Swag.assert(Math.abs(spaced - plain - 10) <= 0.01)
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
    Swag.assert(closeColor(htmlParseColor("oklch(0.62796 0.25768 29.234)"), 0xFFFF0000))
    Swag.assert(closeColor(htmlParseColor("oklab(0.62796 0.22486 0.12585)"), 0xFFFF0000))
    Swag.assert(closeColor(htmlParseColor("oklch(100% 0 0)"), 0xFFFFFFFF))
    Swag.assert(closeColor(htmlParseColor("lab(54.29 80.805 69.891)"), 0xFFFF0000))
    Swag.assert(closeColor(htmlParseColor("lch(54.29 106.84 40.858)"), 0xFFFF0000))
    Swag.assert(closeColor(htmlParseColor("hwb(120 0% 0%)"), 0xFF00FF00))
    Swag.assert(closeColor(htmlParseColor("hwb(0 100% 0%)"), 0xFFFFFFFF))
    Swag.assert(closeColor(htmlParseColor("hwb(0 40% 60%)"), 0xFF666666))
    Swag.assert(closeColor(htmlParseColor("color(srgb 1 0 0)"), 0xFFFF0000))
    Swag.assert(closeColor(htmlParseColor("color(srgb-linear 1 0 0)"), 0xFFFF0000))
    Swag.assert(closeColor(htmlParseColor("color(display-p3 1 0 0)"), 0xFFFF0000, 12))
    Swag.assert(closeColor(htmlParseColor("hsl(0.5turn 100% 50%)"), 0xFF00FFFF))
    Swag.assert(closeColor(htmlParseColor("hsl(3.14159rad 100% 50%)"), 0xFF00FFFF))

    // Alpha rides behind the slash whatever the notation.
    let translucent = htmlParseColor("oklch(0.62796 0.25768 29.234 / 50%)")
    Swag.assert(translucent.matched and Math.abs(cast(s32) translucent.color.a - 128) <= 1)

    // An out-of-gamut color clamps to the gamut edge instead of wrapping.
    let vivid = htmlParseColor("oklch(0.9 0.37 145)")
    Swag.assert(vivid.matched and vivid.color.g == 255)

    // An unknown color space is refused, so the cascade keeps its previous value.
    Swag.assert(!htmlParseColor("color(rec2020 1 0 0)").matched)
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
        Swag.assert(style.color == ((wanted + 1) % 3 == 0 ? red : black))
        Swag.assert(style.fontWeight == (wanted < 2 ? 700 : 400))
    }

    Swag.assert(view.layout.styleOfNode(findNthTag(&view.document, .P, 1)).color != Pixel.Color.fromArgb(0xFF00FF00))
    Swag.assert(view.layout.styleOfNode(findNthTag(&view.document, .P, 2)).color == Pixel.Color.fromArgb(0xFF00FF00))
    Swag.assert(view.layout.styleOfNode(findNthTag(&view.document, .Span, 1)).color == Pixel.Color.fromArgb(0xFF0000FF))
    Swag.assert(view.layout.styleOfNode(findNthTag(&view.document, .Span, 2)).color != Pixel.Color.fromArgb(0xFF0000FF))
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
    Swag.assert(Utf8.contains(document.textContent(0).toString(), "deep text"))

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

    Swag.assert(deepest <= HtmlMaxElementDepth + 1)

    // The whole pipeline survives the same document: styling, box building, layout, painting.
    var host: Testing.HeadlessHost
    host.setup(320, 240)
    defer host.shutdown()

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(320, 240)
    view.applyLayout()
    view.rebuild()
    discard host.render(view)
    Swag.assert(Utf8.contains(view.document.textContent(0).toString(), "deep text"))
}

// Returns the canvas rectangle of the first inline item drawn with `text`.
func findItemRect(view: *HtmlView, text: string)->Math.Rectangle
{
    for boxIndex in view.layout.boxes.count
    {
        let box = view.layout.constBox(cast(u32) boxIndex)
        for itemIndex in box.items.count
        {
            let item = &box.items[itemIndex]
            if item.text == text do
                return {item.x, item.y, item.width, item.ascent + item.descent}
        }
    }

    return {}
}

// Select-all covers the whole document, extraction keeps the reading order, and the clipboard
// receives exactly what the reader sees.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 480)
    defer host.shutdown()

    let view = HtmlView.createText(&host.root, "<p>alpha beta</p><p>gamma delta</p>")
    view.resize(640, 480)
    view.applyLayout()
    view.rebuild()

    Swag.assert(!view.hasSelection())
    view.selectAll()
    Swag.assert(view.hasSelection())
    Swag.assert(view.selectedText() == "alpha beta\ngamma delta")
    Swag.assert(view.copySelection())
    Swag.assert(Clipboard.getString() == "alpha beta\ngamma delta")

    view.clearSelection()
    Swag.assert(!view.hasSelection())
    Swag.assert(!view.copySelection())
}

// A mouse drag selects what it crosses, and a double click takes the word under the pointer.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 480)
    defer host.shutdown()

    let view = HtmlView.createText(&host.root, "<p>alpha beta gamma</p>")
    view.resize(640, 480)
    view.applyLayout()
    view.rebuild()

    let alpha = findItemRect(view, "alpha")
    let gamma = findItemRect(view, "gamma")
    Swag.assert(alpha.width > 0 and gamma.width > 0)

    let dragFrom = view.canvas.localToSurface(Math.Point{alpha.x + 1, alpha.vertCenter()})
    let dragTo   = view.canvas.localToSurface(Math.Point{gamma.right() - 1, gamma.vertCenter()})
    host.drag(dragFrom, dragTo)
    Swag.assert(view.selectedText() == "alpha beta gamma")

    host.doubleClick(view.canvas.localToSurface(Math.Point{alpha.horzCenter(), alpha.vertCenter()}))
    Swag.assert(view.selectedText() == "alpha")
}

// The context menu reaches the same selection commands the keyboard binds.
#test
{
    var host: Testing.HeadlessHost
    host.setup(640, 480)
    defer host.shutdown()

    let view = HtmlView.createText(&host.root, "<p>menu content</p>")
    view.resize(640, 480)
    view.applyLayout()
    view.rebuild()

    host.clickPopupMenuItemWhenShown(HtmlView.CtxSelectAll)
    view.showContextMenu({50, 50})
    host.pump()
    Swag.assert(view.selectedText() == "menu content")

    host.clickPopupMenuItemWhenShown(HtmlView.CtxCopy)
    view.showContextMenu({50, 50})
    host.pump()
    Swag.assert(Clipboard.getString() == "menu content")
}
