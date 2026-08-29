#global internal

using Core, Gui

// Creates the integrated reusable HTML view.
func createHtmlViewer(host: FileScope.Host)
{
    registerHtmlStrings(host.application())
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
