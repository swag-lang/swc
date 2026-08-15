#global public

using Core, Pixel, Gui

private const ViewerPluginApiVersion = 2'u32

private struct HtmlPage
{
    using wnd: Wnd
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

    bodyStyle: HtmlCssStyle
    blocks:    Array'HtmlVisualBlock
}

private func htmlBlockGap(kind: HtmlBlockKind)->f32
{
    switch kind
    {
    case .Heading1: return 26
    case .Heading2: return 22
    case .Heading3, .Heading4, .Heading5, .Heading6: return 16
    case .Code, .Table, .Quote, .Details: return 20
    case .Rule: return 24
    default: return 14
    }
}

private func htmlDefaultSize(kind: HtmlBlockKind)->u32
{
    switch kind
    {
    case .Heading1: return 36
    case .Heading2: return 28
    case .Heading3: return 23
    case .Heading4: return 19
    case .Heading5, .Heading6: return 16
    case .Code, .Table: return 14
    default: return 16
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

    mtd layoutDocument()
    {
        let viewport = .scroll.paddedClientRect()
        if viewport.width <= 0 do
            return

        let requested = .bodyStyle.maxWidth > 0 ? .bodyStyle.maxWidth : 960
        let pageWidth = Math.min(Math.max(viewport.width - 64, 300), requested)
        let pageX     = Math.max((viewport.width - pageWidth) * 0.5, 16)
        let contentX  = 44'f32
        let contentWidth = Math.max(pageWidth - contentX * 2, 220)
        var y = 42'f32
        for block in .blocks
        {
            block.label.setPosition({contentX, y, contentWidth, 0})
            block.label.updateAutomaticHeight()
            y += block.label.position.height + htmlBlockGap(block.kind)
        }

        y += 34
        let pageHeight = Math.max(y, viewport.height - 32)
        .page.setPosition({pageX, 16, pageWidth, pageHeight})
        .body.resize(viewport.width, pageHeight + 32)
        .scroll.setScrollSize(viewport.width, pageHeight + 32)
    }

    func createLoaded(contentParent: *Wnd, source: string)->*HtmlPluginView
    {
        let result = Wnd.create'HtmlPluginView(contentParent, "sViewer.html")
        result.backgroundStyle = .View

        result.scroll           = Wnd.create'ScrollWnd(result, "", {})
        result.scroll.dockStyle = .Center
        result.scroll.updateFlags(.CompactBars | .TransparentBars)
        result.body = result.scroll.createView'Wnd()
        result.body.backgroundStyle = .View
        result.page = Wnd.create'HtmlPage(result.body, "sViewer.html.page")
        result.page.backgroundStyle = .Window

        let rules = parseHtmlCss(source)
        result.bodyStyle = htmlBodyCssStyle(source, rules.toSlice())
        result.page.cssBackground = result.bodyStyle.background

        let parsed = parseHtmlBlocks(source, rules.toSlice())
        for block in parsed
        {
            let label = Label.create(result.page, block.text.toString(), {}, null, .WordWrap | .AutoHeight)
            result.configureLabel(label, block)
            label.sigLinkActivated += func(linkLabel, url)
            {
                discard linkLabel
                Env.openUrl(url)
            }
            result.blocks.add(HtmlVisualBlock{label, block.kind, block.style})
        }

        if result.blocks.isEmpty()
        {
            let label = Label.create(result.page, "This HTML document has no visible content.", {}, null, .WordWrap | .AutoHeight | .SecondaryText)
            result.blocks.add(HtmlVisualBlock{label, .Paragraph, {}})
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

    func create(contentParent: *Wnd, fileName: string)->*HtmlPluginView
    {
        let source = catch File.readAllText(fileName) as readError
        if readError != null or !Utf8.isValid(source.toSlice()) do
            return .createLoaded(contentParent, "<p>Unable to read this HTML document.</p>")
        return .createLoaded(contentParent, source.toString())
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
