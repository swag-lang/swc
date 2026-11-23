#global internal
#global namespace Viewers.Rtf

using Core, Gui, Pixel

private func loadThumbnail(fileName: string, _: u32)->Image fail
{
    let source  = catch Document.load(fileName) { return {} }
    let content = HtmlView.extractText(source.html.toString())
    if not content.count do
        return {}
    var renderer = try ThumbnailRenderer.create()
    return try renderer.renderContent("RTF", content.toString())
}

// Reads formatted RTF body content before offering its raw source as basic text.
func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key          = "rtf"
        .staticName   = "Rich text document"
        .resolveName  = func()->string => texts().ui_Name
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Rtf)
        .create       = &createViewer
        .probe        = func(content: Viewer.ProbeContent)->bool => content.opensWith("{\\rtf")
        .thumbnail    = &loadThumbnail
        .textual      = true
        .smokeFixture = "viewer.rtf"
        .addSelectors(".rtf")
    }

    return result
}

alias Panel = RichDocumentPage'Document

func createViewer(host: Viewer.Host)
{
    discard Panel.create(host, "scope.rtf", texts().ui_Preparing, func(doc)->HtmlStyle
    {
        var style = HtmlStyle.theme()
        style.maxContentWidth = 680
        style.followTheme = not doc.paper
        return style
    }, withOutline: false)
}
