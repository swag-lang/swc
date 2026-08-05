using Gui

struct ActionZoom {}

impl ActionZoom
{
    newCmdId("Zoom1")
    newCmdId("ZoomFit")
    newCmdId("ZoomIn")
    newCmdId("ZoomOut")
}

impl IActionUI for ActionZoom
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main    = cast(*MainWnd) cxt.wnd!
        let capture = main.getCapture()

        switch cxt.id
        {
        case .Zoom1:
            evt.updatedFields |= .Name | .Disabled
            evt.name          = appStrings().act_ActualSize
            evt.disabled      = !capture

        case .ZoomFit:
            evt.updatedFields |= .Name | .Disabled
            evt.name          = appStrings().act_FitToView
            evt.disabled      = !capture

        case .ZoomIn:
            evt.updatedFields |= .Name | .Disabled | .Icon
            evt.name          = appStrings().act_ZoomIn
            evt.disabled      = !capture or !main.editWnd.editView.canZoomIn()
            evt.icon          = main.theme().icon(.ZoomIn)

        case .ZoomOut:
            evt.updatedFields |= .Name | .Disabled | .Icon
            evt.name          = appStrings().act_ZoomOut
            evt.disabled      = !capture or !main.editWnd.editView.canZoomOut()
            evt.icon          = main.theme().icon(.ZoomOut)
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main = cast(*MainWnd) cxt.wnd!
        let view = main.editWnd.editView

        switch cxt.id
        {
        case .Zoom1:   view.setZoom(1)
        case .ZoomFit: view.zoomToFit()
        case .ZoomIn:  view.zoomIn()
        case .ZoomOut: view.zoomOut()
        }

        return true
    }
}
