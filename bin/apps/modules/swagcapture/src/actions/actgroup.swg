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
        let main    = cast(*MainWnd) cxt.wnd!
        let capture = main.getCapture()
        let isLib   = main.libraryMode

        switch cxt.id
        {
        case .Group:
            evt.updatedFields |= .Disabled | .Name
            evt.name          = appStrings().act_Group
            evt.disabled      = isLib or !capture or !capture.canGroup()

        case .Ungroup:
            evt.updatedFields |= .Disabled | .Name
            evt.name          = appStrings().act_Ungroup
            evt.disabled      = isLib or !capture or !capture.canUngroup()
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main    = cast(*MainWnd) cxt.wnd!
        let capture = main.getCapture()!

        switch cxt.id
        {
        case .Group:
            if capture.canGroup() do
                capture.pushUndo(capture.newUndo(.Group))

        case .Ungroup:
            if capture.canUngroup() do
                capture.pushUndo(capture.newUndo(.Ungroup))
        }

        return true
    }
}
