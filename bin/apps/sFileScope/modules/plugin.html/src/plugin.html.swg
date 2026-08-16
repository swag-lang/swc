#global public

using Core, Gui, FileScopePluginApi

// Creates the reusable HTML view through the sFileScope plugin ABI.
func sFileScopePluginCreate(contentParent, commandParent: *Wnd, fileName: string, apiVersion: u32, commands: *#null *Wnd, details: *String, revealMatch: *#null ViewerRevealMatch)->#null *Wnd
{
    discard commandParent
    if apiVersion != ViewerPluginApiVersion do
        return null

    commands[] = null
    details[]  = "HTML · UTF-8 · streamed"
    let view = HtmlView.createFile(contentParent, fileName)
    revealMatch[]         = func(wnd, offset, text)->bool { return (cast(*HtmlView) wnd).revealFileOffset(offset, text) }
    view.sigLinkActivated += func(html, url)
    {
        discard html
        Env.openUrl(url)
    }
    return view
}
