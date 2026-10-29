#global internal
#global namespace Viewers.Html

using Core, Gui

private var g_ZoomPercent: u32 = 100

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
        band:      *Wnd
        address:   *Label
        margin:    *OutlineMargin
    }

    zoomPercent: u32 = 100
    parts:       Array'u64     // Source offsets of the headings the margin lists.
    built:       bool          // Whether the parts exist: a resize reaches the panel while it is built.
}

// The reading measure of a page, and the air of the band its address stands in.
const ReadingColumn = 680.0
const BandHeight    = 56.0

private impl IWnd for Panel
{
    mtd impl onResizeEvent(_: *ResizeEvent)
    {
        if .built do
            .placeMargins()
    }

    mtd impl onNotifyEvent(evt: *NotifyEvent)
    {
        if evt.kind == .LanguageChanged
        {
            .zoomLabel.toolTip = texts().ui_ZoomMenu
            .margin.label      = texts().ui_OnThisPage
            .margin.invalidate()
        }

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
        .placeMargins()
    }

    // Returns where the reading column stands across the view.
    mtd column()->{x: f32, width: f32}
    {
        let width = Math.round(ReadingColumn * cast(f32, .zoomPercent) / 100)
        let room  = .view.clientRect().width
        return {x: Math.round(Math.max((room - width) * 0.5, 0)), width: Math.min(width, room)}
    }

    // Lists the sections of the page in the right margin.
    mtd fillOutline()
    {
        let headings = .view.headings()
        .parts.clear()
        .margin.titles.clear()
        var first = Swag.U32.Max
        for heading in headings do
            first = Math.min(first, heading.level)
        for heading in headings where heading.level > first and heading.level <= first + 2
        {
            .parts.add(heading.sourceOffset)
            .margin.titles.add(heading.title)
        }

        .placeMargins()
    }

    // Stands the address above the reading column and the outline in the margin at its right.
    mtd placeMargins()
    {
        let column = .column()
        .address.setPosition(Math.Rectangle{column.x, 0, column.width, BandHeight}, computeLayout: false)
        let left = column.x + column.width + 48
        .margin.place(left, BandHeight + 24, .clientRect().width - left - 24)
    }

    // Gives the lens the zoom of the page.
    mtd describeLens(entries: *Viewer.LensEntries)
    {
        entries.addZoom(.In, .zoomPercent, func|viewer = me, percent = Viewer.zoomTarget(.In, me.zoomPercent)|() { viewer.setZoom(percent) })
        entries.addZoom(.Out, .zoomPercent, func|viewer = me, percent = Viewer.zoomTarget(.Out, me.zoomPercent)|() { viewer.setZoom(percent) })
        entries.addZoom(.Reset, .zoomPercent, func|viewer = me, percent = Viewer.zoomTarget(.Reset, me.zoomPercent)|() { viewer.setZoom(percent) })
        entries.add(appStrings().cmd_ZoomMenu, func|viewer = me|() { viewer.showZoomMenu() })
    }

    mtd showZoomMenu()
    {
        let percent = Viewer.pickZoom(me, .zoomLabel, .zoomPercent)
        if percent do
            .setZoom(percent)
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

            case MouseEvent as mouse where mouse.kind == .Wheel and mouse.modifiers.has(.Control):
                if mouse.delta.y > 0 do
                    viewer.setZoom(Viewer.zoomIn(viewer.zoomPercent))
                elif mouse.delta.y < 0 do
                    viewer.setZoom(Viewer.zoomOut(viewer.zoomPercent))
                return true

            default:
                return false
            }
        }
    }
}

// Writes where a page is the way an address reads: its two folders above it, then its name.
func addressOf(fileName: string)->String
{
    var parts: Array'string
    var rest = fileName
    for 3
    {
        let name = Path.fileName(rest) orelse ""
        if not name.count do
            break
        parts.add(name)
        rest = Path.directoryName(rest) orelse ""
        if not rest.count do
            break
    }

    var result: #returntype
    for part in parts.reversed()
    {
        if result.length do
            result += " / "
        result += part
    }

    return result
}

// Creates the integrated reusable HTML view.
func createViewer(host: Viewer.Host)
{
    with let result = Wnd.create'Panel(host.contentParent(), "scope.html")
    {
        .backgroundStyle = .View
    }

    // The address of the page, faint and in mono, above its column.
    with result.band = Wnd.create'Wnd(result, Math.Rectangle{0, 0, 0, BandHeight})
    {
        .dockStyle       = .Top
        .backgroundStyle = .Transparent
    }

    with result.address = Label.create(result.band, addressOf(host.fileName()), {}, null, .Ellipsis)
    {
        .style.setFont(result.theme().createDefaultFontFs(12), .Regular)
        .style.addStyleSheetColors("label_Text $label_TextFaint")
        .setTextAlignment(.Left, .Bottom)
    }

    with result.view = HtmlView.createFile(result, host.fileName())
    {
        .dockStyle = .Center
    }

    // The sections of the page in the right margin; choosing one goes there.
    with result.margin = OutlineMargin.create(result, "scope.html.margin")
    {
        .label     = texts().ui_OnThisPage
        .sigChosen += func|result|(_, row)
        {
            if row < result.parts.count do
                discard result.view.revealFileOffset(result.parts[row], "")
        }
    }

    result.view.sigDocumentChanged += func|result|(_) { result.fillOutline() }
    result.built = true

    if not result.view.failureReason.isEmpty()
    {
        host.reject(result.view.failureReason)
        result.destroy()
        return
    }

    result.createZoomControl(host.createInfoGroup(Viewer.ZoomSlotWidth))
    result.hookZoomKeys()

    let services = host.services()
    if services.reportFailure
    {
        let reportFailure: Viewer.ReportFailure = services.reportFailure
        result.view.sigLoadFailed += func|reportFailure, result|(_, reason) { reportFailure(result, reason) }
    }

    result.applyLayout()
    result.setZoom(g_ZoomPercent)
    host.attachView(result)
    DocumentOutline.create(host).bindHtml(result.view)
    host.setDetails(texts().ui_Details)

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
