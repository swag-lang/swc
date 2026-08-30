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

// Creates the integrated reusable HTML view.
func createHtmlViewer(host: Viewer.Host)
{
    let view = HtmlView.createFile(host.contentParent(), host.fileName())
    if !view.failureReason.isEmpty()
    {
        host.reject(view.failureReason.toString())
        view.destroy()
        return
    }

    let services = host.services()
    if services.reportFailure
    {
        let reportFailure = services.reportFailure!
        view.sigLoadFailed += func|reportFailure|(html, reason) { reportFailure(cast(*Wnd) html, reason) }
    }

    host.attachView(view)
    host.setDetails(htmlStrings().ui_Details)
    host.setSearch({
        revealMatch: func(wnd, match, text)->bool { return (cast(*HtmlView) wnd).revealFileOffset(match.offset, text) },
        matchBounds: func(wnd, match, bounds)->bool
    {
        discard match
        return (cast(*HtmlView) wnd).searchMatchRect(bounds)
    },
        clear: func(wnd) { (cast(*HtmlView) wnd).clearSearch() }})
    host.setLifecycle({isLoading: func(wnd)->bool { return (cast(*HtmlView) wnd).isLoading() }})
    view.sigLinkActivated += func(html, url)
    {
        discard html
        Env.openUrl(url)
    }
}
