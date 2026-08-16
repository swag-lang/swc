#global public

using Core, Pixel

// Bytes read from disk per streaming step. Large enough that a multi-megabyte document is read
// in a handful of frames, small enough that a frame is never held for it.
private const HtmlStreamChunkSize = 256 * 1024'u64

// Wall-clock budget one streaming step may spend, so the window keeps answering while a document
// loads.
private const HtmlStreamFrameBudget = 6_000'u64

// Source bytes read before the first partial rendering. The threshold then grows fourfold at each
// one, so a document shows its beginning quickly and the intermediate passes stay a bounded share
// of the whole load instead of repeating once per chunk.
private const HtmlFirstRefreshSize = 192 * 1024'u64

// The largest document the engine keeps in memory. Past it the reader is told the file was cut
// rather than shown a rendering that silently drops content.
private const HtmlMaxDocumentSize = 48 * 1024 * 1024'u64

// Controls the typography an [[Gui.HtmlView]] starts from.
//
// These are the values a document inherits before its own CSS has a say — what a browser calls
// its default font settings. A document that specifies nothing is drawn with them, and one that
// specifies everything is unaffected by them.
public struct HtmlStyle
{
    public
    {
        bodyFontSize:    u32 = 16       // Default body-text size, in logical pixels.
        codeFontSize:    u32 = 14       // Default size for monospaced text, in logical pixels.
        maxContentWidth: f32 = 0        // Reading measure imposed on a document that sets none; `0` follows the document.
        followTheme          = true     // Whether default colors and the color scheme come from the GUI theme.
    }
}

public impl HtmlStyle
{
    // Returns the document defaults that follow the active GUI theme.
    func theme()->HtmlStyle => {}
}

// The surface an [[Gui.HtmlView]] draws its document on.
#[Swag.NoDoc]
struct HtmlCanvas
{
    using wnd: Wnd

    #[Swag.Late]
    owner: *HtmlView
}

// Displays HTML as a laid-out document.
//
// [[Gui.HtmlView.createText]] renders in-memory source, and [[Gui.HtmlView.createFile]] streams a
// file and follows the stylesheets it links to, relative to its folder. Rendering stays offline:
// no script runs, and no reference outside the document's own folder is fetched.
//
// The document is parsed into a tree, styled through a real CSS cascade, and laid out into boxes,
// so a page keeps its columns, its tables, its inline styling, and the regions it scrolls on its
// own.
//
// ```swag
// let document = HtmlView.createFile(parent, "manual.html")
// document.sigLinkActivated += func(view, url)
// {
//     discard view
//     Console.println(url)
// }
// ```
public struct HtmlView
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        sigLinkActivated: SigArray'func||(*HtmlView, string)     // Emitted when a rendered link is activated.

        public readonly
        documentStyle: HtmlStyle     // Typography a document inherits before its own CSS applies.
    }

    internal
    {
        #[Swag.Late]
        {
            scroll: *ScrollWnd
            canvas: *HtmlCanvas
        }

        document: HtmlDocument
        parser:   HtmlParser
        sheet:    HtmlStyleSheet
        pool:     HtmlValuePool
        resolver: HtmlStyleResolver
        layout:   HtmlLayout
        images:   HtmlImageCache

        stream:      File.FileStream
        fileName:    String
        bytesRead:   u64
        sourceDone:  bool
        loadTimer:   #null *Timer
        nextRefresh: u64

        pendingSearch: String
        revealOffset:  u64
        hasReveal:     bool
        searchNode = HtmlNoNode
        hovered    = HtmlNoNode
    }
}

internal func scrollDocumentWithKey(scroll: *ScrollWnd, evt: *KeyEvent)->bool
{
    if evt.kind != .Pressed do
        return false

    let position = scroll.scrollPosition()
    let viewport = scroll.paddedClientRect()
    let page     = Math.max(viewport.height - scroll.verticalScrollStep, scroll.verticalScrollStep)
    var target   = position.y
    switch evt.key
    {
    case .Up where evt.modifiers == .None:                                target -= scroll.verticalScrollStep
    case .Down where evt.modifiers == .None:                              target += scroll.verticalScrollStep
    case .PageUp where evt.modifiers == .None:                            target -= page
    case .PageDown where evt.modifiers == .None:                          target += page
    case .Home where evt.modifiers == .None or evt.modifiers == .Control: target = 0
    case .End where evt.modifiers == .None or evt.modifiers == .Control:  target = scroll.scrollableClientRect().height
    case .Space where evt.modifiers == .None:                             target += page
    case .Space where evt.modifiers == .Shift:                            target -= page
    default: return false
    }

    scroll.setScrollPos(position.x, target)
    return true
}

internal impl HtmlView
{
    // Returns the colors a document inherits when it names none of its own.
    mtd styleDefaults()->HtmlStyleDefaults
    {
        var result: retval
        let colors = .themeColors()
        result.text           = colors.label_Text
        result.faintText      = colors.label_TextFaint
        result.background     = colors.view_Bk
        result.codeBackground = colors.edit_Bk
        result.link           = colors.url_Text
        result.border         = colors.edit_Border
        result.selection      = colors.edit_SelectedBk
        result.fontSize       = cast(f32) .documentStyle.bodyFontSize
        result.monoFontSize   = cast(f32) .documentStyle.codeFontSize
        return result
    }

    // Reports whether the host palette reads as a dark one, which is the answer a document's
    // `prefers-color-scheme` query gets.
    mtd darkScheme()->bool
    {
        let ground = .themeColors().view_Bk
        let luma   = (cast(u32) ground.r * 299 + cast(u32) ground.g * 587 + cast(u32) ground.b * 114) / 1000
        return luma < 128
    }

    // Reports whether source remains to be read.
    public mtd const isLoading()->bool => !.sourceDone

    mtd viewportSize()->Math.Point
    {
        let rect = .scroll.paddedClientRect()
        return {Math.max(rect.width, 1), Math.max(rect.height, 1)}
    }

    // Collects the stylesheets a document carries, in the order it declares them.
    mtd collectStyleSheets()
    {
        .sheet.clear()
        .pool.clear()
        .appendStyleSheets(0)

        // A reading measure the host asked for behaves like a user stylesheet: it applies before
        // anything the document says, so a page that sets its own width still wins.
        if .documentStyle.maxContentWidth > 0 do
            .sheet.parse(Format.toString("body { max-width: %px; margin-left: auto; margin-right: auto }", .documentStyle.maxContentWidth).toString())
    }

    private mtd appendStyleSheets(node: u32)
    {
        let current = .document.constNode(node)
        if current.kind == .Element
        {
            if current.tag == .Style
            {
                var css: String
                for child in current.children where .document.constNode(child).kind == .Text do
                    css += .document.constNode(child).text
                .sheet.parse(css.toString())
                return
            }

            if current.tag == .Link and .isStyleSheetLink(node)
            {
                .appendExternalStyleSheet(.document.attribute(node, "href"))
                return
            }
        }

        for child in current.children do
            .appendStyleSheets(child)
    }

    private mtd isStyleSheetLink(node: u32)->bool
    {
        for part in Tokenize.split(.document.attribute(node, "rel"), ' 'u8) where Utf8.compare(part, "stylesheet", .Latin1NoCase) == 0 do
            return true
        return false
    }

    // Reads a linked stylesheet from the folder the document was read from.
    //
    // Only a relative or absolute local path is followed; a document is displayed without
    // reaching the network, whatever it links to.
    private mtd appendExternalStyleSheet(href: string)
    {
        if !@countof(href) or .images.basePath.isEmpty() do
            return
        if Utf8.contains(href, "://") or Utf8.startsWith(href, "//") or Utf8.startsWith(href, "data:") do
            return

        let fileName = Path.isRooted(href) ? String.from(href) : Path.combine(.images.basePath.toString(), href)
        let content  = catch File.readAllText(fileName.toString()) as readError
        if readError != null do
            return
        .sheet.parse(content.toString())
    }

    // Recomputes styles and boxes, then places them.
    mtd rebuild()
    {
        let viewport = .viewportSize()

        // Text is measured against the grid it will be drawn on, so the display scale has to be
        // known before the first word is measured.
        let surface = .surface
        if surface do
            .layout.deviceScale = surface!.dpiScale
        .collectStyleSheets()
        .resolver.resolve(&.document, &.sheet, &.pool, .styleDefaults(), viewport, .darkScheme())
        .layout.build(&.document, &.resolver, .theme(), &.images)
        .applyLayout()
        .placeDocument()
    }

    // Runs the layout for the current viewport and updates what can be scrolled.
    mtd placeDocument()
    {
        let viewport = .viewportSize()
        if .layout.root == HtmlNoNode do
            return

        .layout.layout(viewport.x, viewport.y)

        // The canvas is one viewport tall whatever the document measures, and the paint applies
        // the scroll offset itself. A window as tall as the document would be a window of a
        // quarter of a million pixels, which is not a shape the surface geometry is built for.
        let height   = Math.max(.layout.documentHeight, viewport.y)
        let position = .scroll.scrollPosition()
        .canvas.setPosition({0, 0, viewport.x, viewport.y})
        .scroll.setScrollSize(viewport.x, height)
        .scroll.setScrollPos(position)
        .scroll.verticalScrollStep = Math.max(cast(f32) .documentStyle.bodyFontSize * 3, 24)
        .canvas.invalidate()
    }

    // Feeds one bounded batch of source into the parser.
    mtd streamStep()
    {
        var stopwatch: Time.Stopwatch
        stopwatch.start()

        while !.sourceDone
        {
            let chunk = catch .stream.readUtf8Chunk(HtmlStreamChunkSize) as readError
            if readError != null
            {
                .finishSource("<p>Unable to read this HTML document.</p>")
                break
            }

            if chunk.isEmpty()
            {
                .finishSource("")
                break
            }

            .parser.feed(chunk.toString())
            .bytesRead += chunk.length
            if .bytesRead >= HtmlMaxDocumentSize
            {
                .finishSource("<p>This document is too large to be displayed in full; the rest of the file was not read.</p>")
                break
            }

            if stopwatch.elapsedMicroseconds() >= HtmlStreamFrameBudget do
                break
        }

        // A partial rendering is produced at growing intervals, so a long document shows its
        // beginning quickly without paying for a full pass on every chunk.
        if .sourceDone or .bytesRead >= .nextRefresh
        {
            if !.sourceDone do
                .nextRefresh = .bytesRead * 4
            .rebuild()
            .resolvePending()
        }

        if !.sourceDone do
            .scheduleMore()
    }

    private mtd finishSource(notice: string)
    {
        if @countof(notice) do
            .parser.feed(notice)
        .parser.finish()
        .sourceDone = true
        .stream.close()
    }

    mtd scheduleMore()
    {
        if .loadTimer or .sourceDone do
            return
        .loadTimer = .addTimer(4'ms)
    }

    mtd stopLoading()
    {
        if .loadTimer
        {
            .removeTimer(.loadTimer!)
            .loadTimer = null
        }

        .stream.close()
    }

    // Acts on a search or a reveal that was waiting for the bytes it needs.
    private mtd resolvePending()
    {
        if .hasReveal and (.sourceDone or .revealOffset < .bytesRead)
        {
            .hasReveal = false
            discard .scrollToNode(.nodeAtSourceOffset(.revealOffset))
        }

        if !.pendingSearch.isEmpty() and .findText(.pendingSearch.toString()) do
            .pendingSearch.clear()
    }

    // Returns the node the given byte offset of the source belongs to.
    mtd const nodeAtSourceOffset(offset: u64)->u32
    {
        var best       = HtmlNoNode
        var bestOffset = 0'u64
        for index in .document.nodes.count
        {
            let node = .document.constNode(cast(u32) index)
            if node.kind == .Document or node.sourceOffset > offset do
                continue
            if best != HtmlNoNode and node.sourceOffset < bestOffset do
                continue
            best       = cast(u32) index
            bestOffset = node.sourceOffset
        }

        return best
    }

    // Returns the element carrying an identifier, or `HtmlNoNode` when the document has none.
    public mtd const elementById(id: string)->u32
    {
        if !@countof(id) do
            return HtmlNoNode
        for index in .document.nodes.count where .document.constNode(cast(u32) index).id == id do
            return cast(u32) index
        return HtmlNoNode
    }

    // Scrolls to the element a document-internal reference names.
    //
    // Returns false when the reference points outside the document, which is what tells the
    // caller to treat the link as a destination of its own.
    public mtd navigateToFragment(url: string)->bool
    {
        let hash = Utf8.indexOf(url, '#'rune)
        if hash != 0 do
            return false
        return .scrollToNode(.elementById(url[1 to]))
    }

    // Returns the box that draws a node, walking up to the element that contains it.
    mtd const boxOfNode(node: u32)->u32
    {
        var walk = node
        while walk != HtmlNoNode
        {
            let found = .layout.nodeBox.tryFind(walk)
            if found do
                return found!.value
            walk = .document.constNode(walk).parent
        }

        return HtmlNoNode
    }

    // Brings the box that draws a node into view.
    mtd scrollToNode(node: u32)->bool
    {
        if node == HtmlNoNode do
            return false

        let box = .boxOfNode(node)
        if box == HtmlNoNode do
            return false

        // A node whose text lives in a line box is found more precisely through that line, so a
        // match inside a long block scrolls to the line and not to the top of the block.
        var top = .layout.constBox(box).rect.y
        for item in .layout.constBox(box).items where item.node == node and item.visible
        {
            top = item.y
            break
        }

        .searchNode = node
        let position = .scroll.scrollPosition()
        .scroll.setScrollPos(position.x, Math.max(top - 24, 0))
        .canvas.invalidate()
        return true
    }

    // Scrolls to the next node whose text contains `text`, wrapping once at the end.
    public mtd findText(text: string)->bool
    {
        if !@countof(text) do
            return false

        let count = .document.nodes.count
        if !count do
            return false

        var start = 0'u64
        if .searchNode != HtmlNoNode do
            start = cast(u64) .searchNode + 1

        for offset in count
        {
            let index = cast(u32) ((start + offset) % count)
            let node  = .document.constNode(index)
            if node.kind != .Text or node.text.isEmpty() do
                continue
            if Utf8.indexOf(node.text.toString(), text, 0, .Latin1NoCase) == Swag.U64.Max do
                continue
            if .scrollToNode(index) do
                return true
        }

        return false
    }

    // Returns the anchor a node sits inside, or `HtmlNoNode` when it sits in none.
    mtd const linkElementAt(node: u32)->u32
    {
        var walk = node
        while walk != HtmlNoNode
        {
            if .document.constNode(walk).tag == .A and .document.hasAttribute(walk, "href") do
                return walk
            walk = .document.constNode(walk).parent
        }

        return HtmlNoNode
    }

    // Returns the destination a node sits inside, or an empty string when it sits in none.
    mtd const linkAt(node: u32)->string
    {
        let anchor = .linkElementAt(node)
        return anchor == HtmlNoNode ? "" : .document.attribute(anchor, "href")
    }

    mtd painter()->HtmlPainter
    {
        // The visible rectangle is in the canvas's own coordinates, which is the space the paint
        // offset puts every box into; the scroll position is kept separately because a sticky box
        // needs to know where the document really is.
        var result: retval
        result.layout    = &.layout
        result.images    = &.images
        result.renderer  = .app().renderer
        result.scrollY   = .scroll.scrollPosition().y
        result.visible   = .scroll.paddedClientRect()
        result.hotLink   = .themeColors().url_HotText
        result.hoverLink = .linkElementAt(.hovered)
        return result
    }

    // Repositions a streamed document on the node a byte offset belongs to.
    //
    // The document is read up to that offset first when it is not there yet, so a match reported
    // by a search over the raw file always lands on what draws it. An empty `text` only scrolls.
    public mtd revealFileOffset(offset: u64, text: string)->bool
    {
        if .fileName.isEmpty() and !.sourceDone do
            return false

        .pendingSearch = text
        if .sourceDone or offset < .bytesRead
        {
            let node = .nodeAtSourceOffset(Math.min(offset, .bytesRead))
            discard .scrollToNode(node)
            .resolvePending()
            return true
        }

        .revealOffset = offset
        .hasReveal    = true
        .scheduleMore()
        return true
    }

    // Replaces the document defaults and restyles what is already loaded.
    public mtd setDocumentStyle(documentStyle: HtmlStyle)
    {
        .documentStyle = documentStyle
        .rebuild()
        .invalidate()
    }

    func createBase(contentParent: *Wnd, documentStyle: HtmlStyle)->*HtmlView
    {
        let result = Wnd.create'HtmlView(contentParent, "gui.html")
        result.backgroundStyle = .View
        result.focusPolicy     = .Tab
        result.wndFlags        |= .NoFocusRing
        result.documentStyle   = documentStyle
        result.nextRefresh     = HtmlFirstRefreshSize
        result.document        = HtmlDocument.create()
        result.parser.start(&result.document)

        result.scroll           = Wnd.create'ScrollWnd(result, "", {})
        result.scroll.dockStyle = .Center
        result.scroll.updateFlags(.DisableHorizontal)

        let view = result.scroll.createView'Wnd()
        view.backgroundStyle = .View

        result.canvas          = Wnd.create'HtmlCanvas(view, "gui.html.canvas")
        result.canvas.owner    = result
        result.canvas.wndFlags |= .NoScroll

        result.scroll.hookOnEvent = func|target = result|(wnd, evt)
        {
            discard wnd
            if evt is ResizeEvent do
                target.placeDocument()
            return false
        }
        result.scroll.sigScrollPositionChanged += func|target = result|(scroll, oldPosition, newPosition)
        {
            discard scroll
            discard oldPosition
            discard newPosition
            target.canvas.invalidate()
        }

        result.applyLayout()
        result.setInitialFocus(result)
        return result
    }

    // Creates a view and renders the complete in-memory HTML source.
    public func createText(contentParent: *Wnd, source: string, documentStyle: HtmlStyle = {})->*HtmlView
    {
        let result = .createBase(contentParent, documentStyle)
        result.parser.feed(source)
        result.parser.finish()
        result.sourceDone = true
        result.bytesRead  = @countof(source)
        result.rebuild()
        return result
    }

    // Creates a view and progressively loads a UTF-8 HTML file.
    //
    // File-open and decoding failures are displayed inside the returned view rather than reported
    // to the caller.
    public func createFile(contentParent: *Wnd, fileName: string, documentStyle: HtmlStyle = {})->*HtmlView
    {
        let result = .createBase(contentParent, documentStyle)
        result.fileName        = fileName
        result.images.basePath = Path.directoryName(fileName) orelse ""

        result.stream = catch File.openRead(fileName) as openError
        if openError != null
        {
            result.finishSource("<p>Unable to read this HTML document.</p>")
            result.rebuild()
            return result
        }

        result.streamStep()
        return result
    }
}

internal impl IWnd for HtmlView
{
    mtd impl onThemeEvent(evt: *ThemeEvent)
    {
        discard evt
        if @isset(.scroll) do
            .rebuild()
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if !scrollDocumentWithKey(.scroll, evt) do
            evt.accepted = false
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        discard evt
        .stopLoading()
        .images.clear()
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer != .loadTimer
        {
            evt.accepted = false
            return
        }

        .removeTimer(evt.timer)
        .loadTimer = null
        .streamStep()
    }
}

internal impl IWnd for HtmlCanvas
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let owner = .owner
        if owner.layout.root == HtmlNoNode do
            return

        var painter = owner.painter()
        painter.painter = evt.paintContext.painter
        painter.paint(painter.visible, painter.scrollY)
    }

    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        let owner = .owner
        let point = .surfaceToLocal(evt.surfacePos)

        switch evt.kind
        {
        case .Move:
            let painter = owner.painter()
            let node    = painter.nodeAt(point)
            if node != owner.hovered
            {
                owner.hovered = node
                .invalidate()
            }

            if @countof(owner.linkAt(node)) do
                .app().setFrameCursor(Cursor.from(.Hand))

        case .Leave:
            if owner.hovered != HtmlNoNode
            {
                owner.hovered = HtmlNoNode
                .invalidate()
            }

        case .Pressed where evt.button == .Left:
            let painter = owner.painter()
            let url     = owner.linkAt(painter.nodeAt(point))
            if !@countof(url)
            {
                evt.accepted = false
                return
            }

            // A reference into the document itself is followed here; anything else is a
            // destination only the host knows how to open.
            if !owner.navigateToFragment(url) do
                owner.sigLinkActivated.call(owner, url)

        case .Wheel:

            // A region that scrolls on its own takes the wheel while the pointer is over it, and
            // hands it back to the page once it has reached its end.
            let painter = owner.painter()
            let region  = painter.scrollableAt(point)
            if region == HtmlNoNode or !owner.scrollRegion(region, -evt.delta.y * 50) do
                evt.accepted = false

        default:
            evt.accepted = false
        }
    }
}

internal impl HtmlView
{
    // Moves an independently scrolled region, and reports whether it actually moved.
    mtd scrollRegion(box: u32, delta: f32)->bool
    {
        let target = .layout.box(box)
        let limit  = Math.max(target.scrollHeight - target.content.height, 0)
        let wanted = Math.clamp(target.scrollTop + delta, 0, limit)
        if wanted == target.scrollTop do
            return false

        target.scrollTop = wanted
        .canvas.invalidate()
        return true
    }
}
