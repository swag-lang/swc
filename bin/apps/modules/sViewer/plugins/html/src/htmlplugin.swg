#global public

using Core, Pixel, Gui

private const ViewerPluginApiVersion = 2'u32
private const HtmlStreamChunkSize = 8 * 1024'u64
private const HtmlStreamCarryLimit = 16 * 1024'u64
private const HtmlStreamLookAhead = 2.0
private const HtmlStreamFrameBudget = 3_000'u64
private const HtmlStreamBlockBudget = 8'u32

private struct HtmlPage
{
    using wnd:     Wnd
    cssBackground: Color
}

private impl IWnd for HtmlPage
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        if .cssBackground.a do
            evt.paintContext.painter.fillRect(.clientRect(), .cssBackground)
    }
}

private struct HtmlVisualBlock
{
    label: *Label = undefined
    kind:  HtmlBlockKind
    style: HtmlCssStyle
}

internal struct HtmlPluginView
{
    using wnd: Wnd

    #[Swag.Late]
    {
        scroll: *ScrollWnd
        body:   *Wnd
        page:   *HtmlPage
    }

    stream:        File.FileStream
    sourceCarry:   String
    sourceDone:    bool
    rules:         Array'HtmlCssRule
    pendingBlocks: Array'HtmlBlock
    pendingIndex:  u64
    loadTimer:     #null *Timer
    contentHeight = 42'f32
    bodyTag:       String
    bodyStyle:     HtmlCssStyle
    blocks:        Array'HtmlVisualBlock
}

private func htmlBlockGap(kind: HtmlBlockKind)->f32
{
    switch kind
    {
    case .Heading1:                                  return 26
    case .Heading2:                                  return 22
    case .Heading3, .Heading4, .Heading5, .Heading6: return 16
    case .Code, .Table, .Quote, .Details:            return 20
    case .Rule:                                      return 24
    default:                                         return 14
    }
}

private func htmlDefaultSize(kind: HtmlBlockKind)->u32
{
    switch kind
    {
    case .Heading1:            return 36
    case .Heading2:            return 28
    case .Heading3:            return 23
    case .Heading4:            return 19
    case .Heading5, .Heading6: return 16
    case .Code, .Table:        return 14
    default:                   return 16
    }
}

internal impl HtmlPluginView
{
    mtd fixedFontFamily(size: u32)->FontFamily
    {
        var result: retval
        result.regular    = .theme().createDefaultFontFS(size, .Regular)
        result.bold       = .theme().createDefaultFontFS(size, .Bold)
        result.italic     = .theme().createDefaultFontFS(size, .Italic)
        result.boldItalic = .theme().createDefaultFontFS(size, .BoldItalic)
        return result
    }

    mtd configureLabel(label: *Label, block: const *HtmlBlock)
    {
        let style = block.style
        let size  = style.fontSize > 0 ? cast(u32) Math.clamp(style.fontSize, 9, 72) : htmlDefaultSize(block.kind)

        if block.kind == .Code or block.kind == .Table do
            label.style.setFont(.fixedFontFamily(size))
        else do
            label.style.setFont(.theme().createDefaultFontfamily(size))
        if style.bold or style.italic
        {
            var text = String.from(label.name.raw)
            if style.bold do
                text = Format.toString("<b>%</b>", text)
            if style.italic do
                text = Format.toString("<i>%</i>", text)
            label.setText(text.toString())
        }

        label.setTextAlignment(style.hasAlign ? style.align : .Left, .Top)

        if style.color.a do
            label.setTextColor(style.color)
        elif .bodyStyle.color.a do
            label.setTextColor(.bodyStyle.color)

        switch block.kind
        {
        case .Code, .Table:
            label.backgroundStyle = .Window
            label.setTextPadding({18, 14, 18, 14})

        case .Quote:
            label.setText(Format.toString("<p1>▎</p>  <i>%</i>", label.name.raw).toString())
            label.setTextPadding({18, 10, 10, 10})

        case .Details:
            label.backgroundStyle = .Window
            label.setTextPadding({16, 12, 16, 12})

        case .Rule:
            label.setTextAlignment(.Center, .Center)
            label.setTextColor(.themeColors().label_TextFaint)

        default:
            label.setTextPadding({0, 2, 0, 2})
        }

        if style.background.a do
            label.backgroundStyle = .Window
    }

    mtd documentGeometry()->{ pageX: f32, pageWidth: f32, contentX: f32, contentWidth: f32 }
    {
        let viewport     = .scroll.paddedClientRect()
        let requested    = .bodyStyle.maxWidth > 0 ? .bodyStyle.maxWidth : 960
        let pageWidth    = Math.min(Math.max(viewport.width - 64, 300), requested)
        let pageX        = Math.max((viewport.width - pageWidth) * 0.5, 16)
        let contentX     = 44'f32
        let contentWidth = Math.max(pageWidth - contentX * 2, 220)
        return {pageX, pageWidth, contentX, contentWidth}
    }

    mtd updateDocumentSize()
    {
        let viewport   = .scroll.paddedClientRect()
        let geometry   = .documentGeometry()
        let pageHeight = Math.max(.contentHeight + 34, viewport.height - 32)
        .page.setPosition({geometry.pageX, 16, geometry.pageWidth, pageHeight})
        .body.resize(viewport.width, pageHeight + 32)
        .scroll.setScrollSize(viewport.width, pageHeight + 32)
    }

    mtd placeBlock(block: *HtmlVisualBlock, contentX, contentWidth: f32, y: *f32)
    {
        block.label.setPosition({contentX, y[], contentWidth, 0})
        block.label.updateAutomaticHeight()
        y[] += block.label.position.height + htmlBlockGap(block.kind)
    }

    mtd layoutDocument()
    {
        let viewport = .scroll.paddedClientRect()
        if viewport.width <= 0 do
            return

        let geometry = .documentGeometry()
        .page.setPosition({geometry.pageX, 16, geometry.pageWidth, Math.max(.page.position.height, viewport.height - 32)})
        var y = 42'f32
        for &block in .blocks do
            .placeBlock(block, geometry.contentX, geometry.contentWidth, &y)
        .contentHeight = y
        .updateDocumentSize()
    }

    mtd appendBlock(block: HtmlBlock)
    {
        let label = Label.create(.page, block.text.toString(), {}, null, .WordWrap | .AutoHeight)
        .configureLabel(label, &block)
        label.sigLinkActivated += func(linkLabel, url)
        {
            discard linkLabel
            Env.openUrl(url)
        }
        .blocks.add(HtmlVisualBlock{label, block.kind, block.style})

        let geometry = .documentGeometry()
        .placeBlock(.blocks.backPtr(), geometry.contentX, geometry.contentWidth, &.contentHeight)
        .updateDocumentSize()
    }

    mtd needsMore()->bool
    {
        if .pendingIndex >= .pendingBlocks.count and .sourceDone and .sourceCarry.isEmpty() do
            return false
        let viewport = .scroll.paddedClientRect()
        return .scroll.scrollPosition().y + viewport.height * HtmlStreamLookAhead >= .contentHeight
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

        let chunk = catch .stream.readUtf8Chunk(HtmlStreamChunkSize) as readError
        if readError != null or Utf8.indexOf(chunk.toSlice(), 0'rune) != Swag.U64.Max
        {
            .sourceCarry = "<p>Unable to read this HTML document.</p>"
            .sourceDone  = true
            .stream.close()
            return
        }

        if chunk.isEmpty()
        {
            .sourceDone = true
            .stream.close()
            return
        }

        .sourceCarry += chunk
    }

    mtd consumeSource(source: string)
    {
        let newRules = parseHtmlCss(source)
        for &rule in newRules do
            .rules.add(#move rule[])

        let body = Utf8.indexOf(source, "<body", 0, .Latin1NoCase)
        if body != Swag.U64.Max
        {
            let close = Utf8.indexOf(source, '>'rune, body + 5)
            if close != Swag.U64.Max do
                .bodyTag = String.from(source[body + 1 until close])
        }

        .bodyStyle          = htmlCssStyle(.bodyTag.toString(), "body", .rules.toSlice())
        .page.cssBackground = .bodyStyle.background
        .pendingBlocks      = parseHtmlBlocks(source, .rules.toSlice())
        .pendingIndex       = 0
    }

    mtd preparePending()->bool
    {
        if .pendingIndex < .pendingBlocks.count do
            return true

        .pendingBlocks.clear()
        .pendingIndex = 0
        if .sourceCarry.isEmpty() and !.sourceDone do
            .readSource()
        if .sourceCarry.isEmpty() do
            return false

        let force  = .sourceDone or .sourceCarry.length >= HtmlStreamCarryLimit
        var parsed = parseHtmlBlockChunk(.sourceCarry.toString(), .rules.toSlice(), force)
        if !parsed.consumed and !.sourceDone
        {
            .readSource()
            let forceAfterRead = .sourceDone or .sourceCarry.length >= HtmlStreamCarryLimit
            parsed = parseHtmlBlockChunk(.sourceCarry.toString(), .rules.toSlice(), forceAfterRead)
        }

        if !parsed.consumed do
            return false

        let source    = String.from(.sourceCarry.toString()[0 until parsed.consumed])
        var remaining = String.from(.sourceCarry.toString()[parsed.consumed to])
        .sourceCarry = #move remaining
        .consumeSource(source.toString())
        return !.pendingBlocks.isEmpty()
    }

    mtd streamStep()
    {
        var stopwatch: Time.Stopwatch
        stopwatch.start()
        var blockCount = 0'u32
        while .needsMore() and blockCount < HtmlStreamBlockBudget
        {
            if !.preparePending() do
                break
            .appendBlock(#move .pendingBlocks[.pendingIndex])
            .pendingIndex += 1
            blockCount    += 1
            if stopwatch.elapsedMicroseconds() >= HtmlStreamFrameBudget do
                break
        }

        if .sourceDone and .sourceCarry.isEmpty() and .pendingIndex >= .pendingBlocks.count and .blocks.isEmpty()
        {
            var empty: HtmlBlock
            empty.kind = .Paragraph
            empty.text = "This HTML document has no visible content."
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

    func createBase(contentParent: *Wnd)->*HtmlPluginView
    {
        let result = Wnd.create'HtmlPluginView(contentParent, "sViewer.html")
        result.backgroundStyle = .View

        result.scroll           = Wnd.create'ScrollWnd(result, "", {})
        result.scroll.dockStyle = .Center
        result.scroll.updateFlags(.CompactBars | .TransparentBars)
        result.body                            = result.scroll.createView'Wnd()
        result.body.backgroundStyle            = .View
        result.page                            = Wnd.create'HtmlPage(result.body, "sViewer.html.page")
        result.page.backgroundStyle            = .Window
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
        return result
    }

    func createLoaded(contentParent: *Wnd, source: string)->*HtmlPluginView
    {
        let result = .createBase(contentParent)
        result.sourceDone = true
        result.consumeSource(source)
        for &block in result.pendingBlocks do
            result.appendBlock(#move block[])
        result.pendingIndex = result.pendingBlocks.count

        if result.blocks.isEmpty()
        {
            var empty: HtmlBlock
            empty.kind = .Paragraph
            empty.text = "This HTML document has no visible content."
            result.appendBlock(#move empty)
        }

        return result
    }

    func create(contentParent: *Wnd, fileName: string)->*HtmlPluginView
    {
        let result = .createBase(contentParent)
        result.stream = catch File.openRead(fileName) as openError
        if openError != null
        {
            result.sourceCarry = "<p>Unable to read this HTML document.</p>"
            result.sourceDone  = true
        }

        result.scheduleMore()
        return result
    }
}

internal impl IWnd for HtmlPluginView
{
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

// Creates the dedicated HTML and CSS view exported through the sViewer plugin ABI.
func sViewerPluginCreate(contentParent, commandParent: *Wnd, fileName: string, apiVersion: u32, commands: *#null *Wnd)->#null *Wnd
{
    discard commandParent
    if apiVersion != ViewerPluginApiVersion do
        return null
    commands[] = null
    return HtmlPluginView.create(contentParent, fileName)
}
