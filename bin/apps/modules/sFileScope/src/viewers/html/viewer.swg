#global internal

using Core, Gui

// Creates the integrated reusable HTML view.
func createHtmlViewer(request: const *ViewerRequest, result: *ViewerResult)
{
    registerHtmlStrings(request.contentParent.app())
    let view = HtmlView.createFile(request.contentParent, request.fileName)
    if !view.failureReason.isEmpty()
    {
        result.failureReason = view.failureReason.toString()
        view.destroy()
        return
    }

    if request.reportFailure
    {
        let reportFailure = request.reportFailure!
        view.sigLoadFailed += func|reportFailure|(html, reason) { reportFailure(cast(*Wnd) html, reason) }
    }

    result.view           = view
    result.details        = htmlStrings().ui_Details
    result.revealMatch    = func(wnd, match, text)->bool { return (cast(*HtmlView) wnd).revealFileOffset(match.offset, text) }
    result.isLoading      = func(wnd)->bool { return (cast(*HtmlView) wnd).isLoading() }
    view.sigLinkActivated += func(html, url)
    {
        discard html
        Env.openUrl(url)
    }
}
