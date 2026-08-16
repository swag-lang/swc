#global public

using Core, Pixel

private const HtmlStreamChunkSize = 8 * 1024'u64
private const HtmlStreamCarryLimit = 16 * 1024'u64
private const HtmlRevealContextSize = 64 * 1024'u64
private const HtmlRevealChunkSize = HtmlRevealContextSize + HtmlStreamChunkSize
private const HtmlStreamLookAhead = 2.0
private const HtmlStreamFrameBudget = 3_000'u64
private const HtmlStreamBlockBudget = 8'u32

// Controls the reading measure and typography of an [[Gui.HtmlView]].
//
// Source CSS can refine these defaults. Colors without a complete foreground/background pair
// are adjusted against the active GUI theme so documents remain readable in either palette.
public struct HtmlStyle
{
    public
    {
        maxContentWidth:  f32 = 960     // Widest document page, in logical pixels.
        horizontalInset:  f32 = 32      // Minimum room kept on each side of the page.
        contentInset:     f32 = 44      // Room kept between the page edge and its text.
        topInset:         f32 = 42      // Space before the first visible block.
        bottomInset:      f32 = 34      // Space after the last visible block.
        bodyFontSize:     u32 = 16      // Default body-text draw size, in logical pixels.
        codeFontSize:     u32 = 14      // Default code and table draw size, in logical pixels.
        heading1FontSize: u32 = 36      // Level-one heading draw size, in logical pixels.
        heading2FontSize: u32 = 28      // Level-two heading draw size, in logical pixels.
        heading3FontSize: u32 = 23      // Level-three heading draw size, in logical pixels.
        heading4FontSize: u32 = 19      // Level-four heading draw size, in logical pixels.
        heading5FontSize: u32 = 16      // Level-five heading draw size, in logical pixels.
        heading6FontSize: u32 = 16      // Level-six heading draw size, in logical pixels.
        lineHeight:       f32 = 1.5     // Arrow-key scroll step relative to the body font height.
    }
}

public impl HtmlStyle
{
    // Returns the document style that follows the active GUI theme.
    func theme()->HtmlStyle => {}
}

#[Swag.NoDoc]
struct HtmlPage
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

#[Swag.NoDoc]
struct HtmlVisualBlock
{
    label: *Label = undefined
    kind:  HtmlBlockKind
    style: HtmlCssStyle
    text:  String
}

// Displays HTML as a themed, read-only document with progressive UTF-8 file loading.
//
// [[Gui.HtmlView.createText]] renders in-memory source, while [[Gui.HtmlView.createFile]] streams
// a file. Rendering stays offline: scripts, embedded documents, and hidden metadata never run.
// The parent window owns the returned control through the normal [[Gui.Wnd]] hierarchy.
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
        documentStyle: HtmlStyle     // Active document typography and reading measure.
    }

    internal
    {
        #[Swag.Late]
        {
            scroll: *ScrollWnd
            body:   *Wnd
            page:   *HtmlPage
        }

        stream:            File.FileStream
        fileName:          String
        fileSize:          u64
        bytesRead:         u64
        residentStart:     u64
        virtualOrigin:     f32
        virtualHeight:     f32
        pendingSearch:     String
        pendingSeek:       bool
        pendingSeekOffset: u64
        sourceCarry:       String
        sourceDone:        bool
        rules:             Array'HtmlCssRule
        pendingBlocks:     Array'HtmlBlock
        pendingIndex:      u64
        loadTimer:         #null *Timer
        jumpToEnd:         bool
        pauseStreaming:    bool
        hasPendingY:       bool
        pendingY:          f32
        contentHeight:     f32
        searchBlockIndex = Swag.U64.Max
        bodyTag:           String
        bodyStyle:         HtmlCssStyle
        blocks:            Array'HtmlVisualBlock
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

private func htmlDefaultSize(kind: HtmlBlockKind, style: const *HtmlStyle)->u32
{
    switch kind
    {
    case .Heading1:     return style.heading1FontSize
    case .Heading2:     return style.heading2FontSize
    case .Heading3:     return style.heading3FontSize
    case .Heading4:     return style.heading4FontSize
    case .Heading5:     return style.heading5FontSize
    case .Heading6:     return style.heading6FontSize
    case .Code, .Table: return style.codeFontSize
    default:            return style.bodyFontSize
    }
}

internal impl HtmlView
{
    // Scrolls to the next rendered block containing `text`, wrapping once at the end.
    public mtd findText(text: string)->bool
    {
        if !@countof(text) or .blocks.isEmpty() do
            return false
        let first = .searchBlockIndex == Swag.U64.Max ? 0 : (.searchBlockIndex + 1) % .blocks.count
        for offset in .blocks.count
        {
            let index = (first + offset) % .blocks.count
            if Utf8.indexOf(.blocks[index].label.name.raw, text, 0, .Latin1NoCase) == Swag.U64.Max do
                continue
            .searchBlockIndex = index
            let position = .scroll.scrollPosition()
            .scroll.setScrollPos(position.x, .blocks[index].label.parent!.position.y + .blocks[index].label.position.y - 24)
            .blocks[index].label.setFocus()
            return true
        }

        return false
    }

    // Reports whether source remains to be parsed or displayed.
    public mtd const isLoading()->bool
    {
        return .pendingIndex < .pendingBlocks.count or !.sourceDone or !.sourceCarry.isEmpty()
    }

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
        let size  = style.fontSize > 0 ? cast(u32) Math.clamp(style.fontSize, 9, 72) : htmlDefaultSize(block.kind, &.documentStyle)

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

        let ground = style.background.a ? style.background : (.bodyStyle.background.a ? .bodyStyle.background : .themeColors().view_Bk)
        if style.color.a
        {
            var color = style.color
            color.ensureContrast(ground)
            label.setTextColor(color)
        }
        elif .bodyStyle.color.a
        {
            var color = .bodyStyle.color
            color.ensureContrast(ground)
            label.setTextColor(color)
        }

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

        if style.background.a
        {
            label.backgroundStyle = .Window
            label.style.addStyleSheetColors(Format.toString("wnd_Bk 0x%{X}", style.background.argb))
        }
    }

    mtd documentGeometry()->{ pageX: f32, pageWidth: f32, contentX: f32, contentWidth: f32 }
    {
        let viewport     = .scroll.paddedClientRect()
        let requested    = .bodyStyle.maxWidth > 0 ? .bodyStyle.maxWidth : .documentStyle.maxContentWidth
        let pageWidth    = Math.min(Math.max(viewport.width - .documentStyle.horizontalInset * 2, 300), requested)
        let pageX        = Math.max((viewport.width - pageWidth) * 0.5, 16)
        let contentX     = .documentStyle.contentInset
        let contentWidth = Math.max(pageWidth - contentX * 2, 220)
        return {pageX, pageWidth, contentX, contentWidth}
    }

    mtd updateDocumentSize()
    {
        let viewport        = .scroll.paddedClientRect()
        let geometry        = .documentGeometry()
        let loadedHeight    = .contentHeight + .documentStyle.bottomInset
        var estimatedHeight = loadedHeight
        let consumed        = .bytesRead - .residentStart
        if consumed and .bytesRead < .fileSize
        {
            let residentHeight = Math.max(loadedHeight - .virtualOrigin, 1)
            .virtualHeight  = Math.max(residentHeight * cast(f32) .fileSize / cast(f32) consumed, .virtualHeight)
            estimatedHeight = Math.max(.virtualHeight, loadedHeight)
        }

        let pageHeight = Math.max(estimatedHeight, viewport.height - 32)
        let position   = .scroll.scrollPosition()
        .page.setPosition({geometry.pageX, 16, geometry.pageWidth, pageHeight})
        .scroll.setScrollSize(viewport.width, pageHeight + 32)
        .scroll.setScrollPos(position)
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

        // The HTML canvas has no caret, so one Up/Down action follows one body-text line while
        // PageUp/PageDown remain viewport-relative in handleDocumentKey.
        let bodyFontSize = .bodyStyle.fontSize > 0 ? cast(u32) Math.clamp(.bodyStyle.fontSize, 9, 72) : 16
        .scroll.verticalScrollStep = .theme().createDefaultFont(bodyFontSize).height * .documentStyle.lineHeight

        let geometry = .documentGeometry()
        .page.setPosition({geometry.pageX, 16, geometry.pageWidth, Math.max(.page.position.height, viewport.height - 32)})
        var y = .virtualOrigin + .documentStyle.topInset
        for &block in .blocks do
            .placeBlock(block, geometry.contentX, geometry.contentWidth, &y)
        .contentHeight = y
        .updateDocumentSize()
    }

    mtd appendBlock(block: HtmlBlock)
    {
        let label = Label.create(.page, block.text.toString(), {}, null, .WordWrap | .AutoHeight)
        .configureLabel(label, &block)
        label.sigLinkActivated += func|view = me|(linkLabel, url)
        {
            discard linkLabel
            view.sigLinkActivated.call(view, url)
        }
        var visual: HtmlVisualBlock
        visual.label = label
        visual.kind  = block.kind
        visual.style = block.style
        visual.text  = #move block.text
        .blocks.add(#move visual)

        let geometry = .documentGeometry()
        .placeBlock(.blocks.backPtr(), geometry.contentX, geometry.contentWidth, &.contentHeight)
        .updateDocumentSize()
    }

    mtd needsMore()->bool
    {
        if !.isLoading() do
            return false
        if .pauseStreaming do
            return false
        if .jumpToEnd or .hasPendingY do
            return true
        let viewport = .scroll.paddedClientRect()
        return .scroll.scrollPosition().y + viewport.height * HtmlStreamLookAhead >= .contentHeight
    }

    mtd handleDocumentKey(evt: *KeyEvent)->bool
    {
        if evt.kind != .Pressed do
            return false

        if evt.key == .Home and (evt.modifiers == .None or evt.modifiers == .Control)
        {
            .jumpToEnd      = false
            .pauseStreaming = false
            .hasPendingY    = false
            if .residentStart do
                discard .revealFileOffset(0, "")
            return scrollDocumentWithKey(.scroll, evt)
        }

        if evt.key == .End and (evt.modifiers == .None or evt.modifiers == .Control)
        {
            .hasPendingY = false
            if .fileSize and .bytesRead < .fileSize
            {
                let start = .fileSize > HtmlStreamCarryLimit ? .fileSize - HtmlStreamCarryLimit : 0
                .jumpToEnd = true
                discard .revealFileOffset(start, "")
            }
            else
            {
                let position = .scroll.scrollPosition()
                .scroll.setScrollPos(position.x, .contentHeight)
            }

            return true
        }

        var delta    = 0'f32
        let viewport = .scroll.paddedClientRect()
        let page     = Math.max(viewport.height - .scroll.verticalScrollStep, .scroll.verticalScrollStep)
        switch evt.key
        {
        case .Down where evt.modifiers == .None:     delta = .scroll.verticalScrollStep
        case .PageDown where evt.modifiers == .None: delta = page
        case .Space where evt.modifiers == .None:    delta = page
        default: return scrollDocumentWithKey(.scroll, evt)
        }

        let position = .scroll.scrollPosition()
        .pauseStreaming = false
        let origin = .hasPendingY ? .pendingY : position.y
        let target = origin + delta
        if .isLoading() and target + viewport.height > .contentHeight
        {
            .pendingY    = target
            .hasPendingY = true
            .scheduleMore()
            return true
        }

        .scroll.setScrollPos(position.x, target)
        return true
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

        let chunk = catch .stream.readUtf8Chunk(HtmlStreamChunkSize) as readError
        if readError != null or Utf8.indexOf(chunk.toSlice(), 0'rune) != Swag.U64.Max
        {
            .sourceCarry = "<p>Unable to read this HTML document.</p>"
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

        if !.isLoading() and .jumpToEnd
        {
            .jumpToEnd = false
            let position = .scroll.scrollPosition()
            .scroll.setScrollPos(position.x, .scroll.scrollableClientRect().height)
        }
        elif .hasPendingY and (!.isLoading() or .pendingY + .scroll.paddedClientRect().height <= .contentHeight)
        {
            .hasPendingY = false
            let position = .scroll.scrollPosition()
            .scroll.setScrollPos(position.x, .pendingY)
        }

        if !.pendingSearch.isEmpty() and .findText(.pendingSearch.toString()) do
            .pendingSearch.clear()
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

    // Repositions a streamed document near a byte offset and reveals matching text.
    //
    // The bounded UTF-8 context around `offset` is decoded without parsing the preceding bytes.
    // Returns `false` when the backing file cannot be reopened or read. An empty `text` only
    // repositions the resident window.
    public mtd revealFileOffset(offset: u64, text: string)->bool
    {
        .stopLoading()
        for &block in .blocks do
            block.label.destroy()
        .blocks.clear()
        .pendingBlocks.clear()
        .pendingIndex = 0
        .sourceCarry.clear()
        .sourceDone       = false
        .searchBlockIndex = Swag.U64.Max
        .pendingSearch    = text

        let requested = Math.min(offset, .fileSize)
        let start     = requested > HtmlRevealContextSize ? requested - HtmlRevealContextSize : 0
        for adjustment in 4
        {
            .stream = catch File.openRead(.fileName.toString()) as openError
            if openError != null do
                return false
            let actual = Math.min(start + adjustment, .fileSize)
            discard catch .stream.seek(.Begin, actual)
            var chunk = catch .stream.readUtf8Chunk(HtmlRevealChunkSize) as readError
            if readError != null
            {
                .stream.close()
                continue
            }

            let localTarget    = requested > actual ? Math.min(requested - actual, chunk.length) : 0
            let boundary       = htmlBlockStartBefore(chunk.toString(), localTarget)
            let previousHeight = Math.max(.virtualHeight, .scroll.scrollableClientRect().height)
            .residentStart = actual + boundary
            .bytesRead     = actual + chunk.length
            .sourceCarry   = String.from(chunk.toString()[boundary to])
            .sourceDone    = .bytesRead >= .fileSize
            .virtualHeight = Math.max(previousHeight, .scroll.paddedClientRect().height)
            .virtualOrigin = .fileSize ? .virtualHeight * cast(f32) .residentStart / cast(f32) .fileSize : 0
            .contentHeight = .virtualOrigin + .documentStyle.topInset
            .layoutDocument()
            if !.jumpToEnd do
                .scroll.setScrollPos(0, .virtualOrigin)
            .scheduleMore()
            return true
        }

        return false
    }

    func createBase(contentParent: *Wnd, documentStyle: HtmlStyle)->*HtmlView
    {
        let result = Wnd.create'HtmlView(contentParent, "gui.html")
        result.backgroundStyle = .View
        result.focusPolicy     = .Tab
        result.wndFlags        |= .NoFocusRing
        result.documentStyle   = documentStyle
        result.contentHeight   = documentStyle.topInset

        result.scroll           = Wnd.create'ScrollWnd(result, "", {})
        result.scroll.dockStyle = .Center
        result.scroll.updateFlags(.DisableHorizontal)
        result.body                            = result.scroll.createView'Wnd()
        result.body.backgroundStyle            = .View
        result.page                            = Wnd.create'HtmlPage(result.body, "sFileScope.html.page")
        result.page.backgroundStyle            = .View
        result.scroll.sigScrollPositionChanged += func|view = result|(scroll, oldPosition, newPosition)
        {
            discard scroll
            if view.jumpToEnd do
                return
            if view.pauseStreaming and newPosition.y < oldPosition.y do
                view.pauseStreaming = false
            if view.virtualHeight > 0 and !view.blocks.isEmpty() and (newPosition.y + view.scroll.paddedClientRect().height < view.virtualOrigin or newPosition.y > view.contentHeight)
            {
                let ratio = Math.clamp(newPosition.y / view.virtualHeight, 0, 1)
                view.pendingSeekOffset = cast(u64) (ratio * cast(f32) view.fileSize)
                view.pendingSeek       = true
            }

            view.scheduleMore()
        }
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

    // Creates a view and renders the complete in-memory HTML source.
    public func createText(contentParent: *Wnd, source: string, documentStyle: HtmlStyle = {})->*HtmlView
    {
        let result = .createBase(contentParent, documentStyle)
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

    // Creates a view and progressively loads a UTF-8 HTML file.
    //
    // File-open and decoding failures are displayed inside the returned view rather than reported
    // to the caller. At most a bounded source window and its visible blocks stay resident.
    public func createFile(contentParent: *Wnd, fileName: string, documentStyle: HtmlStyle = {})->*HtmlView
    {
        let result = .createBase(contentParent, documentStyle)
        result.fileName = fileName
        result.stream   = catch File.openRead(fileName) as openError
        if openError != null
        {
            result.sourceCarry = "<p>Unable to read this HTML document.</p>"
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

    // Replaces document metrics while keeping colors and font faces bound to the active theme.
    public mtd setDocumentStyle(documentStyle: HtmlStyle)
    {
        .documentStyle = documentStyle
        for &block in .blocks
        {
            block.label.setText(block.text.toString())
            var source: HtmlBlock
            source.kind  = block.kind
            source.text  = block.text
            source.style = block.style
            .configureLabel(block.label, &source)
        }

        .layoutDocument()
        .invalidate()
    }
}

internal impl IWnd for HtmlView
{
    mtd impl onThemeEvent(evt: *ThemeEvent)
    {
        if @isset(.scroll) do
            .setDocumentStyle(.documentStyle)
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
