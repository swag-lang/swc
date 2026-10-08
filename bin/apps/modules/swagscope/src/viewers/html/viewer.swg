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
        .zoomPercent = Math.clamp(percent, 50'u32, 300'u32)
        var style = HtmlStyle.theme()
        style.bodyFontSize = cast(u32, Math.max(Math.round(16.0 * cast(f32, .zoomPercent) / 100), 1))
        style.codeFontSize = cast(u32, Math.max(Math.round(14.0 * cast(f32, .zoomPercent) / 100), 1))
        .view.setDocumentStyle(style)
        .zoomLabel.setText(Format.toString("% %", .zoomPercent, "%"))
    }

    mtd showZoomMenu()
    {
        with let menu = MenuCtrl.createPopup(me, owner: me)
        {
            .addItem("75%", "scope.html.zoom75")
            .addItem("100%", "scope.html.zoom100")
            .addItem("125%", "scope.html.zoom125")
            .addItem("150%", "scope.html.zoom150")
            .addItem("200%", "scope.html.zoom200")
        }

        switch menu.doModal(.zoomLabel, autoDestroy: true) orelse ""
        {
        case "scope.html.zoom75":  .setZoom(75)
        case "scope.html.zoom100": .setZoom(100)
        case "scope.html.zoom125": .setZoom(125)
        case "scope.html.zoom150": .setZoom(150)
        case "scope.html.zoom200": .setZoom(200)
        }
    }

    // Creates the zoom menu button in the host's information group `info`.
    mtd createZoomControl(info: *Wnd)
    {
        with .zoomLabel = IconButton.create(info, {}, {0, 0, ViewerZoomButtonWidth, 32}, "scope.html.zoom", .CenterContent)
        {
            .dockStyle = .Center
            .margin    = {ViewerInfoControlInset, 0, ViewerInfoControlInset, 0}
            .setText("100%")
            .setArrowPosition(.RightDownward)
            .setForm(.Rectangle)
            .style.setFont(me.theme().createDefaultFontFs(11), .Regular)
            .toolTip    = texts().ui_ZoomMenu
            .sigPressed += func|viewer = me|(?) { viewer.showZoomMenu() }
        }
    }

    // Routes the zoom shortcuts to the page, wherever the keyboard focus is inside it.
    mtd hookZoomKeys()
    {
        .hookOnChildEvent = func|viewer = me|(?, evt)
        {
            switch evt
            {
            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and (keyEvt.key == .Add or keyEvt.key == .OemPlus) and keyEvt.modifiers.has(.Control):
                viewer.setZoom(viewer.zoomPercent + 25)
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and (keyEvt.key == .Subtract or keyEvt.key == .OemMinus) and keyEvt.modifiers.has(.Control):
                viewer.setZoom(viewer.zoomPercent > 50 ? viewer.zoomPercent - 25 : 50)
                return true

            case KeyEvent as keyEvt where keyEvt.kind == .Pressed and keyEvt.key == .D0 and keyEvt.modifiers.has(.Control):
                viewer.setZoom(100)
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

    result.createZoomControl(host.createInfoGroup(ViewerZoomSlotWidth))
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
