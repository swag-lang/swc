#global public
#global namespace Markdown

using Core, Pixel

private const StreamChunkSize = 8 * 1024'u64
private const StreamCarryLimit = 16 * 1024'u64
private const RevealContextSize = 64 * 1024'u64
private const ReverseContextSize = StreamChunkSize
private const RevealChunkSize = RevealContextSize + StreamChunkSize
private const ResidentSourceSize = 256 * 1024'u64
private const StreamLookAhead = 2.0
private const StreamFrameBudget = 3_000'u64
private const StreamBlockBudget = 8'u32

// Controls the reading measure and typography of a [[Gui.Markdown.View]].
//
// Colors and font faces resolve from the window's active [[Gui.Theme]], including local
// theme-sheet overrides, so a document can follow either an application palette or a document
// theme.
struct Style
{
    public
    {
        maxContentWidth:  f32                 = 860       // Widest document column, in logical pixels.
        horizontalInset:  f32                 = 48        // Minimum room kept on each side of the document column.
        topInset:         f32                 = 38        // Space before the first document block.
        bottomInset:      f32                 = 34        // Space after the last document block.
        bodyFontSize:     u32                 = 16        // Body-text draw size, in logical pixels.
        codeFontSize:     u32                 = 14        // Fixed-width code and table draw size, in logical pixels.
        mathFontSize:     u32                 = 22        // Base draw size of Pixel mathematical layout.
        heading1FontSize: u32                 = 36        // Level-one heading draw size, in logical pixels.
        heading2FontSize: u32                 = 28        // Level-two heading draw size, in logical pixels.
        heading3FontSize: u32                 = 24        // Level-three heading draw size, in logical pixels.
        heading4FontSize: u32                 = 20        // Level-four heading draw size, in logical pixels.
        heading5FontSize: u32                 = 16        // Level-five heading draw size, in logical pixels.
        heading6FontSize: u32                 = 16        // Level-six heading draw size, in logical pixels.
        lineHeight:       f32                 = 1.6       // Minimum body line height, relative to the active font.
        headingAlignment: StringHorzAlignment = .Left     // Horizontal alignment of headings.

        // Horizontal alignment of body paragraphs.
        //
        // `Justify` spreads the spaces of every wrapped line so both edges of the column are
        // flush. A line the author ended, and the last line of a paragraph, keep their natural
        // width; a line whose spaces would have to stretch past twice the line height is left
        // ragged rather than pulled apart. Headings, lists, quotes, tables and code are never
        // justified.
        paragraphAlignment: StringHorzAlignment = .Left
    }
}

impl Style
{
    // Returns the document style that follows the active GUI theme.
    func theme()->Style => {}
}

#[Swag.NoDoc]
struct VisualBlock
{
    wnd:        *Wnd = undefined
    inline:     #null *InlineView
    table:      #null *TableView
    html:       #null *HtmlView
    kind:       BlockKind
    searchText: String

    // Where this block starts in the reading order of the document's text views. A block that
    // owns none — a formula, an embedded page — sits between the view before it and this index,
    // which is how a selection crossing it knows it was crossed.
    orderIndex: u64
}

// One end of a document selection: a rendered text view, and a byte offset into its text.
//
// The pair is a document position rather than a laid-out one, so it survives a relayout, a theme
// change and a reading-width change; only rebuilding the blocks retires it.
#[Swag.NoDoc]
struct SelectionPoint
{
    view = Swag.U64.Max
    offset: u64
}

// Displays Markdown as a themed, read-only document with progressive UTF-8 file loading.
//
// [[Gui.Markdown.View.createText]] renders in-memory source, while
// [[Gui.Markdown.View.createFile]] streams a file without tying the renderer to an application.
// Block and inline mathematics use [[Pixel.MathExpression]] and the active theme font.
struct View
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        sigLinkActivated: SigArray'func||(*View, string)     // Emitted when a rendered link is activated.
        sigLoadFailed:    SigArray'func||(*View, string)     // Emitted with the exact reason when progressive file loading stops.

        readonly
        {
            documentStyle: Style      // Active document typography and reading measure.
            failureReason: String     // File-loading explanation, or empty while loading remains valid.
        }
    }

    #[Swag.Late]
    {
        scroll: *ScrollWnd
        body:   *Wnd
    }

    stream:              File.FileStream
    fileName:            String
    fileSize:            u64
    bytesRead:           u64
    residentStart:       u64
    virtualOrigin:       f32
    virtualHeight:       f32
    pendingSearch:       String
    pendingSeek:         bool
    pendingSeekOffset:   u64
    sourceCarry:         String
    sourceDone:          bool
    pendingBlocks:       Array'Block
    pendingIndex:        u64
    loadTimer:           #null *Timer
    contentHeight:       f32
    jumpToEnd:           bool
    hasPendingTarget:    bool
    pendingTarget:       f32
    pendingTargetOffset: u64 = Swag.U64.Max
    repositioning:       bool
    searchBlockIndex:    u64 = Swag.U64.Max
    documentThemeColors: String
    blocks:              Array'VisualBlock

    // Every text view of the document in reading order, and the two ends of the reader's
    // selection over them. The anchor is where the press landed and the caret follows the
    // pointer; normalization into reading order happens on read.
    inlineOrder: Array'(*InlineView)
    selAnchor:   SelectionPoint
    selCaret:    SelectionPoint
    selecting:   bool
}

private func applyThemeColors(wnd: *Wnd, colors: string)
{
    wnd.style.setStyleSheetColors(colors)
    for child in wnd.children do
        applyThemeColors(child, colors)
}

private func blockGap(kind: BlockKind)->f32
{
    switch kind
    {
    case .Heading1: return 26
    case .Heading2: return 22
    case .Heading3, .Heading4, .Heading5, .Heading6: return 16

    case .Code, .Table, .Html, .Math, .Quote, .TableOfContents,
         .AlertNote, .AlertTip, .AlertImportant,
         .AlertWarning, .AlertCaution: return 20

    case .Footnote: return 8
    case .Rule:     return 24
    default:        return 14
    }
}

private func htmlStyle(documentStyle: Style)->HtmlStyle
{
    var result: retval
    result.bodyFontSize = documentStyle.bodyFontSize
    result.codeFontSize = documentStyle.codeFontSize
    return result
}

private func streamBoundary(source: string)->u64
{
    var result      = 0'u64
    var lineStart   = 0'u64
    var fenceMarker = 0'u8
    var fenceLength = 0'u32
    var displayMath: bool
    var bracketMath: bool

    for value, index in source where value == '\n'
    {
        let line    = source[lineStart until index]
        let trimmed = Latin1.trim(line)
        let fence   = parseFence(line)
        if fence.found and !fenceMarker
        {
            fenceMarker = fence.marker
            fenceLength = fence.length
        }
        elif fence.found and fence.marker == fenceMarker and fence.length >= fenceLength and !@countof(fence.info)
        {
            fenceMarker = 0
        }
        elif !fenceMarker and Utf8.startsWith(trimmed, "$$")
        {
            let rest = trimmed[2 to]
            if !(@countof(rest) >= 2 and Utf8.endsWith(rest, "$$")) do
                displayMath = !displayMath
        }
        elif !fenceMarker and Utf8.startsWith(trimmed, "\\[") do
            bracketMath = true
        elif !fenceMarker and Utf8.startsWith(trimmed, "\\]") do
            bracketMath = false

        if !fenceMarker and !displayMath and !bracketMath and !@countof(trimmed) do
            result = index + 1
        lineStart = index + 1
    }

    return result
}

private func takeStreamSource(source: *String, sourceDone: bool)->String
{
    if source.isEmpty() do
        return {}

    var boundary = sourceDone ? source.length : streamBoundary(source.toString())
    if !boundary and source.length >= StreamCarryLimit
    {
        for value, index in source.toString() where value == '\n' do
            boundary = index + 1
        if !boundary do
            boundary = source.length
    }

    if !boundary do
        return {}

    let result    = String.from(source.toString()[0 until boundary])
    var remaining = String.from(source.toString()[boundary to])
    source[] = #move remaining
    return result
}

private impl View
{
    mtd documentGeometry()->{ x: f32, width: f32 }
    {
        let viewport = .scroll.paddedClientRect()
        let width    = Math.min(Math.max(viewport.width - .documentStyle.horizontalInset * 2, 280), .documentStyle.maxContentWidth)
        return {Math.max((viewport.width - width) * 0.5, 16), width}
    }

    mtd updateDocumentSize()
    {
        let viewport        = .scroll.paddedClientRect()
        let loadedHeight    = .contentHeight + .documentStyle.bottomInset
        var estimatedHeight = loadedHeight
        let consumed        = .bytesRead - .residentStart
        if consumed and (.bytesRead < .fileSize or .residentStart)
        {
            let residentHeight = Math.max(loadedHeight - .virtualOrigin, 1)
            .virtualHeight  = Math.max(residentHeight * cast(f32) .fileSize / cast(f32) consumed, .virtualHeight)
            estimatedHeight = Math.max(.virtualHeight, loadedHeight)
        }

        if .hasPendingTarget and .pendingTargetOffset != Swag.U64.Max and .fileSize do
            .pendingTarget = .virtualHeight * cast(f32) .pendingTargetOffset / cast(f32) .fileSize

        let height   = Math.max(estimatedHeight, viewport.height)
        let position = .scroll.scrollPosition()
        .scroll.setScrollSize(viewport.width, height)
        .scroll.setScrollPos(position)
    }

    mtd placeBlock(block: *VisualBlock, x, width: f32, y: *f32)
    {
        block.wnd.setPosition({x, y[], width, 0})
        if block.kind == .Math do
            block.wnd.resize(width, (cast(*MathView) block.wnd).preferredHeight())
        elif block.kind == .Table do
            block.wnd.resize(width, block.table!.preferredHeight(width))
        elif block.kind == .Html do
            block.wnd.resize(width, block.html!.embeddedHeight(width))
        else do
            block.wnd.resize(width, block.inline!.preferredHeight(width))

        y[] += block.wnd.position.height + blockGap(block.kind)
    }

    mtd layoutDocument()
    {
        let viewport = .scroll.paddedClientRect()
        if viewport.width <= 0 do
            return

        let geometry = .documentGeometry()
        var y        = .virtualOrigin + .documentStyle.topInset
        for &block in .blocks do
            .placeBlock(block, geometry.x, geometry.width, &y)
        .contentHeight = y
        .updateDocumentSize()
    }

    mtd appendBlock(block: Block)
    {
        var visual: VisualBlock
        visual.kind       = block.kind
        visual.searchText = block.text
        visual.orderIndex = .inlineOrder.count
        if block.kind == .Math
        {
            let math = MathView.create(me, .body, block.text.toString())
            if math
            {
                visual.wnd = math!
                if !.documentThemeColors.isEmpty() do
                    applyThemeColors(visual.wnd, .documentThemeColors.toString())
                .blocks.add(visual)
                let geometry = .documentGeometry()
                .placeBlock(.blocks.backPtr(), geometry.x, geometry.width, &.contentHeight)
                .updateDocumentSize()
                return
            }
        }
        elif block.kind == .Table
        {
            let table = TableView.create(me, .body, block.text.toString())
            visual.wnd   = table
            visual.table = table
            if !.documentThemeColors.isEmpty() do
                applyThemeColors(visual.wnd, .documentThemeColors.toString())
            .blocks.add(visual)
            let geometry = .documentGeometry()
            .placeBlock(.blocks.backPtr(), geometry.x, geometry.width, &.contentHeight)
            .updateDocumentSize()
            return
        }
        elif block.kind == .Html
        {
            let basePath = .fileName.isEmpty() ? "" : (Path.directoryName(.fileName.toString()) orelse "")
            let html     = HtmlView.createEmbedded(.body, block.text.toString(), basePath, htmlStyle(.documentStyle))
            html.sigLinkActivated += func|markdown = me|(document, target)
            {
                discard document
                markdown.sigLinkActivated.call(markdown, target)
            }
            visual.wnd        = html
            visual.html       = html
            visual.searchText = html.document.textContent(0)
            if !.documentThemeColors.isEmpty() do
                applyThemeColors(visual.wnd, .documentThemeColors.toString())
            .blocks.add(visual)
            let geometry = .documentGeometry()
            .placeBlock(.blocks.backPtr(), geometry.x, geometry.width, &.contentHeight)
            .updateDocumentSize()
            return
        }

        let inline = InlineView.create(me, .body, block.text.toString(), block.kind)
        visual.wnd    = inline
        visual.inline = inline
        if !.documentThemeColors.isEmpty() do
            applyThemeColors(visual.wnd, .documentThemeColors.toString())
        .blocks.add(visual)

        let geometry = .documentGeometry()
        .placeBlock(.blocks.backPtr(), geometry.x, geometry.width, &.contentHeight)
        .updateDocumentSize()
    }

    mtd needsMore()->bool
    {
        if .pendingIndex >= .pendingBlocks.count and .sourceDone and .sourceCarry.isEmpty() do
            return false
        if .blocks.isEmpty() do
            return true
        if .bytesRead - .residentStart >= ResidentSourceSize and !.jumpToEnd and !.hasPendingTarget do
            return false
        if .jumpToEnd or .hasPendingTarget do
            return true
        let viewport = .scroll.paddedClientRect()
        return .scroll.scrollPosition().y + viewport.height * StreamLookAhead >= .contentHeight
    }

    mtd scheduleMore()
    {
        if .loadTimer or (!.pendingSeek and !.needsMore()) do
            return
        .loadTimer = .addTimer(8'ms)
    }

    mtd readSource()
    {
        if .sourceDone do
            return

        let chunk = catch .stream.readUtf8Chunk(StreamChunkSize) as readError
        if readError != null
        {
            .reportLoadFailure(Errors.message(readError))
            return
        }

        if Utf8.indexOf(chunk.toSlice(), 0'rune) != Swag.U64.Max
        {
            .reportLoadFailure(strings().markdown_NotUtf8)
            return
        }

        if chunk.isEmpty()
        {
            .sourceDone = true
            .bytesRead  = .fileSize
            .stream.close()
            return
        }

        .sourceCarry += chunk
        let position = catch .stream.position() as positionError
        if positionError == null do
            .bytesRead = position
    }

    mtd reportLoadFailure(reason: string)
    {
        .failureReason = reason
        if .failureReason.isEmpty() do
            .failureReason = strings().markdown_ReadFailed
        .sigLoadFailed.call(me, .failureReason.toString())
        .sourceCarry = strings().markdown_LoadFailed
        .sourceDone  = true
        .bytesRead   = .fileSize
        .stream.close()
    }

    mtd preparePending()->bool
    {
        if .pendingIndex < .pendingBlocks.count do
            return true

        .pendingBlocks.clear()
        .pendingIndex = 0
        var source = takeStreamSource(&.sourceCarry, .sourceDone)
        if source.isEmpty()
        {
            .readSource()
            source = takeStreamSource(&.sourceCarry, .sourceDone)
        }

        if source.isEmpty() do
            return false

        .pendingBlocks = parseBlocks(source.toString())
        return !.pendingBlocks.isEmpty()
    }

    mtd streamStep()
    {
        var stopwatch: Time.Stopwatch
        stopwatch.start()
        var blockCount = 0'u32
        while .needsMore() and blockCount < StreamBlockBudget
        {
            if !.preparePending() do
                break
            .appendBlock(#move .pendingBlocks[.pendingIndex])
            .pendingIndex += 1
            blockCount    += 1
            if stopwatch.elapsedMicroseconds() >= StreamFrameBudget do
                break
        }

        if .sourceDone and .sourceCarry.isEmpty() and .pendingIndex >= .pendingBlocks.count and .blocks.isEmpty()
        {
            var empty: Block
            empty.kind = .Paragraph
            empty.text = strings().markdown_EmptyDocument
            .appendBlock(#move empty)
        }

        if .hasPendingTarget and (.pendingTarget + .scroll.paddedClientRect().height <= .contentHeight or !.hasUnloadedSource())
        {
            .hasPendingTarget    = false
            .pendingTargetOffset = Swag.U64.Max
            let position = .scroll.scrollPosition()
            .scroll.setScrollPos(position.x, .pendingTarget)
        }

        if !.pendingSearch.isEmpty() and .findText(.pendingSearch.toString()) do
            .pendingSearch.clear()

        if .hasUnloadedSource() do
            return

        if .jumpToEnd
        {
            .jumpToEnd = false
            let position = .scroll.scrollPosition()
            .scroll.setScrollPos(position.x, .scroll.scrollableClientRect().height)
        }
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

    mtd handleDocumentKey(evt: *KeyEvent)->bool
    {
        if evt.kind != .Pressed do
            return false

        // What a read-only document can give the clipboard comes first: the same three keys every
        // other rendered document in the toolkit binds.
        if evt.key == .C and evt.modifiers == .Control do
            return .copySelection()
        if evt.key == .A and evt.modifiers == .Control
        {
            .selectAll()
            return true
        }

        if evt.key == .Escape and evt.modifiers == .None and .hasSelection()
        {
            .clearSelection()
            return true
        }

        let position = .scroll.scrollPosition()
        let viewport = .scroll.paddedClientRect()
        let page     = Math.max(viewport.height - .scroll.verticalScrollStep, .scroll.verticalScrollStep)
        var target   = .hasPendingTarget ? .pendingTarget : position.y
        var forward: bool
        switch evt.key
        {
        case .Up where evt.modifiers == .None:
            target -= .scroll.verticalScrollStep

        case .Down where evt.modifiers == .None:
            target  += .scroll.verticalScrollStep
            forward = true

        case .PageUp where evt.modifiers == .None:
            target -= page

        case .PageDown where evt.modifiers == .None:
            target  += page
            forward = true

        case .Home where evt.modifiers == .None or evt.modifiers == .Control:
            .jumpToEnd           = false
            .hasPendingTarget    = false
            .pendingTargetOffset = Swag.U64.Max
            if .residentStart do
                discard .revealFileOffset(0, "")
            .scroll.setScrollPos(position.x, 0)
            return true

        case .End where evt.modifiers == .None or evt.modifiers == .Control:
            .hasPendingTarget = false
            if .fileSize and (.residentStart + (.bytesRead - .residentStart) < .fileSize)
            {
                let start = .fileSize > StreamCarryLimit ? .fileSize - StreamCarryLimit : 0
                .jumpToEnd = true
                discard .revealFileOffset(start, "")
            }
            else do
                .scroll.setScrollPos(position.x, .contentHeight)
            return true

        case .Space where evt.modifiers == .None:
            target  += page
            forward = true

        case .Space where evt.modifiers == .Shift:
            target -= page

        default:
            return false
        }

        .jumpToEnd = false
        if forward and .hasUnloadedSource() and target + viewport.height > .contentHeight
        {
            if .bytesRead - .residentStart >= ResidentSourceSize and .virtualHeight > 0 and .fileSize
            {
                let offset = cast(u64) (Math.clamp(target / .virtualHeight, 0, 1) * cast(f32) .fileSize)
                discard .revealFileOffset(offset, "")
                return true
            }

            .hasPendingTarget    = true
            .pendingTarget       = target
            .pendingTargetOffset = Swag.U64.Max
            .scheduleMore()
            return true
        }

        .hasPendingTarget = false
        .scroll.setScrollPos(position.x, target)
        return true
    }

    // Adds one text view to the reading order and returns the index it took.
    mtd registerInline(view: *InlineView)->u64
    {
        .inlineOrder.add(view)
        return .inlineOrder.count - 1
    }

    // Repaints every text view between two reading-order positions, inclusive.
    mtd invalidateInlines(one, other: u64)
    {
        if .inlineOrder.isEmpty() do
            return
        let first = Math.min(one, other)
        if first >= .inlineOrder.count do
            return
        let last = Math.min(Math.max(one, other), .inlineOrder.count - 1)
        for index in first to last do
            .inlineOrder[index].invalidate()
    }

    // Returns the document position nearest to a surface point.
    //
    // Every text view competes for the point, and the one whose rectangle the pointer is inside —
    // or vertically nearest to — wins, so a drag that leaves the column keeps extending along the
    // block it is beside rather than snapping to the top of the document.
    mtd documentPositionAt(surfacePos: Math.Point)->{ view: u64, offset: u64, has: bool }
    {
        var result: retval
        var best = Swag.F32.Max

        // The element is the view: dereferencing it would copy the window, and a window
        // holds a counted reference on its theme that the copy would release on the way out.
        for view, index in .inlineOrder
        {
            let rect = view.surfaceRect()

            var dx = 0'f32
            if surfacePos.x < rect.x do
                dx = rect.x - surfacePos.x
            elif surfacePos.x > rect.right() do
                dx = surfacePos.x - rect.right()

            var dy = 0'f32
            if surfacePos.y < rect.y do
                dy = rect.y - surfacePos.y
            elif surfacePos.y > rect.bottom() do
                dy = surfacePos.y - rect.bottom()

            let score = dy * 4096 + dx
            if score >= best do
                continue

            best          = score
            result.view   = index
            result.offset = view.textPositionAt({surfacePos.x - rect.x, surfacePos.y - rect.y}).offset
            result.has    = true
        }

        return result
    }

    mtd applyDocumentStyle()
    {
        // Arrow navigation advances by the same minimum line height used by body text. Page
        // navigation remains viewport-relative in handleDocumentKey.
        .scroll.verticalScrollStep = .theme().createDefaultFont(.documentStyle.bodyFontSize).height * .documentStyle.lineHeight
        for &block in .blocks
        {
            if block.inline
            {
                block.inline!.layoutWidth = 0
                if block.kind >= .Heading1 and block.kind <= .Heading6 do
                    block.inline!.horizontalAlignment = .documentStyle.headingAlignment
                elif block.kind == .Paragraph do
                    block.inline!.horizontalAlignment = .documentStyle.paragraphAlignment
            }

            if block.table do
                block.table!.layoutWidth = 0
            if block.html do
                block.html!.setDocumentStyle(htmlStyle(.documentStyle))
        }

        .layoutDocument()
        .invalidate()
    }
}

impl View
{
    // Creates an empty Markdown document view.
    #[Swag.Discardable]
    func create(contentParent: *Wnd, documentStyle: Style = {})->*View
    {
        let result = Wnd.create'View(contentParent, "gui.markdown")
        result.backgroundStyle = .View
        result.focusPolicy     = .Tab
        result.wndFlags        |= .NoFocusRing
        result.documentStyle   = documentStyle
        result.contentHeight   = documentStyle.topInset

        result.scroll           = Wnd.create'ScrollWnd(result, "", {})
        result.scroll.dockStyle = .Center
        result.scroll.updateFlags(.DisableHorizontal)
        result.scroll.verticalScrollStep       = result.theme().createDefaultFont(documentStyle.bodyFontSize).height * documentStyle.lineHeight
        result.body                            = result.scroll.createView'Wnd()
        result.body.backgroundStyle            = .View
        result.scroll.sigScrollPositionChanged += func|view = result|(scroll, oldPosition, newPosition)
        {
            discard scroll
            if view.jumpToEnd or view.repositioning do
                return

            // A direct scrollbar gesture supersedes a target that is still being materialized.
            // Keeping the old target here lets its next timer pull the reader back after a
            // reversal, which makes resident windows appear to oscillate.
            let supersededTarget = view.hasPendingTarget and view.pendingSearch.isEmpty()
            if supersededTarget
            {
                view.hasPendingTarget    = false
                view.pendingTargetOffset = Swag.U64.Max
            }

            let viewport                 = view.scroll.paddedClientRect()
            let beforeResident           = newPosition.y + viewport.height < view.virtualOrigin
            let approachingResidentStart = view.residentStart and newPosition.y < oldPosition.y and newPosition.y < view.virtualOrigin + viewport.height * StreamLookAhead
            if view.virtualHeight > 0 and (supersededTarget or !view.blocks.isEmpty()) and view.pendingSearch.isEmpty() and (beforeResident or approachingResidentStart or newPosition.y > view.contentHeight)
            {
                let ratio = Math.clamp(newPosition.y / view.virtualHeight, 0, 1)
                view.pendingSeekOffset = cast(u64) (ratio * cast(f32) view.fileSize)
                view.pendingSeek       = true
            }
            else do
                view.pendingSeek = false

            view.scheduleMore()
        }

        // The scroll viewport receives its final size during the parent's layout pass. Relayout
        // from that child resize so document centering never uses the previous window width.
        result.scroll.hookOnEvent = func|view = result|(wnd, evt)
        {
            discard wnd
            if evt is ResizeEvent
            {
                view.layoutDocument()
                view.scheduleMore()
            }

            return false
        }
        result.applyLayout()
        result.layoutDocument()
        result.setInitialFocus(result)
        return result
    }

    // Creates a view and renders the complete Markdown source.
    func createText(contentParent: *Wnd, source: string, documentStyle: Style = {})->*View
    {
        let result = .create(contentParent, documentStyle)
        result.sourceDone = true
        let parsed = parseBlocks(source)
        for &block in parsed do
            result.appendBlock(#move block[])

        if result.blocks.isEmpty()
        {
            var empty: Block
            empty.kind = .Paragraph
            empty.text = strings().markdown_EmptyDocument
            result.appendBlock(#move empty)
        }

        return result
    }

    // Creates a view and progressively loads a UTF-8 Markdown file.
    //
    // File-open and decoding failures remain visible in the document and are also exposed through
    // [[Gui.Markdown.View.failureReason]] and [[Gui.Markdown.View.sigLoadFailed]].
    func createFile(contentParent: *Wnd, fileName: string, documentStyle: Style = {})->*View
    {
        let result = .create(contentParent, documentStyle)
        result.fileName = fileName
        result.stream   = catch File.openRead(fileName) as openError
        if openError != null
        {
            result.reportLoadFailure(Errors.message(openError))
        }
        else
        {
            let size = catch result.stream.size() as sizeError
            if sizeError == null do
                result.fileSize = size
            else do
                result.reportLoadFailure(Errors.message(sizeError))
        }

        result.scheduleMore()
        return result
    }

    // Replaces the document metrics while keeping colors and font faces bound to the active theme.
    mtd setDocumentStyle(documentStyle: Style)
    {
        .documentStyle = documentStyle
        .applyDocumentStyle()
    }

    // Applies document-local theme colors to the complete view, including blocks created later
    // while a file is streaming. Pass an empty sheet to resume the application theme.
    mtd setDocumentThemeColors(styleSheetColors: string)
    {
        .documentThemeColors = styleSheetColors
        applyThemeColors(me, styleSheetColors)
    }

    // Reports whether progressive file-loading work is currently scheduled.
    mtd const isLoading()->bool => .loadTimer != null

    // Reports whether file source remains to be read, parsed, or displayed.
    mtd const hasUnloadedSource()->bool
    {
        return !.sourceDone or !.sourceCarry.isEmpty() or .pendingIndex < .pendingBlocks.count
    }

    // Reports the laid-out height of the source rendered so far.
    mtd const loadedDocumentHeight()->f32 => .contentHeight + .documentStyle.bottomInset

    // Reports whether the reader selected something.
    mtd const hasSelection()->bool => .selectionRange().has

    // Empties the selection.
    mtd clearSelection()
    {
        let range = .selectionRange()
        .selAnchor = {}
        .selCaret  = {}
        .selecting = false
        if range.has do
            .invalidateInlines(range.startView, range.endView)
    }

    // Selects the whole rendered document.
    //
    // What is rendered is what a streamed file has materialized so far, which is what the reader
    // can see; the rest of the file has no position to select.
    mtd selectAll()
    {
        if .inlineOrder.isEmpty() do
            return
        .selAnchor = {0, 0}
        .selCaret  = {.inlineOrder.count - 1, .inlineOrder[.inlineOrder.count - 1].textLength}
        .selecting = false
        .invalidateInlines(0, .inlineOrder.count - 1)
    }

    // Returns the selected text, as one line per block and one tab between table cells.
    //
    // Inline formatting resolves to the words it decorated, a formula to its mathematical source,
    // and an embedded page to its text. What comes back is the document as it reads, not the
    // Markdown that produced it.
    mtd selectedText()->String
    {
        var result: retval
        let range = .selectionRange()
        if !range.has do
            return result

        var started: bool
        for &block in .blocks
        {
            if block.inline
            {
                let piece = .selectionInInline(block.inline!.orderIndex)
                if !piece.has do
                    continue
                if started do
                    result += "\n"
                result  += block.inline!.textSlice(piece.start, piece.end)
                started = true
                continue
            }

            if block.table
            {
                var lastRow = Swag.U32.Max
                for &cell in block.table!.cells
                {
                    let piece = .selectionInInline(cell.view.orderIndex)
                    if !piece.has do
                        continue
                    if lastRow == Swag.U32.Max
                    {
                        if started do
                            result += "\n"
                    }
                    elif cell.row != lastRow do
                        result += "\n"
                    else do
                        result += "\t"

                    result  += cell.view.textSlice(piece.start, piece.end)
                    lastRow = cell.row
                    started = true
                }

                continue
            }

            // A block with no text view of its own — a formula, an embedded page — is taken whole
            // when the selection runs across it, and left alone when it merely touches an edge.
            if range.startView < block.orderIndex and range.endView >= block.orderIndex and !block.searchText.isEmpty()
            {
                if started do
                    result += "\n"
                result  += block.searchText
                started = true
            }
        }

        return result
    }

    // Puts the selected text on the clipboard, and reports whether there was one.
    mtd copySelection()->bool
    {
        if !.hasSelection() do
            return false
        let text = .selectedText()
        if text.isEmpty() do
            return false
        Clipboard.addString(text.toString())
        return true
    }

    const CtxCopy      = "Markdown.CtxCopy"          // Command the context menu's copy entry posts.
    const CtxSelectAll = "Markdown.CtxSelectAll"     // Command the context menu's select-all entry posts.

    // Offers the reading vocabulary at `surfacePos`: what a read-only document can give the
    // clipboard, with the same shortcuts the keyboard already binds.
    mtd showContextMenu(surfacePos: Math.Point)
    {
        .setFocus()
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

    // Scrolls to the next rendered block containing `text`, wrapping once at the end.
    mtd findText(text: string)->bool
    {
        if !@countof(text) or .blocks.isEmpty() do
            return false

        for &block in .blocks
        {
            if block.inline do
                block.inline!.clearSearchHighlight()
            if block.table do
                block.table!.clearSearchHighlight()
            if block.html do
                block.html!.clearSearchHighlight()
        }

        let first = .searchBlockIndex == Swag.U64.Max ? 0 : (.searchBlockIndex + 1) % .blocks.count
        for offset in .blocks.count
        {
            let index = (first + offset) % .blocks.count
            let block = &.blocks[index]
            var found: bool
            if block.inline do
                found = block.inline!.highlightText(text)
            elif block.table do
                found = block.table!.highlightText(text)
            elif block.html do
                found = block.html!.findText(text)
            if !found do
                found = Utf8.indexOf(block.searchText.toString(), text, 0, .Latin1NoCase) != Swag.U64.Max
            if !found do
                continue

            .searchBlockIndex = index
            let position = .scroll.scrollPosition()
            .scroll.setScrollPos(position.x, block.wnd.position.y - .documentStyle.topInset)
            block.wnd.setFocus()
            return true
        }

        return false
    }

    // Repositions the streamed document at a byte offset and reveals `text` as soon as its block
    // is materialized, without parsing the preceding bytes.
    mtd revealFileOffset(offset: u64, text: string)->bool
    {
        .stopLoading()

        // The positions a selection is expressed in name views that are about to be destroyed,
        // and the document they addressed is being rebuilt from another offset of the file.
        .selAnchor = {}
        .selCaret  = {}
        .selecting = false
        .inlineOrder.clear()

        for &block in .blocks do
            block.wnd.destroy()
        .blocks.clear()
        .pendingBlocks.clear()
        .pendingIndex = 0
        .sourceCarry.clear()
        .sourceDone       = false
        .searchBlockIndex = Swag.U64.Max
        .pendingSearch    = text

        let requested = Math.min(offset, .fileSize)
        let start     = requested > RevealContextSize ? requested - RevealContextSize : 0
        for adjustment in 4
        {
            .stream = catch File.openRead(.fileName.toString()) as openError
            if openError != null do
                return false
            let actual = Math.min(start + adjustment, .fileSize)
            discard catch .stream.seek(.Begin, actual)
            var chunk = catch .stream.readUtf8Chunk(RevealChunkSize) as readError
            if readError != null
            {
                .stream.close()
                continue
            }

            let localTarget = requested > actual ? Math.min(requested - actual, chunk.length) : 0

            // Start on a complete block near the beginning of the context window, not on the
            // last block before the target. Keeping that leading source resident is what lets a
            // reader move upward without immediately leaving every materialized block behind.
            let probeEnd = localTarget > ReverseContextSize ? localTarget - ReverseContextSize : Math.min(localTarget, StreamChunkSize)
            var boundary = streamBoundary(chunk.toString()[0 until probeEnd])
            if !boundary and localTarget > probeEnd do
                boundary = streamBoundary(chunk.toString()[0 until localTarget])

            let previousHeight = Math.max(.virtualHeight, .scroll.scrollableClientRect().height)
            .residentStart       = actual + boundary
            .bytesRead           = actual + chunk.length
            .sourceCarry         = String.from(chunk.toString()[boundary to])
            .sourceDone          = .bytesRead >= .fileSize
            .virtualHeight       = Math.max(previousHeight, .scroll.paddedClientRect().height)
            .virtualOrigin       = .fileSize ? .virtualHeight * cast(f32) .residentStart / cast(f32) .fileSize : 0
            .contentHeight       = .virtualOrigin + .documentStyle.topInset
            .pendingTarget       = .fileSize ? .virtualHeight * cast(f32) requested / cast(f32) .fileSize : 0
            .hasPendingTarget    = !.jumpToEnd
            .pendingTargetOffset = .hasPendingTarget ? requested : Swag.U64.Max
            .repositioning       = true
            defer .repositioning = false
            .layoutDocument()
            if !.jumpToEnd do
                .scroll.setScrollPos(0, .virtualOrigin)
            .scheduleMore()
            return true
        }

        return false
    }
}

// What the pointer gesture drives, and what a text view paints its own selection from.
//
// A selection spans windows, so the document owns both ends of it while each text view owns
// the glyphs: these are the two halves talking to each other, not a surface a consumer uses.
internal impl View
{
    // Reports whether a selection drag is in flight.
    mtd const isSelecting()->bool => .selecting

    // Starts a selection drag at one position of one text view.
    mtd beginSelection(view: *InlineView, offset: u64)
    {
        .setFocus()
        .clearSelection()
        .selAnchor = {view.orderIndex, offset}
        .selCaret  = .selAnchor
        .selecting = true
    }

    // Moves the free end of the drag to the document position under a surface point.
    mtd extendSelection(surfacePos: Math.Point)
    {
        if !.selecting do
            return
        let hit = .documentPositionAt(surfacePos)
        if !hit.has or (hit.view == .selCaret.view and hit.offset == .selCaret.offset) do
            return

        // Both the range the caret left and the range it now covers have to be repainted, so the
        // union of where it was, where it is, and the anchor is what the drag touches.
        let previous = .selCaret
        .selCaret = {hit.view, hit.offset}
        let low  = Math.min(Math.min(previous.view, hit.view), .selAnchor.view)
        let high = Math.max(Math.max(previous.view, hit.view), .selAnchor.view)
        .invalidateInlines(low, high)
    }

    // Ends a selection drag, keeping what it selected.
    mtd endSelection()
    {
        .selecting = false
    }

    // Selects the word around one position, the double-click gesture.
    mtd selectWordAt(view: *InlineView, offset: u64)
    {
        .setFocus()
        .clearSelection()
        let word = view.wordRangeAt(offset)
        .selAnchor = {view.orderIndex, word.start}
        .selCaret  = {view.orderIndex, word.end}
        .selecting = false
        view.invalidate()
    }

    // Returns the selection normalized to reading order, or `has == false` when it is empty.
    mtd const selectionRange()->{ startView: u64, startOffset: u64, endView: u64, endOffset: u64, has: bool }
    {
        var result: retval
        if .selAnchor.view == Swag.U64.Max or .selCaret.view == Swag.U64.Max do
            return result
        if .selAnchor.view == .selCaret.view and .selAnchor.offset == .selCaret.offset do
            return result

        let anchorFirst = .selAnchor.view < .selCaret.view or (.selAnchor.view == .selCaret.view and .selAnchor.offset < .selCaret.offset)
        result.startView   = anchorFirst ? .selAnchor.view : .selCaret.view
        result.startOffset = anchorFirst ? .selAnchor.offset : .selCaret.offset
        result.endView     = anchorFirst ? .selCaret.view : .selAnchor.view
        result.endOffset   = anchorFirst ? .selCaret.offset : .selAnchor.offset
        result.has         = true
        return result
    }

    // Returns the part of the selection falling inside one text view, in that view's own text
    // coordinates. This is what a view paints its selection from.
    mtd const selectionInInline(orderIndex: u64)->{ start: u64, end: u64, has: bool }
    {
        var result: retval
        let range = .selectionRange()
        if !range.has or orderIndex < range.startView or orderIndex > range.endView do
            return result

        result.start = orderIndex == range.startView ? range.startOffset : 0
        result.end   = orderIndex == range.endView ? range.endOffset : .inlineOrder[orderIndex].textLength
        result.has   = result.end > result.start
        return result
    }
}

internal impl IWnd for View
{
    mtd impl onThemeEvent(evt: *ThemeEvent)
    {
        if @isset(.scroll) do
            .applyDocumentStyle()
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if !.handleDocumentKey(evt) do
            evt.accepted = false
    }

    // The ground between and around the blocks answers for the document as a whole: a press on it
    // drops the selection the way every document viewer reads, and the menu is the same one a
    // block offers.
    mtd impl onMouseEvent(evt: *MouseEvent)
    {
        switch evt.kind
        {
        case .Pressed where evt.button == .Left:
            .setFocus()
            .clearSelection()

        case .Pressed where evt.button == .Right:
            .showContextMenu(evt.surfacePos)

        default:
            evt.accepted = false
        }
    }

    mtd impl onDestroyEvent(evt: *DestroyEvent)
    {
        .stopLoading()
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
        if .pendingSeek
        {
            let offset = .pendingSeekOffset
            .pendingSeek = false
            discard .revealFileOffset(offset, "")
            return
        }

        .streamStep()
        .scheduleMore()
    }
}
