#global internal
#global namespace Viewers.Docx

using Core, Gui

// Offers readable Word text before the generic ZIP package structure.
func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key          = "docx"
        .staticName   = "Word document"
        .resolveName  = func()->string => texts().ui_Name
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Docx)
        .create       = &createViewer
        .smokeFixture = "viewer.docx"
        .addSelectors(".docx")
    }

    return result
}

alias Panel = RichDocumentPage'Document

func createViewer(host: Viewer.Host)
{
    let view = Panel.create(host, "scope.docx", texts().ui_Preparing, func(doc)->HtmlStyle
    {
        var style = HtmlStyle.theme()
        style.maxContentWidth = 680
        style.followTheme = not doc.usePaperColors
        return style
    })
    view.openLink = func(url) { Env.openUrl(url) }
    host.setInformation(func|view|(sheet)
    {
        var data: MediaInfoData
        view.document.properties.describe(&data)
        data.describe(sheet)
    })
}
