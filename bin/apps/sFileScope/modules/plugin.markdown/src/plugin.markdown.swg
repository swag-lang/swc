#global public

using Core, Gui

private const ViewerPluginApiVersion = 3'u32

// Creates the Markdown view exported through the sFileScope plugin ABI.
func sFileScopePluginCreate(contentParent, commandParent: *Wnd, fileName: string, apiVersion: u32, commands: *#null *Wnd, details: *String)->#null *Wnd
{
    discard commandParent
    if apiVersion != ViewerPluginApiVersion do
        return null

    commands[] = null
    details[]  = "Markdown · UTF-8 · streamed"
    let view = MarkdownView.createFile(contentParent, fileName, MarkdownStyle.theme())
    view.sigLinkActivated += func(markdown, url)
    {
        discard markdown
        Env.openUrl(url)
    }
    return view
}
