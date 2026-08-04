using Gui

struct ActionView {}

impl ActionView
{
    newCmdId("Clip")
}

impl IActionUI for ActionView
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main    = cast(*MainWnd) notnull cxt.wnd
        let capture = main.getCapture()
        switch cxt.id
        {
        case .Clip:
            evt.updatedFields |= .Name | .Disabled | .Checked
            evt.name          = appStrings().act_HideOutsideBox
            evt.checked       = main.editorOptions.clipToSelection

            // We advertise .Disabled, so provide the state: clipping to the
            // selection is meaningless without a capture.
            evt.disabled = !capture
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main = cast(*MainWnd) notnull cxt.wnd
        switch cxt.id
        {
        case .Clip: main.editorOptions.clipToSelection = !main.editorOptions.clipToSelection
        }

        return true
    }
}
