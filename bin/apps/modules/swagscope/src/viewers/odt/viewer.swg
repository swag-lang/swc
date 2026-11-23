#global internal
#global namespace Viewers.Odt

using Core, Gui

// Offers readable OpenDocument text before the generic ZIP package structure.
func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key          = "odt"
        .staticName   = "OpenDocument Text"
        .resolveName  = func()->string => texts().ui_Name
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Odt)
        .create       = &createViewer
        .smokeFixture = "viewer.odt"
        .addSelectors(".odt")
    }

    return result
}

alias Panel = RichDocumentPage'Document

func createViewer(host: Viewer.Host)
{
    let view = Panel.create(host, "scope.odt", texts().ui_Preparing, func(doc)->HtmlStyle
    {
        var style = HtmlStyle.theme()
        style.maxContentWidth = doc.readingWidth
        style.followTheme = false
        return style
    })
    host.setInformation(func|view|(sheet)
    {
        var data: MediaInfoData
        view.document.properties.describe(&data)
        data.describe(sheet)
    })
}
