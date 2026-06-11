using Gui

struct ActionUndo {}

impl ActionUndo
{
    newCmdId("DoUndo")
    newCmdId("DoRedo")
}

impl IActionUI for ActionUndo
{
    mtd impl accept(cxt: ActionContext)->bool
    {
        switch cxt.id
        {
        case DoUndo, DoRedo:
            return true
        }

        return false
    }

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main    = cast(*MainWnd) cxt.wnd
        let capture = main.getCapture()

        switch cxt.id
        {
        case DoUndo:
            evt.setFlags |= .Disabled | .Name | .Icon
            evt.name     = "Undo"
            evt.disabled = true
            if capture do
                evt.disabled = !(assume capture).canUndo()
            evt.icon     = main.getTheme().getIcon24(.Undo)

        case DoRedo:
            evt.setFlags |= .Disabled | .Name | .Icon
            evt.name     = "Redo"
            evt.disabled = true
            if capture do
                evt.disabled = !(assume capture).canRedo()
            evt.icon     = main.getTheme().getIcon24(.Redo)
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main    = cast(*MainWnd) cxt.wnd
        let capture = assume main.getCapture()

        switch cxt.id
        {
        case DoUndo:
            capture.undo()
        case DoRedo:
            capture.redo()
        }

        capture.selectionHasChanged()
        return true
    }
}
