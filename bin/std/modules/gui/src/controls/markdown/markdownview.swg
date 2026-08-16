#global public

using Core, Pixel

private const MarkdownStreamChunkSize = 8 * 1024'u64
private const MarkdownStreamCarryLimit = 16 * 1024'u64
private const MarkdownStreamLookAhead = 2.0
private const MarkdownStreamFrameBudget = 3_000'u64
private const MarkdownStreamBlockBudget = 8'u32

// Controls the reading measure and typography of a [[Gui.MarkdownView]].
//
// Colors and font faces always resolve from the window's active [[Gui.Theme]], so a document
// follows application palettes, local theme styles, and live theme-sheet changes.
struct MarkdownStyle
{
    public
    {
        maxContentWidth: f32 = 860     // Widest document column, in logical pixels.
        horizontalInset: f32 = 48      // Minimum room kept on each side of the document column.
        topInset:        f32 = 38      // Space before the first document block.
        bottomInset:     f32 = 34      // Space after the last document block.
        bodyFontSize:    u32 = 16      // Body-text draw size, in logical pixels.
        codeFontSize:    u32 = 14      // Fixed-width code and table draw size, in logical pixels.
        mathFontSize:    u32 = 22      // Base draw size of Pixel mathematical layout.
    }
}

impl MarkdownStyle
{
    // Returns the document style that follows the active GUI theme.
    func theme()->MarkdownStyle => {}
}

#[Swag.NoDoc]
struct MarkdownVisualBlock
{
    wnd:    *Wnd = undefined
    inline: #null *MarkdownInlineView
    table:  #null *MarkdownTableView
    kind:   MarkdownBlockKind
}

// Displays Markdown as a themed, read-only document with progressive UTF-8 file loading.
//
// [[Gui.MarkdownView.createText]] renders in-memory source, while
// [[Gui.MarkdownView.createFile]] streams a file without tying the renderer to an application.
// Block and inline mathematics use [[Pixel.MathExpression]] and the active theme font.
struct MarkdownView
{
    public
    {
        using wnd: Wnd     // Embedded window behavior and presentation.

        sigLinkActivated: SigArray'func||(*MarkdownView, string)     // Emitted when a rendered link is activated.

        public readonly
        documentStyle: MarkdownStyle     // Active document typography and reading measure.

        internal
        {
            #[Swag.Late]
            {
                scroll: *ScrollWnd
                body:   *Wnd
            }

            stream:           File.FileStream
            fileSize:         u64
            bytesRead:        u64
            sourceCarry:      String
            sourceDone:       bool
            pendingBlocks:    Array'MarkdownBlock
            pendingIndex:     u64
            loadTimer:        #null *Timer
            contentHeight:    f32
            jumpToEnd:        bool
            hasPendingTarget: bool
            pendingTarget:    f32
            blocks:           Array'MarkdownVisualBlock
        }
    }
}

private func markdownBlockGap(kind: MarkdownBlockKind)->f32
{
    switch kind
    {
    case .Heading1:                                  return 26
    case .Heading2:                                  return 22
    case .Heading3, .Heading4, .Heading5, .Heading6: return 16
    case .Code, .Table, .Math, .Quote, .TableOfContents,
         .AlertNote, .AlertTip, .AlertImportant,
         .AlertWarning, .AlertCaution:                return 20
    case .Footnote:                                  return 8
    case .Rule:                                      return 24
    default:                                         return 14
    }
}

private func markdownStreamBoundary(source: string)->u64
{
    var result      = 0'u64
    var lineStart   = 0'u64
    var fenceMarker = 0'u8
    var displayMath: bool
    var bracketMath: bool

    for value, index in source where value == '\n'
    {
        let line    = source[lineStart until index]
        let trimmed = Latin1.trim(line)
        let fence   = markdownFence(line)
        if fence.found and (!fenceMarker or fence.marker == fenceMarker)
        {
            fenceMarker = fenceMarker ? 0 : fence.marker
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

private func takeMarkdownStreamSource(source: *String, sourceDone: bool)->String
{
    if source.isEmpty() do
        return {}

    var boundary = sourceDone ? source.length : markdownStreamBoundary(source.toString())
    if !boundary and source.length >= MarkdownStreamCarryLimit
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

private impl MarkdownView
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
        if .bytesRead and .bytesRead < .fileSize do
            estimatedHeight = Math.max(loadedHeight * cast(f32) .fileSize / cast(f32) .bytesRead, loadedHeight)
        let height   = Math.max(estimatedHeight, viewport.height)
        let position = .scroll.scrollPosition()
        .body.resize(viewport.width, height)
        .scroll.setScrollSize(viewport.width, height)
        .scroll.setScrollPos(position)
    }

    mtd placeBlock(block: *MarkdownVisualBlock, x, width: f32, y: *f32)
    {
        block.wnd.setPosition({x, y[], width, 0})
        if block.kind == .Math do
            block.wnd.resize(width, (cast(*MarkdownMathView) block.wnd).preferredHeight())
        elif block.kind == .Table do
            block.wnd.resize(width, block.table!.preferredHeight(width))
        else do
            block.wnd.resize(width, block.inline!.preferredHeight(width))

        y[] += block.wnd.position.height + markdownBlockGap(block.kind)
    }

    mtd layoutDocument()
    {
        let viewport = .scroll.paddedClientRect()
        if viewport.width <= 0 do
            return

        let geometry = .documentGeometry()
        var y        = .documentStyle.topInset
        for &block in .blocks do
            .placeBlock(block, geometry.x, geometry.width, &y)
        .contentHeight = y
        .updateDocumentSize()
    }

    mtd appendBlock(block: MarkdownBlock)
    {
        var visual: MarkdownVisualBlock
        visual.kind = block.kind
        if block.kind == .Math
        {
            let math = MarkdownMathView.create(me, .body, block.text.toString())
            if math
            {
                visual.wnd = math!
                .blocks.add(visual)
                let geometry = .documentGeometry()
                .placeBlock(.blocks.backPtr(), geometry.x, geometry.width, &.contentHeight)
                .updateDocumentSize()
                return
            }
        }
        elif block.kind == .Table
        {
            let table = MarkdownTableView.create(me, .body, block.text.toString())
            visual.wnd   = table
            visual.table = table
            .blocks.add(visual)
            let geometry = .documentGeometry()
            .placeBlock(.blocks.backPtr(), geometry.x, geometry.width, &.contentHeight)
            .updateDocumentSize()
            return
        }

        let inline = MarkdownInlineView.create(me, .body, block.text.toString(), block.kind)
        visual.wnd    = inline
        visual.inline = inline
        .blocks.add(visual)

        let geometry = .documentGeometry()
        .placeBlock(.blocks.backPtr(), geometry.x, geometry.width, &.contentHeight)
        .updateDocumentSize()
    }

    mtd needsMore()->bool
    {
        if .pendingIndex >= .pendingBlocks.count and .sourceDone and .sourceCarry.isEmpty() do
            return false
        if .jumpToEnd or .hasPendingTarget do
            return true
        let viewport = .scroll.paddedClientRect()
        return .scroll.scrollPosition().y + viewport.height * MarkdownStreamLookAhead >= .contentHeight
    }

    mtd scheduleMore()
    {
        if .loadTimer or !.needsMore() do
            return
        .loadTimer = .addTimer(8'ms)
    }

    mtd readSource()
    {
        if .sourceDone do
            return

        let chunk = catch .stream.readUtf8Chunk(MarkdownStreamChunkSize) as readError
        if readError != null or Utf8.indexOf(chunk.toSlice(), 0'rune) != Swag.U64.Max
        {
            .sourceCarry = "Unable to read this Markdown document."
            .sourceDone  = true
            .bytesRead   = .fileSize
            .stream.close()
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

    mtd preparePending()->bool
    {
        if .pendingIndex < .pendingBlocks.count do
            return true

        .pendingBlocks.clear()
        .pendingIndex = 0
        var source = takeMarkdownStreamSource(&.sourceCarry, .sourceDone)
        if source.isEmpty()
        {
            .readSource()
            source = takeMarkdownStreamSource(&.sourceCarry, .sourceDone)
        }

        if source.isEmpty() do
            return false

        .pendingBlocks = parseMarkdownBlocks(source.toString())
        return !.pendingBlocks.isEmpty()
    }

    mtd streamStep()
    {
        var stopwatch: Time.Stopwatch
        stopwatch.start()
        var blockCount = 0'u32
        while .needsMore() and blockCount < MarkdownStreamBlockBudget
        {
            if !.preparePending() do
                break
            .appendBlock(#move .pendingBlocks[.pendingIndex])
            .pendingIndex += 1
            blockCount    += 1
            if stopwatch.elapsedMicroseconds() >= MarkdownStreamFrameBudget do
                break
        }

        if .sourceDone and .sourceCarry.isEmpty() and .pendingIndex >= .pendingBlocks.count and .blocks.isEmpty()
        {
            var empty: MarkdownBlock
            empty.kind = .Paragraph
            empty.text = "This Markdown document is empty."
            .appendBlock(#move empty)
        }

        if .hasPendingTarget and (.pendingTarget + .scroll.paddedClientRect().height <= .contentHeight or !.isLoading())
        {
            .hasPendingTarget = false
            let position      = .scroll.scrollPosition()
            .scroll.setScrollPos(position.x, .pendingTarget)
        }

        if .isLoading() do
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

        let position = .scroll.scrollPosition()
        let viewport = .scroll.paddedClientRect()
        let page     = Math.max(viewport.height - .scroll.verticalScrollStep, .scroll.verticalScrollStep)
        var target   = .hasPendingTarget ? .pendingTarget : position.y
        var forward: bool
        switch evt.key
        {
        case .Up where evt.modifiers == .None:                                target -= .scroll.verticalScrollStep
        case .Down where evt.modifiers == .None:                              target += .scroll.verticalScrollStep; forward = true
        case .PageUp where evt.modifiers == .None:                            target -= page
        case .PageDown where evt.modifiers == .None:                          target += page; forward = true
        case .Home where evt.modifiers == .None or evt.modifiers == .Control:
            .jumpToEnd        = false
            .hasPendingTarget = false
            .scroll.setScrollPos(position.x, 0)
            return true

        case .End where evt.modifiers == .None or evt.modifiers == .Control:
            .hasPendingTarget = false
            if .isLoading()
            {
                .jumpToEnd = true
                .scheduleMore()
            }
            else do
                .scroll.setScrollPos(position.x, .scroll.scrollableClientRect().height)
            return true

        case .Space where evt.modifiers == .None:  target += page; forward = true
        case .Space where evt.modifiers == .Shift: target -= page
        default: return false
        }

        .jumpToEnd = false
        if forward and .isLoading() and target + viewport.height > .contentHeight
        {
            .hasPendingTarget = true
            .pendingTarget    = target
            .scheduleMore()
            return true
        }

        .hasPendingTarget = false
        .scroll.setScrollPos(position.x, target)
        return true
    }

    mtd applyDocumentStyle()
    {
        for &block in .blocks
        {
            if block.inline do
                block.inline!.layoutWidth = 0
            if block.table do
                block.table!.layoutWidth = 0
        }

        .layoutDocument()
        .invalidate()
    }

}

public impl MarkdownView
{

    // Creates an empty Markdown document view.
    #[Swag.Discardable]
    func create(contentParent: *Wnd, documentStyle: MarkdownStyle = {})->*MarkdownView
    {
        let result = Wnd.create'MarkdownView(contentParent, "gui.markdown")
        result.backgroundStyle = .View
        result.focusPolicy     = .Tab
        result.wndFlags        |= .NoFocusRing
        result.documentStyle    = documentStyle
        result.contentHeight    = documentStyle.topInset

        result.scroll           = Wnd.create'ScrollWnd(result, "", {})
        result.scroll.dockStyle = .Center
        result.scroll.updateFlags(.CompactBars | .TransparentBars)
        result.body                            = result.scroll.createView'Wnd()
        result.body.backgroundStyle            = .View
        result.scroll.sigScrollPositionChanged += func|view = result|(scroll, oldPosition, newPosition)
        {
            discard scroll
            discard oldPosition
            discard newPosition
            view.scheduleMore()
        }
        result.hookOnEvent = func|view = result|(wnd, evt)
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
    func createText(contentParent: *Wnd, source: string, documentStyle: MarkdownStyle = {})->*MarkdownView
    {
        let result = .create(contentParent, documentStyle)
        result.sourceDone = true
        let parsed = parseMarkdownBlocks(source)
        for &block in parsed do
            result.appendBlock(#move block[])

        if result.blocks.isEmpty()
        {
            var empty: MarkdownBlock
            empty.kind = .Paragraph
            empty.text = "This Markdown document is empty."
            result.appendBlock(#move empty)
        }

        return result
    }

    // Creates a view and progressively loads a UTF-8 Markdown file.
    func createFile(contentParent: *Wnd, fileName: string, documentStyle: MarkdownStyle = {})->*MarkdownView
    {
        let result = .create(contentParent, documentStyle)
        result.stream = catch File.openRead(fileName) as openError
        if openError != null
        {
            result.sourceCarry = "Unable to read this Markdown document."
            result.sourceDone  = true
        }
        else
        {
            let size = catch result.stream.size() as sizeError
            if sizeError == null do
                result.fileSize = size
        }

        result.scheduleMore()
        return result
    }

    // Replaces the document metrics while keeping colors and font faces bound to the active theme.
    mtd setDocumentStyle(documentStyle: MarkdownStyle)
    {
        .documentStyle = documentStyle
        .applyDocumentStyle()
    }

    // Reports whether source remains to be parsed or displayed.
    mtd const isLoading()->bool
    {
        return !.sourceDone or !.sourceCarry.isEmpty() or .pendingIndex < .pendingBlocks.count
    }

    // Reports the laid-out height of the source rendered so far.
    mtd const loadedDocumentHeight()->f32 => .contentHeight + .documentStyle.bottomInset
}

internal impl IWnd for MarkdownView
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
        .streamStep()
        .scheduleMore()
    }
}
