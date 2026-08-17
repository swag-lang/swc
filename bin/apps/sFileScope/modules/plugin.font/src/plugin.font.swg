#global public

using Core, Pixel, Gui, TrueType

private const FontCommandWidth = 456.0
private const FontCommandGlyphSize = 18.0

internal struct FontPluginView
{
    using wnd: Wnd

    #[Swag.Late]
    {
        commands:       *Wnd
        sampleEdit:     *EditBox
        previousButton: *IconButton
        nextButton:     *IconButton
        pageLabel:      *Label
        document:       *FontDocumentView
    }

    details:       String
    sampleDefault: String
}

private impl FontPluginView
{
    mtd refreshPageCommands()
    {
        .previousButton.enable(.document.history.count != 0)
        .nextButton.enable(.document.hasNext)
        let range = Format.toString("U+%{X04}–U+%{X04}", .document.pageStart, .document.pageEnd)
        .pageLabel.setText(range.toString())
    }

    mtd retranslate()
    {
        let replaceSample = .sampleEdit.text() == .sampleDefault.toString()
        .sampleDefault = fontStrings().ui_DefaultSample
        if replaceSample do
            .sampleEdit.setText(.sampleDefault.toString())

        .sampleEdit.setPlaceholder(fontStrings().ui_SamplePlaceholder)
        .previousButton.toolTip = fontStrings().ui_PreviousPage
        .nextButton.toolTip     = fontStrings().ui_NextPage
        .document.invalidate()
    }
}

private impl IWnd for FontPluginView
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        else do
            evt.accepted = false
    }
}

internal impl FontPluginView
{
    func create(contentParent, commandParent: *Wnd, fileName: string)->*FontPluginView fail
    {
        registerFontStrings(contentParent.app())

        var bytes     = try File.readAllBytes(fileName)
        let faceCount = try Face.countFaces(bytes.toSlice())
        let face      = (try Face.load(bytes.toSlice()))!
        var keepFace: bool
        defer if !keepFace do
            face.destroy()

        let cacheKey = Format.toString("%|filescope-font|%{X08}", fileName, Hash.Crc32.compute(bytes.toSlice()))
        let typeFace = try TypeFace.create(cacheKey.toString(), bytes.toSlice())
        let result   = Wnd.create'FontPluginView(contentParent, "sFileScope.font")
        result.backgroundStyle = .View

        with result.commands = Wnd.create'Wnd(commandParent, {0, 0, FontCommandWidth, 36})
        {
            .backgroundStyle = .Window
        }

        result.sampleDefault = fontStrings().ui_DefaultSample
        with result.sampleEdit = EditBox.create(result.commands, result.sampleDefault.toString(), {0, 0, 260, 36}, flags: .ClearButton | .ReleaseFocusOnEnterOrEscape)
        {
            .dockStyle = .Left
            .setMaximumLength(128)
            .setPlaceholder(fontStrings().ui_SamplePlaceholder)
            .sigTextChanged += func|view = result|(edit)
            {
                discard edit
                view.document.invalidate()
            }
        }

        with result.previousButton = IconButton.create(result.commands, result.theme().icon(.ChevronLeft, FontCommandGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .margin.x   = 8
            .toolTip    = fontStrings().ui_PreviousPage
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.document.previousPage()
                view.refreshPageCommands()
            }
        }

        with result.nextButton = IconButton.create(result.commands, result.theme().icon(.ChevronRight, FontCommandGlyphSize), {0, 0, 36, 36})
        {
            .dockStyle  = .Left
            .toolTip    = fontStrings().ui_NextPage
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.document.nextPage()
                view.refreshPageCommands()
            }
        }

        with result.pageLabel = Label.create(result.commands, "", {0, 0, 108, 36}, null, .SecondaryText)
        {
            .dockStyle = .Left
            .margin.x  = 8
            .style.setFont(result.theme().createDefaultFontFS(11), .Regular)
            .setTextAlignment(.Right, .Center)
        }

        result.document = FontDocumentView.create(result, face, typeFace, #move bytes, result.sampleEdit)
        keepFace        = true

        let style = face.styleName.isEmpty() ? fontStrings().ui_Regular : face.styleName.toString()
        if faceCount == 1 do
            result.details = Format.toString(fontStrings().ui_DetailsSingle, face.familyName, style, face.glyphCount, face.unitsPerEm)
        else do
            result.details = Format.toString(fontStrings().ui_DetailsCollection, face.familyName, style, face.glyphCount, face.unitsPerEm, faceCount)

        result.refreshPageCommands()
        result.applyLayout()
        result.setInitialFocus(result.document)
        return result
    }
}

private func createFontPluginView(contentParent, commandParent: *Wnd, fileName: string, view: *#null *FontPluginView) fail
{
    view[] = try FontPluginView.create(contentParent, commandParent, fileName)
}

// Creates the TrueType specimen and character-map view exported through the sFileScope plugin ABI.
func sFileScopePluginCreate(request: const *ViewerRequest, result: *ViewerResult)->bool
{
    if request.apiVersion != ViewerPluginApiVersion do
        return false

    registerFontStrings(request.contentParent.app())
    var view: #null *FontPluginView
    catch createFontPluginView(request.contentParent, request.commandParent, request.fileName, &view) as decodeError
    if decodeError != null
    {
        result.failureReason = Errors.message(decodeError)
        return true
    }

    result.view     = view
    result.commands = view!.commands
    result.details  = view!.details
    return true
}
