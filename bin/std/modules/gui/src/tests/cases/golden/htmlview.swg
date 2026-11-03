#global if #command == Swag.CompilerCommand.Test
#global internal

using Core, Pixel

// The virtual HTML window is refreshed in advance in both directions. A delayed timer still
// cannot leave the viewport outside the materialized layout on the next paint.

// SVG image dimensions come from the root attributes; CSS dimensions can override them.

// Large square figures obey the area budget as well as the longest-side limit.

// Every offline resource path uses the same lexical boundary before filesystem access.

func guiFixturePath(name: string)->String => Path.combine(testSourceRoot(#curlocation), Format.toString("datas/%", name).toString())

func htmlFixturePath()->String => guiFixturePath("html.comprehensive.html")

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
    for index in document.nodes.count where document.constNode(cast(u32, index)).tag == tag do
        return cast(u32, index)
    return HtmlNoNode
}

// Returns the first element carrying a class used to name fixture structure.
func findClass(document: const *HtmlDocument, name: string)->u32
{
    for index in document.nodes.count where document.hasClass(cast(u32, index), name) do
        return cast(u32, index)
    return HtmlNoNode
}

// Returns the position of the first laid-out text item matching `text` inside a box.
func findItemPos(view: *HtmlView, box: u32, text: string)->{ x: f32, y: f32, found: bool }
{
    var result: #returntype
    for item in view.layout.constBox(box).items
    {
        if item.kind != .Text or view.layout.inlineText(item) != text do
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
    for index in document.nodes.count where document.constNode(cast(u32, index)).tag == tag
    {
        seen += 1
        if seen == wanted do
            return cast(u32, index)
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

    Swag.assert(not view.isLoading())
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
    var result: #returntype
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

// Character references decode to their code points, including the numeric forms.

// A raw-text element never contributes markup, whatever it contains.

// Reading a document in chunks produces the tree the whole source produces.

// The cascade orders declarations by importance, then specificity, then source order, and
// resolves the custom properties a document defines.

// Unsupported complex functional selectors cannot silently become their first compound.

// Lengths read every unit a document uses, and math expressions keep what layout must resolve.

// Polygonal clip paths remain paintable decorations rather than being treated as unsupported
// masks, which is what gives documentation overview cards their cut corners and visible fill.

// Every color notation a document uses reads back as the same paint.

// Blocks stack with collapsed margins, and a grid places its children over its declared tracks.

// A flex row shares what is left over between the items that grow.

// Text wraps into as many lines as the measure allows, and a forced break starts a new one.

// A terminal preserved newline ends the last line without creating another blank line.

// A block stays inside the measure its ancestors set, however deep it sits.

// A table sizes its columns from what their cells need.

// A table cell aligns its contents inside the row height established by a taller sibling.

// A bounded overflow region moves its own contents and never paints them outside its viewport.

// A tall inline image remains paintable after its typographic origin has left the viewport.

// A CSS region scrollbar pages through its track and drags its thumb like a native vertical bar.

// A viewport-relative rail has a definite height even though its document parent grows with its
// content. This is the two-pane shape used by generated module pages: the outer view owns the
// page scrollbar while the rail consumes the wheel independently.

// A positive z-index keeps a sticky header above siblings that occur later in the document.

// The complete fixture renders, and nothing a document hides reaches the drawn text.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)

    let view = HtmlView.createText(&host.root, (expect File.readAllText(htmlFixturePath())).toString())
    view.resize(960, 680)
    view.applyLayout()
    view.rebuild()

    let text = view.document.textContent(0)
    Swag.assert(Utf8.contains(text.toString(), "Heading level one"))
    Swag.assert(Utf8.contains(text.toString(), "The distant html verification marker"))
    Swag.assert(not Utf8.contains(text.toString(), "must not render"))

    // A hidden container is parsed and then left out of the box tree entirely.
    for index in view.layout.boxes.count
    {
        let node = view.layout.constBox(cast(u32, index)).node
        if node == HtmlNoNode do
            continue
        Swag.assert(view.document.constNode(node).tag != .Script)
        Swag.assert(view.document.constNode(node).tag != .Template)
    }

    Swag.assert(view.layout.documentHeight > 680)

    var image = host.renderSettled(view)
    Pixel.Testing.assertImageGolden(&image, "htmlview.document")
}

// A search over a streamed document lands on the box that draws the match, wherever it is in the
// file and however much of it has been read.

// Progressive refreshes spread out fourfold, so a large generated page does not repeatedly
// rebuild almost the same prefix while the reader is still interacting with it.

// Inline runs share one build arena, so retaining a paragraph costs storage proportional to its
// bytes rather than one allocator block per word.

// Painting a search hit survives every split of the match across inline items: an item that
// begins inside the hit has an empty prefix, which must never reach String.opSlice.

// A source-backed reveal marks the requested occurrence, not the first equal word in its node.

// A real generated Rustdoc page keeps its full production scale. Its highlighted source expands
// to hundreds of thousands of nodes, and its structural selectors used to rescan tens of
// thousands of siblings for each match. Small documents cannot expose that failure mode.

// Large ordinary HTML is bounded too, even when it has no generated-source `<pre>` shape. The
// generic window may start at a recovery boundary, but it must never make file size become DOM
// size and revisiting one byte offset must choose the same resident source.

// What a scroll position shows does not depend on how the reader got there.
//
// This is the contract the previous viewer could not keep: its scroll-to-byte estimate changed as
// it moved the resident source window, so travelling with the scrollbar rewrote the text and
// sometimes emptied the page. A virtual window must map a position deterministically.

// A virtual HTML document follows the latest scrollbar position through repeated long seeks and
// reversals. Revisiting a stop must materialize the same source window and the same pixels.

// The focused document answers the whole keyboard scrolling contract.

// Reports whether a vertical run of one column holds the exact color.
func columnHasColor(image: *Pixel.Image, x: s32, y0, y1: s32, argb: u32)->bool
{
    for y in y0 until y1 where image.pixelColor(x, y).argb == argb do
        return true
    return false
}

// Reports whether a horizontal run of one row holds the exact color.
func rowHasColor(image: *Pixel.Image, y: s32, x0, x1: s32, argb: u32)->bool
{
    for x in x0 until x1 where image.pixelColor(x, y).argb == argb do
        return true
    return false
}

// Each corner rounds by its own radius. A box that rounds one corner keeps the other three
// square rather than taking the largest radius everywhere.

// A rounded box whose sides carry different colours keeps each side's own colour. One stroke
// cannot do that, so such a box is drawn side by side, with square corners as the documented
// approximation.

// A box whose four sides agree is still drawn as one rounded ring, on every side.

// A percentage height resolves against a parent that has one, down a whole chain of them, and
// still falls back to content height where nothing definite stands above it.

// A positioned box answers to the nearest positioned ancestor, not to whatever box happens to
// hold it. The badge of a card is the shape this is written for: `position: relative` on the card,
// `position: absolute` on the badge two levels down.

// Two automatic insets keep a positioned box where the flow would have put it, rather than
// collapsing it onto the edge of its containing block.

// A positioned child of a flex or grid container is laid out like any other positioned box. It
// takes no part in the container's own line, but it is placed and sized.

// A positioned span written in the middle of a paragraph splits that paragraph's text into
// anonymous blocks. The box still answers to the card, not to the paragraph it was written in.

// A positioned box with no positioned ancestor resolves against the initial containing block:
// the top of the document, and the viewport's width.

// An absolutely positioned generated rule is a box of its own, and a functional color paints it.

// Every checked-in HTML fixture is a complete document that the streaming parser accepts.

// A flexible documentation header keeps all navigation links on its single browser-sized row.

// The left frame owns wheel input under the pointer at every page position, including when its
// own scrollbar is already at an edge. The document owns wheel input only over the right frame.

// Clicking a fragment in the independently scrolled rail positions its target after the CSS
// scroll margin instead of hiding it under the sticky header.

// A relative local link replaces the displayed file and follows its fragment in the new page.

// The generated Pixel API page stays progressive, preserves its independently scrolled rail
// across partial rebuilds, resolves a fragment from the next chunk, and keeps the browser's
// one-line header. The test deliberately stops after that third 48 KiB chunk: exercising a
// progressive frame must not turn every GUI configuration into a full megabyte-layout benchmark.

// Pins the generated API page in the browser reference's light palette and wide viewport: the
// overview cut, typography, section ornaments, note fills, and table alignment all pass through
// the production HTML view.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(1660, 1324)

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

    Swag.assert(not view.isLoading())

    var image = host.render(view)
    Pixel.Testing.assertImageGolden(&image, "htmlview.pixel-api")
    view.stopLoading()
}

// A file-open failure stays inspectable even when no observer was connected during construction.

// A `>` inside a quoted attribute value belongs to the value, not to the tag.

// The newline that immediately follows a `<pre>` or `<textarea>` start tag is not content, and
// only that one is dropped.

// Both fixes hold when the source arrives in chunks that cut a quoted value and a dropped
// newline at every awkward position.

// Preserved white space keeps the indentation a code line starts with; collapsed white space
// still drops it. This is the shape of every `.code-block` the generated documentation draws.

// `repeat()` expands to its full track list, alone and mixed with plain tracks.

// Preserved white space draws the indentation of a code block line by line — the shape every
// `.code-block` region of the generated documentation relies on.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 220)

    var source: String = "<style>body { margin: 0; background: #ffffff }"
    source += ".code { margin: 12px; padding: 10px; background: #eef2f6; border: 1px solid #90a0b0; font-family: monospace; font-size: 14px; white-space: pre; color: #102030 }"
    source += "</style>"
    source += "<div class=\"code\">func demo()\n{\n    if ready\n        run(1)\n}</div>"

    let view = HtmlView.createText(&host.root, source.toString())
    view.resize(360, 220)
    view.applyLayout()
    view.rebuild()

    var image = host.renderSettled(view)
    Pixel.Testing.assertImageGolden(&image, "htmlview.preserved-whitespace")
}

// The tables fixture renders through the production view, so a column-sizing or cell-alignment
// regression lands in this image before any reader sees it.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 680)

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

    Swag.assert(not view.isLoading())
    var image = host.renderSettled(view)
    Pixel.Testing.assertImageGolden(&image, "htmlview.tables")
}

// An image embedded in the document as a `data:` URI decodes like a file image, so a
// self-contained export shows its figures. The payload is the pixel module's own fixture.

// A document's bytes decide its decoding: a `charset=` declaration, a byte-order mark, or the
// content itself. Assuming UTF-8 used to refuse every legacy page outright.

// The flex and grid fixture renders through the production view, pinning wrap, alignment, and
// track sizing as pixels rather than as a handful of sampled rectangles.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(960, 540)

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

    Swag.assert(not view.isLoading())
    var image = host.renderSettled(view)
    Pixel.Testing.assertImageGolden(&image, "htmlview.flex-grid")
}

// Misnested formatting keeps its formatting: the close that pops an inline ancestor reopens the
// formatting elements it swallowed, the way every browser recovers `<b>one <i>two</b> three</i>`.

// A source that writes no `<html>`, `<head>` or `<body>` is the same document as one that does.
// This is what makes a page's own `body { ... }` rules apply to a fragment.

// Character references resolve against the standard's complete list, including the two-code-point
// ones and the legacy spellings a document writes without their semicolon.

// The background a document asks for covers the canvas, not just the box that carries it: a page
// that sets a white ground is white everywhere, including under and beside its content.

// Content written inside the table structure but outside any cell renders before the table,
// where browsers foster-parent it, and the grid keeps only its rows.

// A block interrupts a paragraph even through its open inline children: the paragraph closes,
// and the block is its sibling rather than its grandchild.

// The recoveries hold when the source arrives in chunks that cut every token.

// A left float leaves the stack: the lines beside it shorten, the flow returns to the margin
// below it, and `clear` starts below the floats it names.

// A right float hugs the right edge, and the text keeps the left one.

// The classic article arrangement as pixels: a floated figure, the text wrapping beside it and
// returning to the full measure below, and a cleared footer starting under the float.
#[Swag.TestTag("golden")]
#test
{
    var host: Testing.HeadlessHost
    host.setup(360, 240)

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

    var image = host.renderSettled(view)
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

// CJK text carries no spaces: every character is a break opportunity, and the paragraph stays
// inside its column instead of overflowing it as one run.

// `word-break: break-all` fills each line to its edge, splitting the run mid-word.

// `<wbr>` marks a soft break opportunity, and `&shy;` breaks with a visible hyphen only where
// the break was taken.

// The `font` shorthand expands into its longhands, including the `/line-height` form, and
// `word-spacing` widens each space of the line.

// Reports whether a parsed color lands within a small tolerance of an expected paint, which is
// what a conversion through another color space can promise.
func closeColor(value: HtmlColorValue, argb: u32, tolerance = 3's32)->bool
{
    if not value.matched do
        return false

    let expected = Pixel.Color.fromArgb(argb)
    let dr       = Math.abs(cast(s32, value.color.r) - cast(s32, expected.r))
    let dg       = Math.abs(cast(s32, value.color.g) - cast(s32, expected.g))
    let db       = Math.abs(cast(s32, value.color.b) - cast(s32, expected.b))
    let da       = Math.abs(cast(s32, value.color.a) - cast(s32, expected.a))
    return dr <= tolerance and dg <= tolerance and db <= tolerance and da <= tolerance
}

// The modern color notations convert to sRGB: the OK family, the Lab family, `hwb()`, the
// `color()` function, and hue units other than degrees.

// The full `an+b` grammar matches, and the `-of-type` selectors count within their type.

// A hostile document nested thousands of elements deep flattens at the depth bound instead of
// walking the recursive passes off the native stack, and its content stays readable.

// Returns the canvas rectangle of the first inline item drawn with `text`.
func findItemRect(view: *HtmlView, text: string)->Math.Rectangle
{
    for boxIndex in view.layout.boxes.count
    {
        let box = view.layout.constBox(cast(u32, boxIndex))
        for itemIndex in box.items.count
        {
            let item = &box.items[itemIndex]
            if view.layout.inlineText(item) == text do
                return Math.Rectangle{item.x, item.y, item.width, item.ascent + item.descent}
        }
    }

    return {}
}

// Select-all covers the whole document, extraction keeps the reading order, and the clipboard
// receives exactly what the reader sees.

// A mouse drag selects what it crosses, and a double click takes the word under the pointer.

// The context menu reaches the same selection commands the keyboard binds.
