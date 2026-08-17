#global public

using Core, Gui

// Creates the reusable HTML view through the sFileScope plugin ABI.
func sFileScopePluginCreate(request: const *ViewerRequest, result: *ViewerResult)->bool
{
    if request.apiVersion != ViewerPluginApiVersion do
        return false

    registerHtmlStrings(request.contentParent.app())
    let view = HtmlView.createFile(request.contentParent, request.fileName)
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
