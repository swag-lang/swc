using Gui

struct ActionLibView {}

impl ActionLibView
{
    newCmdId("Ratings")
    newCmdId("LinkMarkers")
}

impl IActionUI for ActionLibView
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let libWnd = cast(*LibraryWnd) cxt.wnd!

        evt.updatedFields |= .Name | .Checked
        switch cxt.id
        {
        case .Ratings:
            evt.name    = appStrings().act_ShowRatings
            evt.checked = libWnd.showRatingOverlay

        case .LinkMarkers:
            evt.name    = appStrings().act_ShowLinkMarkers
            evt.checked = libWnd.showLinkOverlay
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let libWnd = cast(*LibraryWnd) cxt.wnd!

        switch cxt.id
        {
        case .Ratings:     libWnd.showRatingOverlay = !libWnd.showRatingOverlay
        case .LinkMarkers: libWnd.showLinkOverlay = !libWnd.showLinkOverlay
        }

        libWnd.view.invalidate()
        return true
    }
}
