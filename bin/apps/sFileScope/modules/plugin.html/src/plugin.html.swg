#global public

using Core, Gui

// Creates the reusable HTML view through the sFileScope plugin ABI.
func sFileScopePluginCreate(request: const *ViewerRequest, result: *ViewerResult)->bool
{
    if request.apiVersion != ViewerPluginApiVersion do
        return false

    registerHtmlStrings(request.contentParent.app())
    let view = HtmlView.createFile(request.contentParent, request.fileName)
    if !view.failureReason.isEmpty()
    {
        result.failureReason = view.failureReason.toString()
        view.destroy()
        return true
    }

    if request.reportFailure
    {
        let reportFailure = request.reportFailure!
        view.sigLoadFailed += func|reportFailure|(html, reason) { reportFailure(cast(*Wnd) html, reason) }
    }

    result.view           = view
    result.details        = htmlStrings().ui_Details
    result.revealMatch    = func(wnd, offset, text)->bool { return (cast(*HtmlView) wnd).revealFileOffset(offset, text) }
    result.isLoading      = func(wnd)->bool { return (cast(*HtmlView) wnd).isLoading() }
    view.sigLinkActivated += func(html, url)
    {
        discard html
        Env.openUrl(url)
    }

    return true
}
