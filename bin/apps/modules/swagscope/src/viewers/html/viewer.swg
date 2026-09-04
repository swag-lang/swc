#global internal

using Core, Gui

// Describes the HTML viewer to the host.
func htmlViewerPlugin()->Viewer.Plugin
{
    var result: retval
    result.key          = "html"
    result.staticName   = "HTML"
    result.attach       = &registerHtmlStrings
    result.iconAtlas    = viewerIcons()
    result.iconIndex    = cast(s32) ViewerIcons.Html
    result.create       = &createHtmlViewer
    result.smokeFixture = "viewer.html"
    result.addSelectors(".htm;.html;.shtml;.xht;.xhtml")
    return result
}

internal struct HtmlViewer
{
    using wnd: Wnd

        late
    {
        view:      *HtmlView
        zoomLabel: *IconButton
    }

    zoomPercent: u32 = 100
}

private impl HtmlViewer
{
    mtd setZoom(percent: u32)
    {
        .zoomPercent = Math.clamp(percent, 50'u32, 300'u32)
        var style = HtmlStyle.theme()
        style.bodyFontSize = cast(u32) Math.max(Math.round(16.0 * cast(f32) .zoomPercent / 100), 1)
        style.codeFontSize = cast(u32) Math.max(Math.round(14.0 * cast(f32) .zoomPercent / 100), 1)
        .view.setDocumentStyle(style)
        .zoomLabel.setText(Format.toString("% %", .zoomPercent, "%"))
    }

    mtd showZoomMenu()
    {
        let menu = MenuCtrl.createPopup(me, owner: me)
        menu.addItem("75%", "scope.html.zoom75")
        menu.addItem("100%", "scope.html.zoom100")
        menu.addItem("125%", "scope.html.zoom125")
        menu.addItem("150%", "scope.html.zoom150")
        menu.addItem("200%", "scope.html.zoom200")
        switch menu.doModal(.zoomLabel, autoDestroy: true) orelse ""
        {
        case "scope.html.zoom75":  .setZoom(75)
        case "scope.html.zoom100": .setZoom(100)
        case "scope.html.zoom125": .setZoom(125)
        case "scope.html.zoom150": .setZoom(150)
        case "scope.html.zoom200": .setZoom(200)
        }
    }
}

// Creates the integrated reusable HTML view.
func createHtmlViewer(host: Viewer.Host)
{
    let result = Wnd.create'HtmlViewer(host.contentParent(), "scope.html")
    result.backgroundStyle = .View
    result.view            = HtmlView.createFile(result, host.fileName())
    result.view.dockStyle  = .Center
    if !result.view.failureReason.isEmpty()
    {
        host.reject(result.view.failureReason.toString())
        result.destroy()
        return
    }

    let info = host.createInfoGroup(ViewerZoomSlotWidth)
    with result.zoomLabel = IconButton.create(info, {}, {0, 0, ViewerZoomButtonWidth, 32}, "scope.html.zoom", .CenterContent)
    {
        .dockStyle = .Center
        .margin    = {ViewerInfoControlInset, 0, ViewerInfoControlInset, 0}
        .setText("100%")
        .setArrowPosition(.RightDownward)
        .setForm(.Rectangle)
        .style.setFont(result.theme().createDefaultFontFS(11), .Regular)
        .toolTip    = htmlStrings().ui_ZoomMenu
        .sigPressed += func|viewer = result|(button)
        {
            discard button
            viewer.showZoomMenu()
        }
    }

    result.hookOnChildEvent = func|viewer = result|(wnd, evt)
    {
        discard wnd
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

    let services = host.services()
    if services.reportFailure
    {
        let reportFailure = services.reportFailure!
        result.view.sigLoadFailed += func|reportFailure, result|(html, reason)
        {
            discard html
            reportFailure(result, reason)
        }
    }

    result.applyLayout()
    result.setZoom(100)
    host.attachView(result)
    host.setDetails(htmlStrings().ui_Details)
    host.setSearch({
        revealMatch: func(wnd, match, text)->bool { return (cast(*HtmlViewer) wnd).view.revealFileOffset(match.offset, text) },
        matchBounds: func(wnd, match, bounds)->bool
    {
        discard match
        return (cast(*HtmlViewer) wnd).view.searchMatchRect(bounds)
    },
        clear: func(wnd) { (cast(*HtmlViewer) wnd).view.clearSearch() }})
    host.setLifecycle({isLoading: func(wnd)->bool { return (cast(*HtmlViewer) wnd).view.isLoading() }})
    result.view.sigLinkActivated += func(html, url)
    {
        discard html
        Env.openUrl(url)
    }
}
