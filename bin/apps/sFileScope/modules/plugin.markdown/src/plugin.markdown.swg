#global public

using Core, Pixel, Gui

private const ViewerPluginApiVersion = 3'u32
private const MarkdownPageWidth = 860.0
private const MarkdownPageInset = 48.0
private const MarkdownStreamChunkSize = 8 * 1024'u64
private const MarkdownStreamCarryLimit = 16 * 1024'u64
private const MarkdownStreamLookAhead = 2.0
private const MarkdownStreamFrameBudget = 3_000'u64
private const MarkdownStreamBlockBudget = 8'u32

private struct MarkdownVisualBlock
{
    wnd:   *Wnd = undefined
    label: #null *Label
    kind:  MarkdownBlockKind
}

private struct MarkdownMathView
{
    using wnd:  Wnd
    expression: MathExpression
}

private impl IWnd for MarkdownMathView
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let rect = .clientRect()
        evt.paintContext.painter.drawMathCenter(rect.horzCenter(), rect.vertCenter(), &.expression, .theme().createDefaultFont(22), .themeColors().label_Text)
    }
}

private impl MarkdownMathView
{
    func create(parent: *Wnd, source: string)->#null *MarkdownMathView
    {
        let expression = catch MathExpression.parse(source) as parseError
        if parseError != null do
            return null

        let result = Wnd.create'MarkdownMathView(parent, "sFileScope.markdown.math")
        result.backgroundStyle = .View
        result.expression      = #move expression
        return result
    }

    mtd preferredHeight()->f32
    {
        let metrics = .expression.measure(.theme().createDefaultFont(22))
        return Math.max(metrics.height() + 28, 64)
    }
}

internal struct MarkdownPluginView
{
    using wnd: Wnd

    #[Swag.Late]
    {
        scroll: *ScrollWnd
        body:   *Wnd
    }

    stream:        File.FileStream
    fileSize:      u64
    bytesRead:     u64
    sourceCarry:   String
    sourceDone:    bool
    pendingBlocks: Array'MarkdownBlock
    pendingIndex:  u64
    loadTimer:     #null *Timer
    contentHeight = 38'f32
    blocks:        Array'MarkdownVisualBlock
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

private func markdownBlockGap(kind: MarkdownBlockKind)->f32
{
    switch kind
    {
    case .Heading1:                                  return 26
    case .Heading2:                                  return 22
    case .Heading3, .Heading4, .Heading5, .Heading6: return 16
    case .Code, .Table, .Math, .Quote:               return 20
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

        if !fenceMarker and !displayMath and !@countof(trimmed) do
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

internal impl MarkdownPluginView
{
    mtd configureLabel(label: *Label, kind: MarkdownBlockKind)
    {
        label.setTextAlignment(.Left, .Top)
        switch kind
        {
        case .Heading1:
            label.style.setFont(.theme().createDefaultFont(32, .Bold), .Regular)
            label.setTextPadding({0, 8, 0, 2})

        case .Heading2:
            label.style.setFont(.theme().createDefaultFont(25, .Bold), .Regular)
            label.setTextPadding({0, 8, 0, 2})

        case .Heading3:
            label.style.setFont(.theme().createDefaultFont(21, .Bold), .Regular)

        case .Heading4:
            label.style.setFont(.theme().createDefaultFont(18, .Bold), .Regular)

        case .Heading5, .Heading6:
            label.style.setFont(.theme().createDefaultFont(16, .Bold), .Regular)

        case .Code:
            label.backgroundStyle = .Window
            label.style.setFont(.theme().createDefaultFontFS(14), .Regular)
            label.setTextPadding({18, 14, 18, 14})

        case .Table:
            label.backgroundStyle = .Window
            label.style.setFont(.theme().createDefaultFontFS(14), .Regular)
            label.setTextPadding({16, 12, 16, 12})

        case .Math:
            label.style.setFont(.theme().createDefaultFont(21, .Italic), .Regular)
            label.setTextAlignment(.Center, .Top)
            label.setTextPadding({20, 14, 20, 14})

        case .Quote:
            label.style.setFont(.theme().createDefaultFont(16, .Italic), .Regular)
            label.setTextPadding({18, 10, 10, 10})

        case .Metadata:
            label.style.setFont(.theme().createDefaultFontFS(13), .Regular)
            label.setTextColor(.themeColors().label_TextFaint)
            label.setTextPadding({12, 8, 12, 8})

        case .Rule:
            label.setTextColor(.themeColors().label_TextFaint)
            label.setTextAlignment(.Center, .Center)

        default:
            label.style.setFont(.theme().createDefaultFont(16), .Regular)
            label.setTextPadding({0, 2, 0, 2})
        }
    }

    mtd documentGeometry()->{ x: f32, width: f32 }
    {
        let viewport = .scroll.paddedClientRect()
        let width    = Math.min(Math.max(viewport.width - MarkdownPageInset * 2, 280), MarkdownPageWidth)
        return {Math.max((viewport.width - width) * 0.5, 16), width}
    }

    mtd updateDocumentSize()
    {
        let viewport        = .scroll.paddedClientRect()
        let loadedHeight    = .contentHeight + 34
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
        else
        {
            block.label!.updateAutomaticHeight()
            if block.kind == .Rule and block.wnd.position.height < 2 do
                block.wnd.resize(width, 18)
        }

        y[] += block.wnd.position.height + markdownBlockGap(block.kind)
    }

    mtd layoutDocument()
    {
        let viewport = .scroll.paddedClientRect()
        if viewport.width <= 0 do
            return

        let geometry = .documentGeometry()
        var y        = 38'f32
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
            let math = MarkdownMathView.create(.body, block.text.toString())
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

        var text: String
        if block.kind == .Rule do
            text = "────────────"
        else do
            text = #move block.text
        if block.kind == .Quote do
            text = Format.toString("<p1>|</p>  <i>%</i>", text)
        let label = Label.create(.body, text.toString(), {}, null, .WordWrap | .AutoHeight)
        .configureLabel(label, block.kind)
        label.sigLinkActivated += func(linkLabel, url)
        {
            discard linkLabel
            Env.openUrl(url)
        }
        visual.wnd   = label
        visual.label = label
        .blocks.add(visual)

        let geometry = .documentGeometry()
        .placeBlock(.blocks.backPtr(), geometry.x, geometry.width, &.contentHeight)
        .updateDocumentSize()
    }

    mtd needsMore()->bool
    {
        if .pendingIndex >= .pendingBlocks.count and .sourceDone and .sourceCarry.isEmpty() do
            return false
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

    func createBase(contentParent: *Wnd)->*MarkdownPluginView
    {
        let result = Wnd.create'MarkdownPluginView(contentParent, "sFileScope.markdown")
        result.backgroundStyle = .View
        result.focusPolicy     = .Tab
        result.wndFlags        |= .NoFocusRing

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

    func createLoaded(contentParent: *Wnd, source: string)->*MarkdownPluginView
    {
        let result = .createBase(contentParent)
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

    func create(contentParent: *Wnd, fileName: string)->*MarkdownPluginView
    {
        let result = .createBase(contentParent)
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
}

internal impl IWnd for MarkdownPluginView
{
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if !scrollDocumentWithKey(.scroll, evt) do
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

// Creates the dedicated Markdown view exported through the sFileScope plugin ABI.
func sFileScopePluginCreate(contentParent, commandParent: *Wnd, fileName: string, apiVersion: u32, commands: *#null *Wnd, details: *String)->#null *Wnd
{
    discard commandParent
    if apiVersion != ViewerPluginApiVersion do
        return null
    commands[] = null
    details[] = "Markdown · UTF-8 · streamed"
    return MarkdownPluginView.create(contentParent, fileName)
}
