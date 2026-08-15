#global public

using Core, Pixel, Gui

private const ViewerPluginApiVersion = 2'u32

internal struct TextPluginView
{
    using wnd: Wnd

    #[Swag.Late]
    {
        commands:    *Wnd
        sourceEdit:  *RichEditCtrl
        renderScroll: *ScrollWnd
        renderBody:  *Wnd
        renderLabel: *Label
        modeButton:  *PushButton
        wrapButton:  *PushButton
        kindLabel:   *Label
    }

    source:          String
    rendered:        String
    fileName:        String
    kind:            TextRenderKind
    codeRenderer:    CodeTextRenderer
    hasRenderedMode: bool
    showingRendered: bool
    wrapping:        bool
}

internal impl TextPluginView
{
    mtd layoutRendered()
    {
        if .renderScroll.position.width <= 0 do
            return
        let width = Math.max(.renderScroll.paddedClientRect().width - 64, 120)
        .renderLabel.setPosition({32, 24, width, 0})
        .renderLabel.updateAutomaticHeight()
        let height = Math.max(.renderLabel.position.height + 48, .renderScroll.paddedClientRect().height)
        .renderBody.resize(Math.max(width + 64, .renderScroll.paddedClientRect().width), height)
        .renderScroll.setScrollSize(.renderBody.position.width, height)
    }

    mtd updateCommands()
    {
        .modeButton.show(.hasRenderedMode)
        .wrapButton.show(!.showingRendered)
        .modeButton.setText(.showingRendered ? "Source" : "Preview")
        .wrapButton.setText(.wrapping ? "Wrap on" : "Wrap off")
        let width = 114.0 + (.hasRenderedMode ? 96.0 : 0.0) + (!.showingRendered ? 88.0 : 0.0)
        .commands.resize(width, 32)
        .commands.applyLayout()
    }

    mtd showRendered(rendered: bool)
    {
        .showingRendered = rendered and .hasRenderedMode
        .sourceEdit.show(!.showingRendered)
        .renderScroll.show(.showingRendered)
        .updateCommands()
        if .showingRendered do
            .layoutRendered()
        .applyLayout()
    }

    mtd toggleWrap()
    {
        .wrapping = !.wrapping
        .sourceEdit.setFlags(.ReadOnly | (.wrapping ? RichEditFlags.WordWrap : .None))
        .updateCommands()
    }

    mtd setupSourceRenderer()
    {
        switch .kind
        {
        case .Plain, .Markdown:
            PlainTextRenderer.configure(.sourceEdit, .wrapping)
        case .Html:
            .codeRenderer.configure(.sourceEdit, .fileName.toString(), .Markup)
            if .wrapping do
                .sourceEdit.setFlags(.ReadOnly | .WordWrap)
        case .Code:
            .codeRenderer.configure(.sourceEdit, .fileName.toString())
        }
    }
}

internal impl IWnd for TextPluginView
{
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind == .Pressed and evt.key == .W and evt.modifiers.has(.Control) do
            .toggleWrap()
        elif evt.kind == .Pressed and evt.key == .Space and .hasRenderedMode do
            .showRendered(!.showingRendered)
        else do
            evt.accepted = false
    }
}

internal impl TextPluginView
{
    func createLoaded(contentParent, commandParent: *Wnd, fileName, source: string, validText: bool)->*TextPluginView
    {
        let result = Wnd.create'TextPluginView(contentParent, "sViewer.text")
        result.backgroundStyle = .View
        result.fileName        = fileName
        result.source          = source
        result.kind            = textRenderKind(fileName)
        if result.kind == .None do
            result.kind = .Plain
        result.wrapping        = result.kind != .Code

        with result.commands = Wnd.create'Wnd(commandParent, {0, 0, 210, 32})
        {
            .backgroundStyle = .Window
        }

        with result.modeButton = PushButton.create(result.commands, "Preview", {0, 0, 92, 32})
        {
            .dockStyle = .Left
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.showRendered(!view.showingRendered)
            }
        }

        with result.wrapButton = PushButton.create(result.commands, "Wrap on", {0, 0, 84, 32})
        {
            .dockStyle = .Left
            .margin.x  = 4
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.toggleWrap()
            }
        }

        with result.kindLabel = Label.create(result.commands, textRenderName(result.kind, fileName), {0, 0, 106, 32}, null, .SecondaryText)
        {
            .dockStyle = .Right
            .setTextAlignment(.Right, .Center)
        }

        result.sourceEdit           = RichEditCtrl.create(result)
        result.sourceEdit.dockStyle = .Center
        result.sourceEdit.setFlags(.ReadOnly | (result.wrapping ? RichEditFlags.WordWrap : .None))
        result.sourceEdit.marginLeft  = 12
        result.sourceEdit.marginRight = 12
        result.sourceEdit.style.setFont(result.theme().createDefaultFontFS(result.themeMetrics().defaultFixedFontSize), .Regular)
        result.sourceEdit.setText(validText ? source : "This file does not contain supported UTF-8 text.")

        result.renderScroll           = Wnd.create'ScrollWnd(result, "", {})
        result.renderScroll.dockStyle = .Center
        result.renderScroll.updateFlags(.CompactBars | .TransparentBars)
        result.renderBody                 = result.renderScroll.createView'Wnd()
        result.renderBody.backgroundStyle = .View
        result.renderLabel = Label.create(result.renderBody, "", {}, null, .WordWrap | .AutoHeight)
        result.renderLabel.setTextAlignment(.Left, .Top)
        result.renderScroll.hide()
        result.renderScroll.hookOnEvent = func|view = result|(wnd, evt)
        {
            discard wnd
            if evt is ResizeEvent do
                view.layoutRendered()
            return false
        }

        if validText
        {
            switch result.kind
            {
            case .Markdown:
                result.rendered        = MarkdownTextRenderer.render(source)
                result.hasRenderedMode = true
            case .Html:
                result.rendered        = HtmlTextRenderer.render(source)
                result.hasRenderedMode = true
            }
            result.setupSourceRenderer()
        }

        if result.hasRenderedMode
        {
            result.renderLabel.setText(result.rendered.toString())
            result.showRendered(true)
        }
        else do
            result.showRendered(false)

        result.applyLayout()
        result.setInitialFocus(result.hasRenderedMode ? cast(*Wnd) result.modeButton : cast(*Wnd) result.sourceEdit)
        return result
    }

    func create(contentParent, commandParent: *Wnd, fileName: string)->*TextPluginView
    {
        let source = catch File.readAllText(fileName) as readError
        let valid = readError == null and Utf8.isValid(source.toSlice()) and Utf8.indexOf(source.toSlice(), 0'rune) == Swag.U64.Max
        return .createLoaded(contentParent, commandParent, fileName, source.toString(), valid)
    }
}

// Creates the text-family view exported through the sViewer plugin ABI.
func sViewerPluginCreate(contentParent, commandParent: *Wnd, fileName: string, apiVersion: u32, commands: *#null *Wnd)->#null *Wnd
{
    if apiVersion != ViewerPluginApiVersion do
        return null
    let view   = TextPluginView.create(contentParent, commandParent, fileName)
    commands[] = view.commands
    return view
}
