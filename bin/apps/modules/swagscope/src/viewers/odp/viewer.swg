#global internal
#global namespace Viewers.Odp

using Core, Gui

func viewerPlugin()->Viewer.Plugin
{
    with var result: #returntype
    {
        .key          = "odp"
        .staticName   = "OpenDocument Presentation"
        .resolveName  = func()->string => texts().ui_Name
        .attach       = &registerTexts
        .iconAtlas    = viewerIcons()
        .iconIndex    = cast(s32, ViewerIcons.Odp)
        .create       = func(host) { Pptx.createPresentationViewer(host, &load) }
        .smokeFixture = "viewer.odp"
        .addSelectors(".odp")
    }

    return result
}
