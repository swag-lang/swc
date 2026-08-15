#global public

using Core, Pixel, Gui

private const ViewerPluginApiVersion = 2'u32
private const MarkdownPageWidth = 860.0
private const MarkdownPageInset = 48.0

private struct MarkdownVisualBlock
{
    wnd:   *Wnd = undefined
    label: #null *Label
    kind:  MarkdownBlockKind
}

private struct MarkdownMathView
{
    using wnd: Wnd
    expression: MathExpression
}

private impl IWnd for MarkdownMathView
{
    mtd impl onPaint(evt: *PaintEvent)
    {
        let rect = .clientRect()
        evt.paintContext.painter.drawMathCenter(
            rect.horzCenter(), rect.vertCenter(), &.expression,
            .theme().createDefaultFont(22), .themeColors().label_Text)
    }
}

private impl MarkdownMathView
{
    func create(parent: *Wnd, source: string)->#null *MarkdownMathView
    {
        let expression = catch MathExpression.parse(source) as parseError
        if parseError != null do
            return null

        let result = Wnd.create'MarkdownMathView(parent, "sViewer.markdown.math")
        result.backgroundStyle = .View
        result.expression = #move expression
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

    blocks: Array'MarkdownVisualBlock
}

private func markdownBlockGap(kind: MarkdownBlockKind)->f32
{
    switch kind
    {
    case .Heading1: return 26
    case .Heading2: return 22
    case .Heading3, .Heading4, .Heading5, .Heading6: return 16
    case .Code, .Table, .Math, .Quote: return 20
    case .Rule: return 24
    default: return 14
    }
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

    mtd layoutDocument()
    {
        let viewport = .scroll.paddedClientRect()
        if viewport.width <= 0 do
            return

        let width = Math.min(Math.max(viewport.width - MarkdownPageInset * 2, 280), MarkdownPageWidth)
        let x     = Math.max((viewport.width - width) * 0.5, 16)
        var y     = 38'f32
        for block in .blocks
        {
            if block.kind == .Quote
            {
                let label = block.label!
                let text = Format.toString("<p1>|</p>  <i>%</i>", label.name.raw)
                if !Utf8.startsWith(label.name.raw.toSlice(), "<p1>|") do
                    label.setText(text.toString())
            }

            block.wnd.setPosition({x, y, width, 0})
            if block.kind == .Math do
                block.wnd.resize(width, (cast(*MarkdownMathView) block.wnd).preferredHeight())
            else
            {
                block.label!.updateAutomaticHeight()
                if block.kind == .Rule and block.wnd.position.height < 2 do
                    block.wnd.resize(width, 18)
            }
            y += block.wnd.position.height + markdownBlockGap(block.kind)
        }

        y += 34
        let height = Math.max(y, viewport.height)
        .body.resize(viewport.width, height)
        .scroll.setScrollSize(viewport.width, height)
    }

    func createLoaded(contentParent: *Wnd, source: string)->*MarkdownPluginView
    {
        let result = Wnd.create'MarkdownPluginView(contentParent, "sViewer.markdown")
        result.backgroundStyle = .View

        result.scroll           = Wnd.create'ScrollWnd(result, "", {})
        result.scroll.dockStyle = .Center
        result.scroll.updateFlags(.CompactBars | .TransparentBars)
        result.body = result.scroll.createView'Wnd()
        result.body.backgroundStyle = .View

        let parsed = parseMarkdownBlocks(source)
        for block in parsed
        {
            if block.kind == .Math
            {
                let math = MarkdownMathView.create(result.body, block.text.toString())
                if math
                {
                    result.blocks.add(MarkdownVisualBlock{math!, null, .Math})
                    continue
                }
            }

            let text = block.kind == .Rule ? "────────────" : block.text.toString()
            let label = Label.create(result.body, text, {}, null, .WordWrap | .AutoHeight)
            result.configureLabel(label, block.kind)
            label.sigLinkActivated += func(linkLabel, url)
            {
                discard linkLabel
                Env.openUrl(url)
            }
            result.blocks.add(MarkdownVisualBlock{label, label, block.kind})
        }

        if result.blocks.isEmpty()
        {
            let label = Label.create(result.body, "This Markdown document is empty.", {}, null, .WordWrap | .AutoHeight | .SecondaryText)
            result.configureLabel(label, .Paragraph)
            result.blocks.add(MarkdownVisualBlock{label, label, .Paragraph})
        }

        result.scroll.hookOnEvent = func|view = result|(wnd, evt)
        {
            discard wnd
            if evt is ResizeEvent do
                view.layoutDocument()
            return false
        }
        result.applyLayout()
        result.layoutDocument()
        return result
    }

    func create(contentParent: *Wnd, fileName: string)->*MarkdownPluginView
    {
        let source = catch File.readAllText(fileName) as readError
        if readError != null or !Utf8.isValid(source.toSlice()) do
            return .createLoaded(contentParent, "Unable to read this Markdown document.")
        return .createLoaded(contentParent, source.toString())
    }
}

// Creates the dedicated Markdown view exported through the sViewer plugin ABI.
func sViewerPluginCreate(contentParent, commandParent: *Wnd, fileName: string, apiVersion: u32, commands: *#null *Wnd)->#null *Wnd
{
    discard commandParent
    if apiVersion != ViewerPluginApiVersion do
        return null
    commands[] = null
    return MarkdownPluginView.create(contentParent, fileName)
}
