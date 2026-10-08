#global internal
#global namespace Viewers.InDesign

using Core, Core.Errors, Pixel, Gui

private
{
    // The pixels the cache of decoded pages may hold together.
    const PreviewCachePixelLimit = 24 * 1024 * 1024'u64

    // Width of the page selector in the command bar.
    const PageLabelWidth = 96.0
}

// How an InDesign source is shown: through the page previews a native document saved, or as the
// page scenes of an IDML package rendered as markup.
private enum DocumentKind
{
    NativePreview
    Markup
}

// One opened InDesign source: the saved pixels of a native document or the page scenes of an IDML package.
//
// Both kinds load behind one asynchronous opening operation, and the source decides the rendering
// path before a window is attached.
private struct ViewerDocument
{
    kind:   DocumentKind
    native: Document
    markup: Idml.Document
}

// Loads an `.idml` file as markup, and any other InDesign file through its embedded page previews.
private func loadViewerDocument(fileName: string)->ViewerDocument fail
{
    var result: retval
    let extension = Path.extension(fileName) orelse ""
    if Utf8.compare(extension, ".idml", .Latin1NoCase) == 0
    {
        result.kind   = .Markup
        result.markup = try Idml.load(fileName)
    }
    else
    {
        result.kind   = .NativePreview
        result.native = try loadDocument(fileName)
    }

    return result
}

// Describes the InDesign document reader, for native documents and IDML packages, to the host.
func viewerPlugin()->Viewer.Plugin
{
    with var result: retval
    {
        .key          = "indesign"
        .resolveName  = func()->string => texts().ui_Name
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Indesign)
        .create       = &createViewer
        .smokeFixture = "uni-halle-52a.idml"
        .addSelectors(".indd;.idml")
    }

    return result
}

private func commandWidth(metrics: const *ThemeMetrics)->f32 => 2 * themeActionButtonSize(metrics) + PageLabelWidth + 16

// Shows an InDesign document page by page: saved previews of a native file, composed pages of an IDML package.
//
// For saved previews, ImageView provides wheel zoom, pointer-centred panning, and a double-click
// actual-size toggle, all on the pixels the document saved.
struct Panel
{
    using wnd: Wnd

    details:               String
    fileName:              String
    kind:                  DocumentKind
    previews:              Array'Preview
    markupPages:           Array'Idml.Page
    cachedPreviews:        Array'CachedPreview
    cachedPixels:          u64
    previewUseSerial:      u64  = 1
    hasPreviewContent:     bool
    previewIndex:          u64
    markupZoom:            f32  = 1
    markupFit:             bool = true
    markupFitWidth:        bool
    markupRenderedScale:   f32  = 1
    requestedPreviewIndex: u64  = NoPreview
    loadingPreviewIndex:   u64  = NoPreview
    load:                  Viewer.BackgroundLoad'ViewerDocument
    previewLoad:           PreviewLoad
    services:              Viewer.HostServices
    failureReason:         String

    late
    {
        commands:       *Wnd
        info:           *Wnd
        previousButton: *IconButton
        nextButton:     *IconButton
        pageLabel:      *IconButton
        zoomLabel:      *IconButton
        imageView:      *ImageView
    }

    htmlView: *HtmlView?
}

private impl Panel
{
    mtd pageCount()->u64 => .kind == .Markup ? .markupPages.count : .previews.count
    mtd isMarkup()->bool => .kind == .Markup

    mtd pageName(index: u64)->String
    {
        if .kind == .Markup do
            return .markupPages[index].name
        return Format.toString("%", .previews[index].page)
    }

    mtd markupDetails(index: u64)->String
    {
        let page = &.markupPages[index]
        return Format.toString(texts().ui_MarkupDetails, index + 1, .markupPages.count, page.textFrameCount, page.missingImageCount())
    }

    mtd nextPreviewUse()->u64
    {
        if .previewUseSerial == Swag.U64.Max
        {
            .previewUseSerial = 1
            for &preview in .cachedPreviews do
                preview.lastUsed = 0
        }

        let result = .previewUseSerial
        .previewUseSerial += 1
        return result
    }

    mtd refreshPageCommands()
    {
        let pageCount = .pageCount()
        .previousButton.enable(.previewIndex != 0)
        .nextButton.enable(.previewIndex + 1 < pageCount)
        .pageLabel.setText(Format.toString(texts().ui_Page, .previewIndex + 1, pageCount))
    }

    mtd refreshZoom()
    {
        if .isMarkup()
        {
            .zoomLabel.setText(.markupFit ? (.markupFitWidth ? texts().ui_FitWidth : texts().ui_Fit) : Format.toString("% %", cast(u32, Math.round(.markupPageScale(.previewIndex) * 100)), "%"))
            .services.chromeChanged(me)
            return
        }

        .zoomLabel.setText(Format.toString("% %", cast(u32, Math.round(.imageView.effectiveZoom() * 100)), "%"))
        .services.chromeChanged(me)
    }

    mtd markupFitScale(index: u64)->f32
    {
        let page   = &.markupPages[index]
        let client = .clientRect()
        if client.width <= 0 or client.height <= 0 do
            return 1
        let width  = Math.max(client.width - 48, 1)
        let height = Math.max(client.height - 48, 1)
        let scale  = .markupFitWidth ? width / page.bounds.width : Math.min(width / page.bounds.width, height / page.bounds.height)
        return Math.clamp(scale, 0.25, 3)
    }

    mtd markupPageScale(index: u64)->f32 => .markupFit ? .markupFitScale(index) : .markupZoom

    mtd setMarkupZoom(percent: u32)
    {
        .markupFit      = false
        .markupFitWidth = false
        .markupZoom     = cast(f32, Math.clamp(percent, 25'u32, 300'u32)) / 100
        .selectMarkupPage(.previewIndex)
    }

    mtd fitMarkupPage()
    {
        .markupFit      = true
        .markupFitWidth = false
        .selectMarkupPage(.previewIndex)
    }

    mtd fitMarkupWidth()
    {
        .markupFit      = true
        .markupFitWidth = true
        .selectMarkupPage(.previewIndex)
    }

    // Offers the zoom presets that suit the current presentation: the markup view also fits to
    // width, the preview image also shows actual size.
    mtd showZoomMenu()
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        menu.addItem("50%", "scope.indesign.zoom50")
        if not .isMarkup() do
            menu.addItem(texts().ui_Actual, "scope.indesign.zoomActual", .theme().icon(.ActualSize, themeRowIconSize(.themeMetrics())))
        menu.addItem("125%", "scope.indesign.zoom125")
        menu.addItem("150%", "scope.indesign.zoom150")
        menu.addItem("200%", "scope.indesign.zoom200")
        menu.addSeparator()
        menu.addItem(texts().ui_Fit, "scope.indesign.zoomFit", .theme().icon(.FitView, themeRowIconSize(.themeMetrics())), rightName: "F")
        if .isMarkup() do
            menu.addItem(texts().ui_FitWidth, "scope.indesign.zoomFitWidth", .theme().icon(.FitView, themeRowIconSize(.themeMetrics())), rightName: "W")
        let chosen = menu.doModal(.zoomLabel, autoDestroy: true) orelse ""
        if .isMarkup()
        {
            switch chosen
            {
            case "scope.indesign.zoom50":       .setMarkupZoom(50)
            case "scope.indesign.zoom125":      .setMarkupZoom(125)
            case "scope.indesign.zoom150":      .setMarkupZoom(150)
            case "scope.indesign.zoom200":      .setMarkupZoom(200)
            case "scope.indesign.zoomFit":      .fitMarkupPage()
            case "scope.indesign.zoomFitWidth": .fitMarkupWidth()
            }

            return
        }

        switch chosen
        {
        case "scope.indesign.zoom50":     .imageView.setZoom(0.5)
        case "scope.indesign.zoomActual": .imageView.actualSize()
        case "scope.indesign.zoom125":    .imageView.setZoom(1.25)
        case "scope.indesign.zoom150":    .imageView.setZoom(1.5)
        case "scope.indesign.zoom200":    .imageView.setZoom(2)
        case "scope.indesign.zoomFit":    .imageView.zoomToFit()
        }
    }

    mtd reportCurrentDetails()
    {
        .services.showDetails(me, .details)
    }

    mtd showCachedPreview(index: u64)->bool
    {
        for &preview in .cachedPreviews where preview.index == index
        {
            preview.lastUsed = .nextPreviewUse()
            .imageView.setImage(preview.image)
            .hasPreviewContent = true
            .details = Format.toString(texts().ui_Details, index + 1, .previews.count, preview.image.width, preview.image.height)
            .refreshZoom()
            .reportCurrentDetails()
            return true
        }

        return false
    }

    // Keeps the rendered preview of page `index`, evicting the least recently used previews until
    // it fits within `PreviewCachePixelLimit` pixels.
    mtd cachePreview(index: u64, image: *Image)
    {
        let pixelCount = cast(u64, image.width) * cast(u64, image.height)
        for &cached in .cachedPreviews
        {
            if cached.index == index
            {
                .cachedPixels     -= cached.pixelCount
                cached.pixelCount = pixelCount
                cached.lastUsed   = .nextPreviewUse()
                cached.image      = #move image[]
                .cachedPixels     += pixelCount
                return
            }
        }

        while not .cachedPreviews.isEmpty() and .cachedPixels > PreviewCachePixelLimit - pixelCount
        {
            var oldestIndex = 0'u64
            for cached, cachedIndex in .cachedPreviews where cached.lastUsed < .cachedPreviews[oldestIndex].lastUsed do
                oldestIndex = cachedIndex
            .cachedPixels -= .cachedPreviews[oldestIndex].pixelCount
            .cachedPreviews.removeAt(oldestIndex)
        }

        var cached: CachedPreview
        cached.index      = index
        cached.pixelCount = pixelCount
        cached.lastUsed   = .nextPreviewUse()
        cached.image      = #move image[]
        .cachedPreviews.add(#move cached)
        .cachedPixels += pixelCount
    }

    mtd startRequestedPreview()
    {
        if .previewLoad.isPending() or .requestedPreviewIndex == NoPreview do
            return

        .loadingPreviewIndex   = .requestedPreviewIndex
        .requestedPreviewIndex = NoPreview
        .previewLoad.start(.fileName, &.previews[.loadingPreviewIndex])
        .previewLoad.pollFrom(me)
        .services.loadingChanged(me)
    }

    // Shows page `index` from the preview cache, or requests its preview and reports it as loading.
    // The markup presentation shows the page directly.
    mtd selectPreview(index: u64)
    {
        Swag.assert(index < .pageCount())
        if .isMarkup()
        {
            .selectMarkupPage(index)
            return
        }

        .previewIndex = index
        .refreshPageCommands()
        if .showCachedPreview(index)
        {
            .requestedPreviewIndex = NoPreview
            return
        }

        .details = Format.toString(texts().ui_LoadingDetails, index + 1, .previews.count)
        .reportCurrentDetails()
        .requestedPreviewIndex = index
        .startRequestedPreview()
    }

    // Shows markup page `index` in a new HTML view rendered at the page's current scale, in place
    // of the preview image.
    mtd selectMarkupPage(index: u64)
    {
        Swag.assert(index < .markupPages.count)
        .previewIndex = index
        .htmlView?.destroy()
        .markupRenderedScale      = .markupPageScale(index)
        .htmlView = HtmlView.createText(me, .markupPages[index].html(.markupRenderedScale))
        .htmlView.dockStyle       = .Center
        .htmlView.backgroundStyle = .View
        .imageView.hide()
        .hasPreviewContent = true
        .details = .markupDetails(index)
        .refreshPageCommands()
        .refreshZoom()
        .reportCurrentDetails()
        .applyLayout()
        .setInitialFocus(.htmlView)
    }

    // Presents the loaded document from its first page, as markup pages fitted to the view or as
    // the native page previews.
    mtd publishDocument(document: *ViewerDocument)
    {
        .kind = document.kind
        if .isMarkup()
        {
            .fileName       = #move document.markup.fileName
            .markupPages    = #move document.markup.pages
            .markupFit      = true
            .markupFitWidth = false
            .zoomLabel.show()
            .selectMarkupPage(0)
        }
        else
        {
            .fileName = #move document.native.fileName
            .previews = #move document.native.previews
            .selectPreview(0)
            .applyLayout()
            .setInitialFocus(.imageView)
        }

        .retranslate()
    }

    // Applies the current language to the page and zoom commands and, once the document is loaded,
    // to the details of the shown page.
    mtd retranslate()
    {
        .previousButton.toolTip = .isMarkup() ? texts().ui_PreviousDocumentPage : texts().ui_PreviousPage
        .nextButton.toolTip     = .isMarkup() ? texts().ui_NextDocumentPage : texts().ui_NextPage
        .pageLabel.toolTip      = .isMarkup() ? texts().ui_ChooseDocumentPage : texts().ui_ChoosePage
        .zoomLabel.toolTip      = texts().ui_ZoomMenu
        .refreshZoom()
        if not .load.isPending() and .pageCount()
        {
            .refreshPageCommands()
            if .isMarkup()
            {
                .details = .markupDetails(.previewIndex)
                .reportCurrentDetails()
            }
            elif not .showCachedPreview(.previewIndex)
            {
                .details = Format.toString(texts().ui_LoadingDetails, .previewIndex + 1, .previews.count)
                .reportCurrentDetails()
            }

            .applyLayout()
        }
    }

    mtd goToTypedPage(text: string)->bool
    {
        let parsed = catch StrConv.parseU64(text) as parseError
        if parseError != null or parsed.eat != text.count or parsed.ovf or not parsed.value or parsed.value > .pageCount() do
            return false
        .selectPreview(parsed.value - 1)
        return true
    }

    mtd promptGoToPage()
    {
        if not .surface or not .pageCount() do
            return
        var options: EditDlgOptions
        options.title   = texts().ui_GoToPage
        options.message = Format.toString(texts().ui_PageRange, .pageCount()).toString()
        options.text    = Format.toString("%", .previewIndex + 1).toString()
        let dialog = EditDlg.createSingleLine(.surface, options)
        if dialog.doModal() != Dialog.BtnOk do
            return
        discard .goToTypedPage(dialog.text())
    }

    // Shows the page menu: the go-to-page prompt, then one radio entry per page that selects its
    // preview.
    mtd showPageMenu()
    {
        let strings = texts()

        with let menu = MenuCtrl.createPopup(me, owner: me)
        {
            .addItem(strings.ui_GoToPage, "scope.indesign.goToPage", rightName: "Ctrl+G")
            .addSeparator()
        }

        var commands: Array'String
        commands.reserve(.pageCount())
        for index in .pageCount()
        {
            commands.add(Format.toString("scope.indesign.page.%", index))
            menu.addRadioItem(Format.toString(strings.ui_PageMenuEntry, .pageName(index)), commands[index], checked: index == .previewIndex)
        }

        let chosen = menu.doModal(.pageLabel, autoDestroy: true)
        if not chosen do
            return
        if chosen == "scope.indesign.goToPage"
        {
            .promptGoToPage()
            return
        }

        for command, index in commands where chosen == command.toString()
        {
            .selectPreview(index)
            return
        }
    }

    // Collects the matches of each generated HTML page source, tagged with its page index for revealFileOffset.
    //
    // Source matches may include markup; rendered text ranges belong to the HTML view.
    mtd collectMatches(text: string, options: Viewer.SearchOptions, result: *Array'Viewer.SearchMatch)
    {
        if not .isMarkup() do
            return
        for page, index in .markupPages do
            Viewer.collectTextMatches(page.html(1), text, options, index, 0, 0, result)
    }

    mtd revealMatch(match: Viewer.SearchMatch, text: string)->bool
    {
        if not .isMarkup() or match.major >= .markupPages.count do
            return false
        .selectMarkupPage(match.major)
        return .htmlView!.revealFileOffset(match.offset, text)
    }

    mtd searchBounds(result: *Math.Rectangle)->bool => .isMarkup() and .htmlView and .htmlView.searchMatchRect(result)

    mtd clearSearch()
    {
        if .isMarkup() and .htmlView do
            .htmlView.clearSearch()
    }

    mtd retire()->bool
    {
        return .load.retire() and .previewLoad.retire()
    }
}

private impl IWnd for Panel
{
    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        if .isMarkup() and .markupFit and .htmlView
        {
            let scale = .markupFitScale(.previewIndex)
            if Math.abs(scale - .markupRenderedScale) >= 0.01 do
                .selectMarkupPage(.previewIndex)
        }
    }

    mtd impl onTimerEvent(evt: *TimerEvent)
    {
        if evt.timer == .load.timer
        {
            if not .load.poll() do
                return

            var document: ViewerDocument
            .failureReason = .load.finish(&document)
            if not .failureReason.isEmpty()
            {
                .services.failed(me, .failureReason)
                return
            }

            .publishDocument(&document)
            .services.loadingChanged(me)
            return
        }

        if evt.timer != .previewLoad.timer
        {
            evt.accepted = false
            return
        }

        if not .previewLoad.poll() do
            return

        let completedIndex = .loadingPreviewIndex
        .loadingPreviewIndex = NoPreview
        var image: Image
        let failure = .previewLoad.finish(&image)
        if .requestedPreviewIndex == completedIndex do
            .requestedPreviewIndex = NoPreview

        if failure.isEmpty()
        {
            .cachePreview(completedIndex, &image)
            if completedIndex == .previewIndex do
                discard .showCachedPreview(completedIndex)
        }
        elif completedIndex == .previewIndex
        {
            .failureReason = failure
            .services.failed(me, .failureReason)
        }

        .startRequestedPreview()

        .services.loadingChanged(me)
    }

    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind != .Pressed
        {
            evt.accepted = false
            return
        }

        if not .pageCount()
        {
            evt.accepted = false
            return
        }

        switch evt.key
        {
        case .G where evt.modifiers == .Control:
            .promptGoToPage()

        case .Add, .OemPlus:
            if .isMarkup() do
                .setMarkupZoom(cast(u32, Math.round(.markupPageScale(.previewIndex) * 100)) + 25)
            else do
                .imageView.zoomIn()

        case .Subtract, .OemMinus:
            if .isMarkup() do
                .setMarkupZoom(Math.max(cast(u32, Math.round(.markupPageScale(.previewIndex) * 100)), 50) - 25)
            else do
                .imageView.zoomOut()

        case .D0 where not .isMarkup() and evt.modifiers.has(.Control):
            .imageView.actualSize()

        case .F where evt.modifiers == .None:
            if .isMarkup() do
                .fitMarkupPage()
            else do
                .imageView.zoomToFit()

        case .W where .isMarkup() and evt.modifiers == .None:
            .fitMarkupWidth()

        case .Left, .PageUp where evt.modifiers == .None:
            if .previewIndex do
                .selectPreview(.previewIndex - 1)
            else do
                evt.accepted = false

        case .Right, .PageDown where evt.modifiers == .None:
            if .previewIndex + 1 < .pageCount() do
                .selectPreview(.previewIndex + 1)
            else do
                evt.accepted = false

        case .Home where evt.modifiers == .None:
            .selectPreview(0)

        case .End where evt.modifiers == .None:
            .selectPreview(.pageCount() - 1)

        default:
            evt.accepted = false
        }
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .retranslate()
        else do
            evt.accepted = false
    }
}

impl Panel
{
    // Builds the InDesign panel: page commands, zoom button and image view, with Ctrl+G to go to a
    // page and the arrow, page and Home/End keys paging the markup view. Loads the document in the
    // background.
    func create(host: Viewer.Host)->*Panel
    {
        let services = host.services()

        with let result = Wnd.create'Panel(host.contentParent(), "scope.indesign")
        {
            .backgroundStyle = .View
            .services        = services
        }

        result.createPageCommands(host)
        result.createZoomButton(host)
        with result.imageView = ImageView.create(result)
        {
            .backgroundStyle = .View
            .dockStyle       = .Center
            .sigZoomChanged  += func|view = result|(_) { view.refreshZoom() }
        }

        result.hookOnChildEvent = func|view = result|(_, evt)
        {
            switch evt
            {
            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.key == .G and keyEvt.modifiers == .Control:
                view.promptGoToPage()
                return true

            case KeyEvent as keyEvt where view.isMarkup() and keyEvt.kind == .Pressed and keyEvt.modifiers == .None:
                switch keyEvt.key
                {
                case .Left, .PageUp:
                    if view.previewIndex
                    {
                        view.selectPreview(view.previewIndex - 1)
                        return true
                    }

                case .Right, .PageDown:
                    if view.previewIndex + 1 < view.pageCount()
                    {
                        view.selectPreview(view.previewIndex + 1)
                        return true
                    }

                case .Home:
                    view.selectPreview(0)
                    return true

                case .End:
                    view.selectPreview(view.pageCount() - 1)
                    return true
                }

            default:
                break
            }

            return false
        }

        result.applyLayout()
        result.refreshZoom()
        result.load.startPolled(result, host.fileName(), &loadViewerDocument)
        return result
    }

    // Creates the page commands: previous page, next page, and the page selector.
    private mtd createPageCommands(host: Viewer.Host)
    {
        let metrics    = .themeMetrics()
        let buttonSize = themeActionButtonSize(metrics)
        .commands = host.createCommandGroup(commandWidth(metrics))
        with .previousButton = Viewer.createActionButton(me.commands, .ChevronLeft)
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = texts().ui_PreviousPage
            .enable(false)
            .sigPressed += func|view = me|(_)
            {
                if view.previewIndex do
                    view.selectPreview(view.previewIndex - 1)
            }
        }

        with .nextButton = Viewer.createActionButton(me.commands, .ChevronRight)
        {
            .dockStyle = .Left
            .toolTip   = texts().ui_NextPage
            .enable(false)
            .sigPressed += func|view = me|(_)
            {
                if view.previewIndex + 1 < view.pageCount() do
                    view.selectPreview(view.previewIndex + 1)
            }
        }

        with .pageLabel = IconButton.create(me.commands, {}, {0, 0, PageLabelWidth, buttonSize}, "scope.indesign.page", .CenterContent)
        {
            .dockStyle = .Left
            .margin.x  = 8
            .toolTip   = texts().ui_ChoosePage
            .setArrowPosition(.RightDownward)
            .setForm(.Rectangle)
            .style.setFont(me.theme().createDefaultFontFs(11), .Regular)
            .sigPressed += func|view = me|(_) { view.showPageMenu() }
        }
    }

    // Creates the zoom button of the information band.
    private mtd createZoomButton(host: Viewer.Host)
    {
        .info      = host.createInfoGroup(Viewer.ZoomSlotWidth)
        .zoomLabel = Viewer.createZoomButton(me.info, "scope.indesign.zoom", texts().ui_ZoomMenu)
        .zoomLabel.sigPressed += func|view = me|(_) { view.showZoomMenu() }
    }
}

// Creates the integrated InDesign document view and connects its search and lifecycle to the host.
func createViewer(host: Viewer.Host)
{
    let view = Panel.create(host)
    host.attachView(view)

    host.setSearch(Viewer.searchApi(view))

    with var lifecycle: Viewer.LifecycleApi
    {
        .isLoading = func|view|()->bool => view.load.isPending() or view.previewLoad.isPending()
        .needsLoadingOverlay = func|view|()->bool => view.load.isPending() or (view.previewLoad.isPending() and not view.hasPreviewContent)
        .retire    = func|view|()->bool => view.retire()
    }

    host.setLifecycle(lifecycle)
}
