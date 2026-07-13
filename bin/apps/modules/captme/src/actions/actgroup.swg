using Gui

struct ActionGroup {}

impl ActionGroup
{
    newCmdId("Group")
    newCmdId("Ungroup")
}

impl IActionUI for ActionGroup
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main    = cast(*MainWnd) cxt.wnd
        let capture = main.getCapture()
        let isLib   = main.libraryMode

        switch cxt.id
        {
        case Group:
            evt.setFlags |= .Disabled | .Name
            evt.name     = "Group"
            evt.disabled = isLib or !capture or !capture.canGroup()

        case Ungroup:
            evt.setFlags |= .Disabled | .Name
            evt.name     = "Ungroup"
            evt.disabled = isLib or !capture or !capture.canUngroup()
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main    = cast(*MainWnd) cxt.wnd
        let capture = assume main.getCapture()

        switch cxt.id
        {
        case Group:
            if capture.canGroup() do
                capture.pushUndo(capture.newUndo(.Group))

        case Ungroup:
            if capture.canUngroup() do
                capture.pushUndo(capture.newUndo(.Ungroup))
        }

        return true
    }
}
