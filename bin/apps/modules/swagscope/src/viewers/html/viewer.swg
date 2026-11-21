#global internal
#global namespace Viewers.Html

using Core, Gui, Pixel

private var g_ZoomPercent: u32 = 100
private const ThumbnailSourceSize = 16 * 1024'u64

// Reads the visible text from a bounded HTML prefix for the Explorer preview.
private func loadThumbnail(fileName: string, _: u32)->Image fail
{
    var stream  = catch File.openReadLive(fileName) { return {} }
    let source  = catch stream.readUtf8Chunk(ThumbnailSourceSize) { return {} }
    let content = HtmlView.extractText(source.toString())
    if not content.count do
        return {}
    var renderer = try ThumbnailRenderer.create()
    return try renderer.renderContent("HTML", content.toString())
}

// Offers the rendered surface for a page that announces itself, whatever the file is called.
//
// The two spellings a document begins with are the only markers taken. Anything looser claims an
// XML file, a template, or a source file that merely mentions a tag.
private func pluginProbe(content: Viewer.ProbeContent)->bool => content.opensWith("<!doctype html") or content.opensWith("<html")

// Describes the HTML viewer to the host.
func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key          = "html"
        .staticName   = "HTML"
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Html)
        .create       = &createViewer
        .probe        = &pluginProbe
        .thumbnail    = &loadThumbnail
        .textual      = true
        .smokeFixture = "viewer.html"
        .addSelectors(".htm;.html;.shtml;.xht;.xhtml")
    }

    return result
}

// The HTML viewer: the document view and its zoom readout.
struct Panel
{
    using wnd: Wnd

    late
    {
        view:      *HtmlView
        zoomLabel: *IconButton
    }

    zoomPercent: u32 = 100
    outline:     *DocumentOutline?
    services:    Viewer.HostServices
    shownFacts:  HtmlDocumentFacts     // What the information sheet was last told of the page's head.
    factsFinal:  bool     // Whether `shownFacts` was read from a page that had finished loading.
    canvasColor: Color
}

// The fallback reading measure for a page without its own CSS width.
const ReadingColumn = 680.0

private impl IWnd for Panel
{
    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged do
            .zoomLabel.toolTip = texts().ui_ZoomMenu

        .wnd.IWnd.onNotifyEvent(evt)
    }
}

private impl Panel
{
    internal mtd setZoom(percent: u32)
    {
        .zoomPercent  = Viewer.clampZoom(percent)
        g_ZoomPercent = .zoomPercent
        var style = HtmlStyle.theme()
        style.bodyFontSize    = cast(u32, Math.max(Math.round(16.0 * cast(f32, .zoomPercent) / 100), 1))
        style.codeFontSize    = cast(u32, Math.max(Math.round(14.0 * cast(f32, .zoomPercent) / 100), 1))
        style.maxContentWidth = Math.round(ReadingColumn * cast(f32, .zoomPercent) / 100)
        .view.setDocumentStyle(style)
        .zoomLabel.setText(Viewer.zoomText(.zoomPercent))
    }

    // Gives the lens the zoom of the page.
    mtd describeLens(entries: *Viewer.LensEntries)
    {
        entries.add(texts().ui_ReaderView, .Wrap, func|viewer = me|() { viewer.view.setReaderMode(not viewer.view.isReaderMode()) }, checked: .view.isReaderMode())
        entries.addZoom(.In, .zoomPercent, func|viewer = me, percent = Viewer.zoomTarget(.In, me.zoomPercent)|() { viewer.setZoom(percent) })
        entries.addZoom(.Out, .zoomPercent, func|viewer = me, percent = Viewer.zoomTarget(.Out, me.zoomPercent)|() { viewer.setZoom(percent) })
        entries.addZoom(.Reset, .zoomPercent, func|viewer = me, percent = Viewer.zoomTarget(.Reset, me.zoomPercent)|() { viewer.setZoom(percent) })
        entries.add(appStrings().cmd_ZoomMenu, .ZoomLevels, func|viewer = me|() { viewer.showZoomMenu() }, bindId: "scope.html.zoomMenu")
    }

    mtd showZoomMenu()
    {
        let percent = Viewer.pickZoom(me, .zoomLabel, .zoomPercent)
        if percent do
            .setZoom(percent)
    }

    // Names the encoding the page is read with and what decided it, the way the information
    // sheet reads it: "Windows-1252 · declared by the page".
    internal mtd encodingText()->String
    {
        let strings = texts()
        var source: string
        switch #complete .view.encodingSource
        {
        case .Content:       source = strings.ui_EncodingDetected
        case .ByteOrderMark: source = strings.ui_EncodingMarked
        case .Declaration:   source = strings.ui_EncodingDeclared
        }

        return Format.toString("% · %", Viewer.encodingName(.view.encoding), source)
    }

    // Describes the page in the information sheet: its format, and the encoding in force for the
    // document on screen, which a followed link may have changed.
    mtd describeInformation(sheet: *InfoSheet)
    {
        var data: MediaInfoData

        // What the page says of itself in its head, as written.
        let facts = .view.documentFacts()
        .shownFacts = facts
        if not facts.title.isEmpty() or not facts.language.isEmpty() or not facts.description.isEmpty()
        {
            data.add(.Document, group: true)
            if not facts.title.isEmpty() do
                data.add(.Title, facts.title)
            if not facts.language.isEmpty() do
                data.add(.Language, facts.language)
            if not facts.description.isEmpty() do
                data.add(.Description, facts.description)
        }

        data.add(.Text, group: true)
        data.add(.Format, "HTML")
        data.add(.Encoding, .encodingText())
        data.describe(sheet)
    }

    // Creates the zoom menu button in the host's information group `info`.
    mtd createZoomControl(info: *Wnd)
    {
        .zoomLabel = Viewer.createZoomButton(info, "scope.html.zoom", texts().ui_ZoomMenu)
        .zoomLabel.sigPressed += func|viewer = me|(_) { viewer.showZoomMenu() }
    }

    // Routes the zoom shortcuts to the page, wherever the keyboard focus is inside it.
    mtd hookZoomKeys()
    {
        .hookOnChildEvent = func|viewer = me|(_, evt)
        {
            switch evt
            {
            case KeyEvent as keyEvt where Viewer.isZoomKey(keyEvt):
                viewer.setZoom(Viewer.zoomAfterKey(keyEvt, viewer.zoomPercent))
                return true

            case MouseEvent as mouse where Viewer.isZoomWheel(mouse):
                viewer.setZoom(Viewer.zoomAfterWheel(mouse, viewer.zoomPercent))
                return true

            default:
                return false
            }
        }
    }
}

// Creates the integrated reusable HTML view.
func createViewer(host: Viewer.Host)
{
    with let result = Wnd.create'Panel(host.contentParent(), "scope.html")
    {
        .backgroundStyle = .View
    }

    // Host air remains separate from authored page margins and responsive CSS.
    let inset = result.themeMetrics().floating_Inset
    with result.view = HtmlView.createFile(result, host.fileName())
    {
        .dockStyle = .Center
        .margin    = {inset, 0, inset, 0}
    }

    if not result.view.failureReason.isEmpty()
    {
        host.reject(result.view.failureReason)
        result.destroy()
        return
    }

    result.createZoomControl(host.createInfoGroup(Viewer.ZoomSlotWidth))
    result.hookZoomKeys()

    // A head read once the page has streamed in changes what the information sheet says.
    //
    // Only a page still arriving, or a newly followed one, can change its head; reading the facts
    // walks every node, so the relayouts of a loaded page for zoom or width do not read them again.
    let services = host.services()
    result.services = services
    result.view.sigDocumentChanged += func|result|(_)
    {
        let loading = result.view.isLoading()
        let color   = result.view.authoredCanvasBackground()
        if result.canvasColor != color
        {
            result.canvasColor = color
            result.services.informationChanged(result)
        }

        if result.factsFinal and not loading do
            return
        result.factsFinal = not loading

        let facts = result.view.documentFacts()
        if facts.title != result.shownFacts.title or
           facts.language != result.shownFacts.language or
           facts.description != result.shownFacts.description
        {
            result.shownFacts = facts
            result.services.informationChanged(result)
        }
    }

    if services.reportFailure
    {
        let reportFailure: Viewer.ReportFailure = services.reportFailure
        result.view.sigLoadFailed += func|reportFailure, result|(_, reason) { reportFailure(result, reason) }
    }

    result.applyLayout()
    result.setZoom(g_ZoomPercent)
    host.attachView(result)
    result.outline = DocumentOutline.create(host)
    result.outline.bindHtml(result.view)
    host.setDetails(texts().ui_Details)
    host.setInformation(func|result|(sheet) { result.describeInformation(sheet) })

    with var search: Viewer.SearchApi
    {
        .revealMatch = func|result|(match, text)->bool => result.view.revealFileOffset(match.offset, text)
        .matchBounds = func|result|(_, bounds)->bool => result.view.searchMatchRect(bounds)
        .clear       = func|result|() => result.view.clearSearch()
    }

    host.setSearch(search)
    host.setLensSource(func|result|(entries) { result.describeLens(entries) })

    host.setLifecycle({isLoading: func|result|()->bool => result.view.isLoading()})
    result.view.sigLinkActivated += func(_, url)
    {
        Env.openUrl(url)
    }
}
