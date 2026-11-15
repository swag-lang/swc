#global internal
#global namespace Viewers.Ods

using Core, Gui

func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key          = "ods"
        .staticName   = "OpenDocument Spreadsheet"
        .resolveName  = func()->string => texts().ui_Name
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Ods)
        .create       = func(host) { Xlsx.createWorkbookViewer(host, &load) }
        .smokeFixture = "viewer.ods"
        .addSelectors(".ods")
    }

    return result
}
