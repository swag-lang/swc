#global public

using Core, Pixel

// Bytes read from disk per streaming step. One step consumes exactly one bounded chunk, so even a
// fast machine presents a multi-megabyte document over several application frames.
private const HtmlStreamChunkSize = 48 * 1024'u64

// Source bytes read before the first partial rendering. The threshold then grows fourfold at each
// one, so a document shows its beginning quickly and the intermediate passes stay a bounded share
// of the whole load instead of repeating once per chunk.
private const HtmlFirstRefreshSize = 192 * 1024'u64

// The largest document the engine keeps in memory. Past it the reader is told the file was cut
// rather than shown a rendering that silently drops content.
private const HtmlMaxDocumentSize = 48 * 1024 * 1024'u64

// File-backed source pages above this size are rendered through a bounded source window. Generated
// documentation routinely wraps an entire source file in one `<pre><code>` element; retaining the
// corresponding DOM, cascade and inline layout multiplies a few megabytes into hundreds of
// megabytes. The window keeps the real HTML engine and author CSS, but only for nearby source.
private const HtmlVirtualSourceThreshold = 2 * 1024 * 1024'u64
private const HtmlVirtualProbeSize = 256 * 1024'u64
private const HtmlVirtualWindowSize = 192 * 1024'u64
private const HtmlVirtualLookBehind = HtmlVirtualWindowSize / 2

// Source bytes inspected before the first parse to decide how the file spells its characters.
private const HtmlCharsetProbeSize = 4 * 1024'u64

// Returns the encoding a `charset=` declaration within the probe names, when it names one this
// engine reads.
//
// This is the prescan every browser runs on the head of a file: the head of a legacy page is
// pure ASCII, so the content heuristic cannot see past it, and the declaration is the only
// truth available. The label set maps the way the HTML standard maps it — the Latin-1 family
// is code page 1252, and a UTF-16 label on bytes readable as ASCII means UTF-8.
private func htmlDeclaredEncoding(probe: string)->{ encoding: Text.Encoding, matched: bool }
{
    var result: retval
    var scan = 0'u64
    while true
    {
        let found = Utf8.indexOf(probe, "charset", scan, .Latin1NoCase)
        if found == Swag.U64.Max do
            return result

        var index = found + @countof("charset")
        while index < @countof(probe) and Latin1.isSpace(probe[index]) do
            index += 1
        if index >= @countof(probe) or probe[index] != '='
        {
            scan = index
            continue
        }

        index += 1
        while index < @countof(probe) and Latin1.isSpace(probe[index]) do
            index += 1
        if index < @countof(probe) and (probe[index] == '"' or probe[index] == '\'') do
            index += 1

        let labelStart = index
        while index < @countof(probe) and (Latin1.isLetterOrDigit(probe[index]) or probe[index] == '-') do
            index += 1

        let label = String.from(probe[labelStart until index]).toLower()
        switch label.toString()
        {
        case "utf-8", "utf8", "utf-16", "utf-16le", "utf-16be":
            result.encoding = .Utf8
            result.matched  = true
            return result

        case "windows-1252", "iso-8859-1", "iso8859-1", "latin1", "l1", "cp1252", "ascii", "us-ascii":
            result.encoding = .Windows1252
            result.matched  = true
            return result
        }

        scan = index
    }
}

// Controls the typography an [[Gui.HtmlView]] starts from.
//
// These are the values a document inherits before its own CSS has a say — what a browser calls
// its default font settings. A document that specifies nothing is drawn with them, and one that
// specifies everything is unaffected by them.
struct HtmlStyle
{
    public
    {
        bodyFontSize:    u32 = 16       // Default body-text size, in logical pixels.
        codeFontSize:    u32 = 14       // Default size for monospaced text, in logical pixels.
        maxContentWidth: f32 = 0        // Reading measure imposed on a document that sets none; `0` follows the document.
        followTheme          = true     // Whether default colors and the color scheme come from the GUI theme.
    }
}

impl HtmlStyle
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

// One independently scrolled element retained while an incremental parse rebuilds the box tree.
private struct HtmlRegionScrollState
{
    node: u32
    top:  f32
}

// Displays HTML as a laid-out document.
//
// [[Gui.HtmlView.createText]] renders in-memory source, and [[Gui.HtmlView.createFile]] streams a
// file and follows local document links and stylesheets relative to its folder. Rendering stays
// offline: no script runs and remote references are reported through [[Gui.HtmlView.sigLinkActivated]].
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
struct HtmlView
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        sigLinkActivated: SigArray'func||(*HtmlView, string)     // Emitted when an activated link cannot be followed as a local document or fragment.
        sigLoadFailed:    SigArray'func||(*HtmlView, string)     // Emitted with the exact reason when progressive file loading stops.

        readonly
        {
            documentStyle: HtmlStyle     // Typography a document inherits before its own CSS applies.
            failureReason: String        // File-loading explanation, or empty while loading remains valid.
        }
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
        encoding:    Text.Encoding
        fileSize:    u64
        bytesRead:   u64
        sourceDone:  bool
        loadTimer:   #null *Timer
        nextRefresh: u64
        embedded:    bool

        // A generated source page is one enormous preformatted block. Only this deterministic
        // byte window is materialized; the outer scroll range represents the complete file.
        virtualSource:        bool
        virtualPreformatted:  bool
        virtualPrefix:        String
        virtualSuffix:        String
        virtualContentStart:  u64
        virtualWindowStart:   u64
        virtualWindowEnd:     u64
        virtualOrigin:        f32
        virtualHeight:        f32
        virtualPendingSeek:   bool
        virtualPendingOffset: u64
        virtualPendingY:      f32

        pendingSearch:      String
        pendingFragment:    String
        revealOffset:       u64
        hasReveal:          bool
        hasPendingFragment: bool
        searchNode = HtmlNoNode
        searchStart:        u64
        searchEnd:          u64
        hovered    = HtmlNoNode

        // The reader's selection, as the two ends of the drag that made it. The anchor is where
        // the press landed and the caret follows the pointer; both are a text node plus a byte
        // offset into its source text, and normalization into document order happens on read.
        selAnchorNode = HtmlNoNode
        selCaretNode  = HtmlNoNode
        selAnchorOffset: u64
        selCaretOffset:  u64
        selecting:       bool

        scrollDragBox = HtmlNoNode
        scrollDragTrackTop: f32
        scrollDragTravel:   f32
        scrollDragGrab:     f32
        scrollDragLimit:    f32
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
        let viewport      = .viewportSize()
        let regionScrolls = .captureRegionScrolls()

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
        .restoreRegionScrolls(regionScrolls.toSlice())
    }

    // Captures independently scrolled element positions before a streaming rebuild replaces the
    // box tree. Node indices remain stable while the parser appends source.
    private mtd captureRegionScrolls()->Array'HtmlRegionScrollState
    {
        var result: retval
        for box in .layout.boxes where box.node != HtmlNoNode and box.scrollTop > 0
        {
            var state: HtmlRegionScrollState
            state.node = box.node
            state.top  = box.scrollTop
            result.add(state)
        }

        return result
    }

    private mtd restoreRegionScrolls(states: const [..] HtmlRegionScrollState)
    {
        for state in states
        {
            let found = .layout.nodeBox.tryFind(state.node)
            if !found do
                continue

            let box = .layout.box(found!.value)
            if !box.scrollable do
                continue
            box.scrollTop = Math.clamp(state.top, 0, Math.max(box.scrollHeight - box.content.height, 0))
        }
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
        let laidOutHeight = Math.max(.layout.documentHeight, viewport.y)
        let height        = .embedded ? viewport.y : (.virtualSource and .virtualHeight > 0 ? .virtualHeight : laidOutHeight)
        let position      = .scroll.scrollPosition()
        .canvas.setPosition({0, 0, viewport.x, viewport.y})
        .scroll.setScrollSize(viewport.x, height)
        .scroll.setScrollPos(position)
        .scroll.verticalScrollStep = Math.max(cast(f32) .documentStyle.bodyFontSize * 3, 24)
        .canvas.invalidate()
    }

    // Recognizes the shape generated documentation uses for source listings and retains the
    // bounded shell needed to style independent windows of its `<pre><code>` content.
    private mtd prepareVirtualSource()->bool
    {
        if .fileSize < HtmlVirtualSourceThreshold or .encoding != .Utf8 do
            return false

        let contentStart = catch .stream.position() as positionError
        if positionError != null do
            return false
        let probe = catch .stream.readTextChunk(HtmlVirtualProbeSize, .encoding) as readError
        if readError != null
        {
            discard catch .stream.seek(.Begin, contentStart)
            return false
        }

        let headClose     = Utf8.indexOf(probe.toString(), "</head>", 0, .Latin1NoCase)
        let bodyStart     = Utf8.indexOf(probe.toString(), "<body", 0, .Latin1NoCase)
        let preStart      = Utf8.indexOf(probe.toString(), "<pre", bodyStart == Swag.U64.Max ? 0 : bodyStart, .Latin1NoCase)
        let codeStart     = Utf8.indexOf(probe.toString(), "<code", preStart == Swag.U64.Max ? 0 : preStart, .Latin1NoCase)
        let bodyEnd       = bodyStart == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(probe.toString(), '>'rune, bodyStart)
        let preEnd        = preStart == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(probe.toString(), '>'rune, preStart)
        let codeEnd       = codeStart == Swag.U64.Max ? Swag.U64.Max : Utf8.indexOf(probe.toString(), '>'rune, codeStart)
        let sourceListing = bodyEnd != Swag.U64.Max and preEnd != Swag.U64.Max and codeEnd != Swag.U64.Max and Utf8.indexOf(probe.toString(), "<a href=#", codeEnd + 1, .Latin1NoCase) != Swag.U64.Max

        .virtualPrefix = headClose == Swag.U64.Max ? "<html><head></head>" : String.from(probe.toString()[0 until headClose + @countof("</head>")])
        if bodyEnd != Swag.U64.Max do
            .virtualPrefix += probe.toString()[bodyStart to bodyEnd]
        else do
            .virtualPrefix += "<body>"

        if sourceListing
        {
            .virtualPrefix       += probe.toString()[preStart to preEnd]
            .virtualPrefix       += probe.toString()[codeStart to codeEnd]
            .virtualSuffix       = "</code></pre></body></html>"
            .virtualContentStart = contentStart + codeEnd + 1
            .virtualPreformatted = true
        }
        else
        {
            .virtualSuffix       = "</body></html>"
            .virtualContentStart = bodyEnd == Swag.U64.Max ? contentStart : contentStart + bodyEnd + 1
        }

        .virtualSource = true
        .stream.close()
        return true
    }

    // Materializes one deterministic byte window of a generated source page. Replacing the
    // window releases the previous document's text, nodes, styles and boxes before parsing the
    // next one, so memory depends on this constant window rather than on file size.
    private mtd loadVirtualWindow(requestedOffset: u64, requestedY = -1.0'f32)->bool
    {
        let requested = Math.clamp(requestedOffset, .virtualContentStart, .fileSize)
        let wanted    = requested > .virtualContentStart + HtmlVirtualLookBehind ? requested - HtmlVirtualLookBehind : .virtualContentStart

        .stream = catch File.openRead(.fileName.toString()) as openError
        if openError != null do
            return false
        let actual = Math.min(wanted, .fileSize)
        discard catch .stream.seek(.Begin, actual)
        var bytes: Array'u8
        bytes.resize(Math.min(HtmlVirtualWindowSize + HtmlVirtualLookBehind * 2, .fileSize - actual))
        let count = catch .stream.read(bytes.toSlice()) as readError
        .stream.close()
        if readError != null do
            return false
        bytes.resize(count)
        let chunk = Text.decode(bytes.toSlice(), .Utf8)

        var begin = 0'u64
        if actual != .virtualContentStart
        {
            // The seek begins inside an arbitrary source line. Drop only that incomplete line;
            // keeping the rest of the look-behind makes the requested point land near the middle
            // of the resident window instead of immediately scheduling the same seek again.
            let anchor = .virtualPreformatted ? Utf8.indexOf(chunk.toString(), "\n<a ", 0, .Latin1NoCase) : Swag.U64.Max
            if anchor != Swag.U64.Max do
                begin = anchor + 1
            else
            {
                let line = Utf8.indexOf(chunk.toString(), '\n'rune)
                if line != Swag.U64.Max do
                    begin = line + 1
            }
        }

        var end = Math.min(begin + HtmlVirtualWindowSize, chunk.length)
        if end < chunk.length
        {
            let boundary = Utf8.indexOf(chunk.toString(), "\n<a ", end, .Latin1NoCase)
            if boundary != Swag.U64.Max do
                end = boundary + 1
        }

        if end <= begin do
            return false

        .document.clear()
        .parser.start(&.document)
        .layout.boxes.clear()
        .layout.root = HtmlNoNode
        .images.clear()
        .images.basePath = Path.directoryName(.fileName.toString()) orelse ""
        .searchNode      = HtmlNoNode
        .hovered         = HtmlNoNode
        .clearSelection()

        var source = String.from(.virtualPrefix.toString())
        source += chunk.toString()[begin until end]
        source += .virtualSuffix
        .parser.feed(source.toString())
        .parser.finish()
        .sourceDone         = true
        .bytesRead          = actual + end
        .virtualWindowStart = actual + begin
        .virtualWindowEnd   = actual + end
        .rebuild()

        let contentBytes = Math.max(.fileSize - .virtualContentStart, 1)
        let windowBytes  = Math.max(.virtualWindowEnd - .virtualWindowStart, 1)
        if .virtualHeight <= 0
        {
            let measured = Math.max(.layout.documentHeight, .viewportSize().y)
            .virtualHeight = Math.max(measured * cast(f32) contentBytes / cast(f32) windowBytes, .viewportSize().y)
        }

        let localRatio  = cast(f32) (requested - .virtualWindowStart) / cast(f32) windowBytes
        let globalRatio = cast(f32) (requested - .virtualContentStart) / cast(f32) contentBytes
        let localY      = Math.clamp(localRatio, 0, 1) * .layout.documentHeight
        let targetY     = requestedY >= 0 ? Math.clamp(requestedY, 0, .virtualHeight) : Math.clamp(globalRatio, 0, 1) * .virtualHeight
        .virtualOrigin = targetY - localY
        .placeDocument()
        .scroll.setScrollPos(.scroll.scrollPosition().x, targetY)
        .resolvePending()
        .canvas.invalidate()
        return true
    }

    // Decides how the open stream spells its characters and leaves it at the first content byte.
    //
    // A byte-order mark answers on its own and is not content; a `charset=` declaration within
    // the probe answers next; what remains is decided by the bytes through
    // [[Core.Text.detectEncoding]].
    mtd detectDocumentEncoding()->Text.Encoding
    {
        var probe: Array'u8
        probe.resize(HtmlCharsetProbeSize)
        let count = catch .stream.read(probe.toSlice()) as readError
        probe.resize(readError == null ? count : 0)

        var result       = Text.detectEncoding(probe.toSlice())
        var contentStart = 0'u64
        if Text.hasBom(probe.toSlice(), result)
        {
            contentStart = Text.bomLength(result)
        }
        else
        {
            let declared = htmlDeclaredEncoding(cast(string) probe.toSlice())
            if declared.matched do
                result = declared.encoding
        }

        // A stream that cannot rewind cannot stream the document; the next read reports that
        // through the existing failure path, and the encoding answer no longer matters.
        catch .stream.seek(.Begin, contentStart) as seekError
        if seekError != null do
            return .Utf8

        return result
    }

    // Feeds one bounded batch of source into the parser.
    mtd streamStep()
    {
        if !.sourceDone
        {
            let chunk = catch .stream.readTextChunk(HtmlStreamChunkSize, .encoding) as readError
            if readError != null
            {
                .reportLoadFailure(Errors.message(readError))
                .finishSource("<p>Unable to read this HTML document.</p>")
            }
            elif chunk.isEmpty()
            {
                // The depth cap behaves like the size cap: the reader is told what was cut
                // rather than shown a silently flattened rendering.
                .finishSource(.parser.depthCapped ? "<p>This document nests its elements too deeply; the deepest levels were flattened.</p>" : "")
            }
            else
            {
                .parser.feed(chunk.toString())
                .bytesRead += chunk.length
                if .bytesRead >= HtmlMaxDocumentSize do
                    .finishSource("<p>This document is too large to be displayed in full; the rest of the file was not read.</p>")
            }
        }

        // A partial rendering is produced at growing intervals, so a long document shows its
        // beginning quickly without paying for a full pass on every chunk. A pending navigation
        // rebuilds as soon as its parsed target is ready instead of waiting behind that schedule.
        let fragmentReady = .hasPendingFragment and .elementById(.pendingFragment.toString()) != HtmlNoNode
        let revealReady   = .hasReveal and .revealOffset < .bytesRead
        if .sourceDone or .bytesRead >= .nextRefresh or (.layout.root == HtmlNoNode and .bytesRead > 0) or fragmentReady or revealReady
        {
            if !.sourceDone do
                .nextRefresh = .bytesRead * 4
            .rebuild()
            .resolvePending()
        }

        if !.sourceDone do
            .scheduleMore()
    }

    mtd reportLoadFailure(reason: string)
    {
        .failureReason = reason
        if .failureReason.isEmpty() do
            .failureReason = "HTML source could not be read"
        .sigLoadFailed.call(me, .failureReason.toString())
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
        if .loadTimer or (.sourceDone and !.virtualPendingSeek) do
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
        if .hasPendingFragment
        {
            let node = .elementById(.pendingFragment.toString())
            if node != HtmlNoNode
            {
                .hasPendingFragment = false
                .pendingFragment.clear()
                discard .scrollToNode(node, useScrollMargin: true)
            }
            elif .sourceDone
            {
                .hasPendingFragment = false
                .pendingFragment.clear()
            }
        }

        if .hasReveal and (.sourceDone or .revealOffset < .bytesRead)
        {
            .hasReveal = false
            if !.pendingSearch.isEmpty() and .highlightSourceMatch(.revealOffset, .pendingSearch.toString()) do
                .pendingSearch.clear()
            else do
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

    // Highlights the exact rendered text range named by a source-file match.
    private mtd highlightSourceMatch(offset: u64, text: string)->bool
    {
        if .virtualSource do
            return false
        let nodeIndex = .nodeAtSourceOffset(offset)
        if nodeIndex == HtmlNoNode do
            return false
        let node = .document.constNode(nodeIndex)
        if node.kind != .Text or offset < node.sourceOffset do
            return false
        let start = offset - node.sourceOffset
        if start + @countof(text) > node.text.length do
            return false

        .searchNode  = nodeIndex
        .searchStart = start
        .searchEnd   = start + @countof(text)
        discard .scrollToNode(nodeIndex)
        .canvas.invalidate()
        return true
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

        let fragment = url[1 to]
        if !@countof(fragment)
        {
            let position = .scroll.scrollPosition()
            .scroll.setScrollPos(position.x, 0)
            return true
        }

        if .scrollToNode(.elementById(fragment), useScrollMargin: true) do
            return true
        if !.sourceDone
        {
            .pendingFragment    = fragment
            .hasPendingFragment = true
            .scheduleMore()
        }

        // A fragment belongs to this document even when no matching element exists.
        return true
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
    mtd scrollToNode(node: u32, useScrollMargin = false)->bool
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

        var clearance = 24.0'f32
        if useScrollMargin
        {
            let target = .layout.constBox(box)
            let style  = .layout.constStyle(target.style)
            clearance = .layout.resolveLength(style.scrollMarginTop, target.style, .layout.viewport.x)
        }

        let position = .scroll.scrollPosition()
        let origin   = .virtualSource ? .virtualOrigin : 0
        .scroll.setScrollPos(position.x, Math.max(origin + top - clearance, 0))
        .canvas.invalidate()
        return true
    }

    // Follows a local document link in this view, preserving the host callback for URLs and
    // destinations this offline renderer does not own.
    private mtd navigateToLocalDocument(url: string)->bool
    {
        if .images.basePath.isEmpty() or !@countof(url) do
            return false
        if Utf8.contains(url, "://") or Utf8.startsWith(url, "//") or Utf8.startsWith(url, "data:") do
            return false

        let hash     = Utf8.indexOf(url, '#'rune)
        let path     = hash == Swag.U64.Max ? url : url[0 until hash]
        let fragment = hash == Swag.U64.Max ? "" : url[hash + 1 to]
        if !@countof(path) do
            return false

        let colon = Utf8.indexOf(path, ':'rune)
        if colon != Swag.U64.Max and !(colon == 1 and Path.isRooted(path)) do
            return false

        var fileName = Path.isRooted(path) ? String.from(path) : Path.combine(.images.basePath.toString(), path)
        Path.normalize(&fileName)
        if !File.exists(fileName.toString()) do
            return false

        if Path.equals(fileName.toString(), .fileName.toString())
        {
            return hash == Swag.U64.Max ? true : .navigateToFragment(Format.toString("#%", fragment).toString())
        }

        .loadFile(fileName.toString(), fragment)
        return true
    }

    private mtd activateLink(url: string)->bool
    {
        if .embedded do
            return false
        if .navigateToFragment(url) do
            return true
        return .navigateToLocalDocument(url)
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
            let match = Utf8.indexOf(node.text.toString(), text, 0, .Latin1NoCase)
            if match == Swag.U64.Max do
                continue
            if .scrollToNode(index)
            {
                .searchNode  = index
                .searchStart = match
                .searchEnd   = match + @countof(text)
                .canvas.invalidate()
                return true
            }
        }

        return false
    }

    mtd searchMatchCount(text: string)->u64
    {
        if !@countof(text) do
            return 0

        var result: u64
        for &node in .document.nodes where node.kind == .Text and !node.text.isEmpty()
        {
            var from: u64
            while true
            {
                let match = Utf8.indexOf(node.text.toString(), text, from, .Latin1NoCase)
                if match == Swag.U64.Max do
                    break
                result += 1
                from   = match + @countof(text)
            }
        }

        return result
    }

    mtd findTextOccurrence(text: string, occurrence: u64)->bool
    {
        if !@countof(text) do
            return false

        .clearSearchHighlight()
        var remaining = occurrence
        for index in .document.nodes.count
        {
            let node = .document.constNode(cast(u32) index)
            if node.kind != .Text or node.text.isEmpty() do
                continue

            var from: u64
            while true
            {
                let match = Utf8.indexOf(node.text.toString(), text, from, .Latin1NoCase)
                if match == Swag.U64.Max do
                    break
                if remaining
                {
                    remaining -= 1
                    from      = match + @countof(text)
                    continue
                }

                if !.scrollToNode(cast(u32) index) do
                    return false
                .searchNode  = cast(u32) index
                .searchStart = match
                .searchEnd   = match + @countof(text)
                .canvas.invalidate()
                return true
            }
        }

        return false
    }

    // Clears the current match when an embedding document starts another search.
    mtd clearSearchHighlight()
    {
        .searchNode  = HtmlNoNode
        .searchStart = 0
        .searchEnd   = 0
        .canvas.invalidate()
    }

    // Returns the selection normalized to document order, or `has == false` when it is empty.
    mtd const selectionRange()->{ startNode: u32, startOffset: u64, endNode: u32, endOffset: u64, has: bool }
    {
        var result: retval
        if .selAnchorNode == HtmlNoNode or .selCaretNode == HtmlNoNode do
            return result
        if .selAnchorNode == .selCaretNode and .selAnchorOffset == .selCaretOffset do
            return result

        let anchorFirst = .selAnchorNode < .selCaretNode or (.selAnchorNode == .selCaretNode and .selAnchorOffset < .selCaretOffset)
        result.startNode   = anchorFirst ? .selAnchorNode : .selCaretNode
        result.startOffset = anchorFirst ? .selAnchorOffset : .selCaretOffset
        result.endNode     = anchorFirst ? .selCaretNode : .selAnchorNode
        result.endOffset   = anchorFirst ? .selCaretOffset : .selAnchorOffset
        result.has         = true
        return result
    }

    // Reports whether the reader selected something.
    public mtd const hasSelection()->bool => .selectionRange().has

    // Empties the selection.
    public mtd clearSelection()
    {
        if .selAnchorNode == HtmlNoNode and .selCaretNode == HtmlNoNode do
            return
        .selAnchorNode = HtmlNoNode
        .selCaretNode  = HtmlNoNode
        .selAnchorOffset, .selCaretOffset = 0
        .selecting     = false
        .canvas.invalidate()
    }

    // Selects the whole document text.
    public mtd selectAll()
    {
        var first = HtmlNoNode
        var last  = HtmlNoNode
        for index in .document.nodes.count
        {
            let node = .document.constNode(cast(u32) index)
            if node.kind != .Text or node.text.isEmpty() do
                continue
            if first == HtmlNoNode do
                first = cast(u32) index
            last = cast(u32) index
        }

        if first == HtmlNoNode do
            return
        .selAnchorNode   = first
        .selAnchorOffset = 0
        .selCaretNode    = last
        .selCaretOffset  = .document.constNode(last).text.length
        .canvas.invalidate()
    }

    // Returns the selected text, one space per soft line break and one line per block.
    public mtd selectedText()->String
    {
        var result: retval
        var painter = .painter()
        painter.collectSelection(&result)
        return result
    }

    // Puts the selected text on the clipboard, and reports whether there was one.
    public mtd copySelection()->bool
    {
        if !.hasSelection() do
            return false
        let text = .selectedText()
        if text.isEmpty() do
            return false
        Clipboard.addString(text.toString())
        return true
    }

    const CtxCopy      = "Html.CtxCopy"
    const CtxSelectAll = "Html.CtxSelectAll"

    // Offers the reading vocabulary at `surfacePos`: what a read-only document can give the
    // clipboard, with the same shortcuts the keyboard already binds.
    mtd showContextMenu(surfacePos: Math.Point)
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        menu.addItem(strings().edit_Copy, CtxCopy, rightName: "Ctrl+C", disabled: !.hasSelection())
        menu.addSeparator()
        menu.addItem(strings().edit_SelectAll, CtxSelectAll, rightName: "Ctrl+A")

        let picked = menu.doModal(surfacePos, .TopLeft, autoDestroy: true) orelse ""
        switch picked
        {
        case CtxCopy:      discard .copySelection()
        case CtxSelectAll: .selectAll()
        }
    }

    // Selects the word around one text position, the double-click gesture.
    mtd selectWordAt(node: u32, offset: u64)
    {
        if node == HtmlNoNode or cast(u64) node >= .document.nodes.count do
            return
        let source = .document.constNode(node).text.toString()
        if !@countof(source) do
            return

        // One pass records where each rune starts and whether it belongs to a word; the word is
        // then the run of word runes around the rune holding the offset, or that rune alone.
        var starts: Array'u64
        var words:  Array'bool
        var scan = 0'u64
        while scan < @countof(source)
        {
            let {value, eat} = Utf8.decodeRune(source[scan to])
            starts.add(scan)
            words.add(Unicode.isLetterOrDigit(value) or value == '_'rune)
            scan += eat
        }

        starts.add(scan)
        let position  = Math.min(offset, @countof(source) - 1)
        var runeIndex = 0'u64
        for i in words.count where starts[i] <= position do
            runeIndex = i

        var lo = runeIndex
        var hi = runeIndex
        if words[runeIndex]
        {
            while lo and words[lo - 1] do
                lo -= 1
            while hi + 1 < words.count and words[hi + 1] do
                hi += 1
        }

        .selAnchorNode   = node
        .selAnchorOffset = starts[lo]
        .selCaretNode    = node
        .selCaretOffset  = starts[hi + 1]
        .selecting       = false
        .canvas.invalidate()
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
        result.layout      = &.layout
        result.images      = &.images
        result.renderer    = .app().renderer
        result.scrollY     = .scroll.scrollPosition().y - (.virtualSource ? .virtualOrigin : 0)
        result.visible     = .scroll.paddedClientRect()
        result.hotLink     = .themeColors().url_HotText
        result.hoverLink   = .linkElementAt(.hovered)
        result.searchNode  = .searchNode
        result.searchStart = .searchStart
        result.searchEnd   = .searchEnd
        result.selection   = .styleDefaults().selection
        let range = .selectionRange()
        if range.has
        {
            result.selStartNode   = range.startNode
            result.selStartOffset = range.startOffset
            result.selEndNode     = range.endNode
            result.selEndOffset   = range.endOffset
        }

        result.scrollTrack    = .themeColors().scrollBar_Bk
        result.scrollThumb    = .themeColors().scrollBar_Box
        result.scrollBarSize  = .themeMetrics().scrollBar_SmallSize
        result.scrollThumbMin = .themeMetrics().scrollBar_BoxMinSize
        return result
    }

    // Repositions a streamed document on the node a byte offset belongs to.
    //
    // The document is read up to that offset first when it is not there yet, so a match reported
    // by a search over the raw file marks that exact rendered range when source and text offsets
    // agree. An empty `text` only scrolls.
    public mtd revealFileOffset(offset: u64, text: string)->bool
    {
        if .fileName.isEmpty() and !.sourceDone do
            return false

        if .virtualSource
        {
            .stopLoading()
            .virtualPendingSeek = false
            .pendingSearch      = text
            return .loadVirtualWindow(offset)
        }

        .pendingSearch = text
        if .sourceDone or offset < .bytesRead
        {
            if @countof(text) and .highlightSourceMatch(offset, text)
            {
                .pendingSearch.clear()
                return true
            }

            let node = .nodeAtSourceOffset(Math.min(offset, .bytesRead))
            .searchNode  = node == 0 ? HtmlNoNode : node - 1
            .searchStart = 0
            .searchEnd   = 0
            discard .scrollToNode(node)
            .resolvePending()
            return true
        }

        .revealOffset = offset
        .hasReveal    = true
        .scheduleMore()
        return true
    }

    // Reports the current search highlight in surface coordinates.
    //
    // Returns false until a streamed match is laid out. The caller owns the visual treatment and
    // may poll this method while [[Gui.HtmlView.isLoading]] remains true.
    public mtd searchMatchRect(result: *Math.Rectangle)->bool
    {
        var local: Math.Rectangle
        var paint = .painter()
        if !paint.searchMatchRect(&local) do
            return false
        result[] = .canvas.localToSurface(local)
        return !result.isEmpty()
    }

    // Removes the programmatic search highlight without changing the document selection.
    public mtd clearSearch()
    {
        .clearSearchHighlight()
    }

    // Replaces the document defaults and restyles what is already loaded.
    public mtd setDocumentStyle(documentStyle: HtmlStyle)
    {
        .documentStyle = documentStyle
        .rebuild()
        .invalidate()
    }

    // Measures an embedded document at `width` without exposing a nested scrolling surface.
    mtd embeddedHeight(width: f32)->f32
    {
        @assert(.embedded)
        var height = Math.max(.layout.documentHeight, 1)
        for 2
        {
            .resize(width, height)
            .applyLayout()
            .placeDocument()
            height = Math.max(.layout.documentHeight, 1)
        }

        return height
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

            // An embedded document contributes its complete height to its parent and therefore
            // has no outer scroll surface of its own. Let an unclaimed wheel continue to that
            // parent; independently scrollable CSS regions already consume it in HtmlCanvas.
            if let mouseEvt = evt as MouseEvent where target.embedded and mouseEvt.kind == .Wheel
            {
                mouseEvt.accepted = false
                return true
            }

            return false
        }
        result.scroll.sigScrollPositionChanged += func|target = result|(scroll, oldPosition, newPosition)
        {
            discard scroll
            discard oldPosition
            if target.virtualSource and target.virtualHeight > 0 and target.fileSize > target.virtualContentStart
            {
                let contentBytes = target.fileSize - target.virtualContentStart
                let ratio        = Math.clamp(newPosition.y / target.virtualHeight, 0, 1)
                let offset       = target.virtualContentStart + cast(u64) (ratio * cast(f32) contentBytes)
                let margin       = (target.virtualWindowEnd - target.virtualWindowStart) / 4
                let before       = target.virtualWindowStart > target.virtualContentStart and offset < target.virtualWindowStart + margin
                let after        = target.virtualWindowEnd < target.fileSize and offset + margin > target.virtualWindowEnd
                if before or after
                {
                    target.virtualPendingOffset = offset
                    target.virtualPendingY      = newPosition.y
                    target.virtualPendingSeek   = true
                    target.scheduleMore()
                }
                else do
                    target.virtualPendingSeek = false
            }

            target.canvas.invalidate()
        }

        result.applyLayout()
        result.setInitialFocus(result)
        return result
    }

    // Replaces the source state and begins one progressive local-file load.
    private mtd loadFile(fileName: string, fragment: string = "")
    {
        // A local link's fragment can point into the current document's attribute storage, which
        // is released below. Own it before clearing the document.
        let fragmentCopy = String.from(fragment)

        .stopLoading()
        .images.clear()
        .document.clear()
        .parser.start(&.document)
        .layout.boxes.clear()
        .layout.root = HtmlNoNode

        .fileName             = fileName
        .images.basePath      = Path.directoryName(fileName) orelse ""
        .fileSize             = 0
        .bytesRead            = 0
        .sourceDone           = false
        .nextRefresh          = HtmlFirstRefreshSize
        .revealOffset         = 0
        .hasReveal            = false
        .hasPendingFragment   = !fragmentCopy.isEmpty()
        .pendingFragment      = fragmentCopy
        .searchNode           = HtmlNoNode
        .searchStart          = 0
        .searchEnd            = 0
        .hovered              = HtmlNoNode
        .selAnchorNode        = HtmlNoNode
        .selCaretNode         = HtmlNoNode
        .selAnchorOffset      = 0
        .selCaretOffset       = 0
        .selecting            = false
        .virtualSource        = false
        .virtualPreformatted  = false
        .virtualContentStart  = 0
        .virtualWindowStart   = 0
        .virtualWindowEnd     = 0
        .virtualOrigin        = 0
        .virtualHeight        = 0
        .virtualPendingSeek   = false
        .virtualPendingOffset = 0
        .virtualPrefix.clear()
        .virtualSuffix.clear()
        .pendingSearch.clear()
        .failureReason.clear()
        .scroll.setScrollPos(0, 0)

        .stream = catch File.openRead(fileName) as openError
        if openError != null
        {
            .reportLoadFailure(Errors.message(openError))
            .finishSource("<p>Unable to read this HTML document.</p>")
            .rebuild()
            return
        }

        let size = catch .stream.size() as sizeError
        if sizeError == null do
            .fileSize = size

        .encoding = .detectDocumentEncoding()
        if .prepareVirtualSource()
        {
            discard .loadVirtualWindow(.virtualContentStart)
            return
        }

        .streamStep()
    }

    // Creates a view and renders the complete in-memory HTML source.
    public func createText(contentParent: *Wnd, source: string, documentStyle: HtmlStyle = {})->*HtmlView
    {
        let result = HtmlView.createBase(contentParent, documentStyle)
        result.parser.feed(source)
        result.parser.finish()
        result.sourceDone = true
        result.bytesRead  = @countof(source)
        result.rebuild()
        return result
    }

    // Creates a complete HTML fragment that contributes its natural height to a parent document.
    func createEmbedded(contentParent: *Wnd, source: string, basePath: string, documentStyle: HtmlStyle = {})->*HtmlView
    {
        let result = HtmlView.createBase(contentParent, documentStyle)
        result.embedded        = true
        result.images.basePath = basePath
        result.parser.feed(source)
        result.parser.finish()
        result.sourceDone = true
        result.bytesRead  = @countof(source)
        result.rebuild()
        return result
    }

    // Creates a view and progressively loads an HTML file.
    //
    // The encoding is decided from the file itself — its byte-order mark, its `<meta charset>`,
    // or its bytes — so a legacy code page 1252 page reads as the accented text it means.
    // File-open and decoding failures remain visible in the document and are also exposed through
    // [[Gui.HtmlView.failureReason]] and [[Gui.HtmlView.sigLoadFailed]].
    public func createFile(contentParent: *Wnd, fileName: string, documentStyle: HtmlStyle = {})->*HtmlView
    {
        let result = HtmlView.createBase(contentParent, documentStyle)
        result.loadFile(fileName)
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
        if evt.kind == .Pressed
        {
            if (evt.key == .C and evt.modifiers == .Control) or (evt.key == .Insert and evt.modifiers == .Control)
            {
                if .copySelection() do
                    return
            }
            elif evt.key == .A and evt.modifiers == .Control
            {
                .selectAll()
                return
            }
            elif evt.key == .Escape and evt.modifiers == .None and .hasSelection()
            {
                .clearSelection()
                return
            }
        }

        if .embedded or !scrollDocumentWithKey(.scroll, evt) do
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
        if .virtualPendingSeek
        {
            let offset = .virtualPendingOffset
            let y      = .virtualPendingY
            .virtualPendingSeek = false
            discard .loadVirtualWindow(offset, y)
            return
        }

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
            if owner.scrollDragBox != HtmlNoNode
            {
                owner.dragRegionScroll(point.y)
                return
            }

            var painter = owner.painter()
            if owner.selecting
            {
                let hit = painter.textPositionAt(point)
                if hit.node != HtmlNoNode and (hit.node != owner.selCaretNode or hit.offset != owner.selCaretOffset)
                {
                    owner.selCaretNode   = hit.node
                    owner.selCaretOffset = hit.offset
                    .invalidate()
                }

                .app().setFrameCursor(Cursor.from(.IBeam))
                return
            }

            let node = painter.nodeAt(point)
            if node != owner.hovered
            {
                // Painting only reads the link under the pointer, so crossing plain text keeps
                // the frame; repainting the whole canvas per pointer move is what made hovering
                // a long document feel slow.
                let previousLink = owner.linkElementAt(owner.hovered)
                owner.hovered = node
                if owner.linkElementAt(node) != previousLink do
                    .invalidate()
            }

            if @countof(owner.linkAt(node)) do
                .app().setFrameCursor(Cursor.from(.Hand))
            elif node != HtmlNoNode and owner.document.constNode(node).kind == .Text do
                .app().setFrameCursor(Cursor.from(.IBeam))

        case .Leave:
            if owner.hovered != HtmlNoNode
            {
                let hadLink = owner.linkElementAt(owner.hovered) != HtmlNoNode
                owner.hovered = HtmlNoNode
                if hadLink do
                    .invalidate()
            }

        case .Pressed where evt.button == .Left:
            owner.setFocus()
            var painter = owner.painter()
            let bar     = painter.scrollBarAt(point)
            if bar.box != HtmlNoNode
            {
                // The visible thumb is intentionally narrow, but the whole track width remains
                // its pointer target so it is as easy to grab as a native compact scrollbar.
                if point.y >= bar.thumb.y and point.y <= bar.thumb.bottom()
                {
                    owner.beginRegionScrollDrag(bar, point.y)
                    .captureMouse()
                }
                else
                {
                    let page = owner.layout.constBox(bar.box).content.height
                    discard owner.scrollRegion(bar.box, point.y < bar.thumb.y ? -page : page)
                }

                return
            }

            let url = owner.linkAt(painter.nodeAt(point))
            if @countof(url)
            {
                // A reference into the document itself is followed here; anything else is a
                // destination only the host knows how to open.
                if !owner.activateLink(url) do
                    owner.sigLinkActivated.call(owner, url)
                return
            }

            // Plain text under the press starts a selection drag; a press elsewhere drops any
            // previous one, which is how every document viewer reads.
            owner.clearSelection()
            let hit = painter.textPositionAt(point)
            if hit.node != HtmlNoNode and hit.distance == 0
            {
                owner.selAnchorNode   = hit.node
                owner.selAnchorOffset = hit.offset
                owner.selCaretNode    = hit.node
                owner.selCaretOffset  = hit.offset
                owner.selecting       = true
                .captureMouse()
                return
            }

            evt.accepted = false

        case .DoubleClick where evt.button == .Left:
            var painter = owner.painter()
            let hit     = painter.textPositionAt(point)
            if hit.node == HtmlNoNode or hit.distance != 0
            {
                evt.accepted = false
                return
            }

            owner.selectWordAt(hit.node, hit.offset)

        case .Pressed where evt.button == .Right:
            owner.setFocus()
            owner.showContextMenu(evt.surfacePos)

        case .Released where evt.button == .Left:
            if owner.selecting
            {
                owner.selecting = false
                if .mouseCapture() == me do
                    .releaseMouse()
                return
            }

            if owner.scrollDragBox == HtmlNoNode
            {
                evt.accepted = false
                return
            }

            owner.endRegionScrollDrag()
            if .mouseCapture() == me do
                .releaseMouse()

        case .Wheel:

            // A region that scrolls on its own owns the wheel while the pointer is over it, even
            // at an edge. One frame never moves another frame as a side effect.
            let painter = owner.painter()
            let region  = painter.scrollableAt(point)
            if region == HtmlNoNode do
                evt.accepted = false
            else do
                discard owner.scrollRegion(region, -evt.delta.y * 50)

        default:
            evt.accepted = false
        }
    }
}

internal impl HtmlView
{
    private mtd beginRegionScrollDrag(bar: HtmlRegionScrollBar, pointerY: f32)
    {
        let target = .layout.constBox(bar.box)
        .scrollDragBox      = bar.box
        .scrollDragTrackTop = bar.track.y
        .scrollDragTravel   = Math.max(bar.track.height - bar.thumb.height, 0)
        .scrollDragGrab     = pointerY - bar.thumb.y
        .scrollDragLimit    = Math.max(target.scrollHeight - target.content.height, 0)
    }

    private mtd dragRegionScroll(pointerY: f32)
    {
        if .scrollDragBox == HtmlNoNode or .scrollDragTravel <= 0 do
            return

        let thumbY = Math.clamp(pointerY - .scrollDragGrab - .scrollDragTrackTop, 0, .scrollDragTravel)
        let target = .layout.box(.scrollDragBox)
        let wanted = thumbY * .scrollDragLimit / .scrollDragTravel
        if wanted == target.scrollTop do
            return

        target.scrollTop = wanted
        .canvas.invalidate()
    }

    private mtd endRegionScrollDrag()
    {
        .scrollDragBox = HtmlNoNode
        .scrollDragTrackTop, .scrollDragTravel, .scrollDragGrab, .scrollDragLimit = 0
    }

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
