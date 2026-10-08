#global internal
#global namespace Viewers.Html

using Core, Gui

// Offers the rendered surface for a page that announces itself, whatever the file is called.
//
// The two spellings a document begins with are the only markers taken. Anything looser claims an
// XML file, a template, or a source file that merely mentions a tag.
private func pluginProbe(content: Viewer.ProbeContent)->bool => content.opensWith("<!doctype html") or content.opensWith("<html")

// Describes the HTML viewer to the host.
func viewerPlugin()->Viewer.Plugin
{
    with var result: retval
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
    }

    zoomPercent: u32 = 100
}

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
        .zoomPercent = Viewer.clampZoom(percent)
        var style = HtmlStyle.theme()
        style.bodyFontSize = cast(u32, Math.max(Math.round(16.0 * cast(f32, .zoomPercent) / 100), 1))
        style.codeFontSize = cast(u32, Math.max(Math.round(14.0 * cast(f32, .zoomPercent) / 100), 1))
        .view.setDocumentStyle(style)
        .zoomLabel.setText(Viewer.zoomText(.zoomPercent))
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
        .zoomLabel.sigPressed += func|viewer = me|(?) { viewer.showZoomMenu() }
    }

    // Routes the zoom shortcuts to the page, wherever the keyboard focus is inside it.
    mtd hookZoomKeys()
    {
        .hookOnChildEvent = func|viewer = me|(?, evt)
        {
            switch evt
            {
            case KeyEvent as keyEvt where Viewer.isZoomKey(keyEvt):
                viewer.setZoom(Viewer.zoomAfterKey(keyEvt, viewer.zoomPercent))
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
        .view = HtmlView.createFile(result, host.fileName())
        .view.dockStyle  = .Center
    }

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
        result.view.sigLoadFailed += func|reportFailure, result|(?, reason) { reportFailure(result, reason) }
    }

    result.applyLayout()
    result.setZoom(100)
    host.attachView(result)
    DocumentOutline.create(host).bindHtml(result.view)
    host.setDetails(texts().ui_Details)

    with var search: Viewer.SearchApi
    {
        .revealMatch = func|result|(match, text)->bool => result.view.revealFileOffset(match.offset, text)
        .matchBounds = func|result|(?, bounds)->bool => result.view.searchMatchRect(bounds)
        .clear       = func|result|() => result.view.clearSearch()
    }

    host.setSearch(search)

    host.setLifecycle({isLoading: func|result|()->bool => result.view.isLoading()})
    result.view.sigLinkActivated += func(?, url)
    {
        Env.openUrl(url)
    }
}
