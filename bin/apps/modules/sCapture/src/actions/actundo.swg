using Gui

struct ActionUndo {}

impl ActionUndo
{
    newCmdId("DoUndo")
    newCmdId("DoRedo")
}

impl IActionUI for ActionUndo
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main    = cast(*MainWnd) cxt.wnd!
        let capture = main.getCapture()

        switch cxt.id
        {
        case .DoUndo:
            evt.updatedFields |= .Disabled | .Name | .Icon
            evt.name          = appStrings().act_Undo
            evt.disabled      = !capture or !capture.canUndo()
            evt.icon          = main.theme().icon(.Undo)

        case .DoRedo:
            evt.updatedFields |= .Disabled | .Name | .Icon
            evt.name          = appStrings().act_Redo
            evt.disabled      = !capture or !capture.canRedo()
            evt.icon          = main.theme().icon(.Redo)
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main    = cast(*MainWnd) cxt.wnd!
        let capture = main.getCapture()!

        switch cxt.id
        {
        case .DoUndo: capture.undo()
        case .DoRedo: capture.redo()
        }

        capture.selectionHasChanged()
        return true
    }
}
