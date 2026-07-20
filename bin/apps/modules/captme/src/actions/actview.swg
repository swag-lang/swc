using Gui

struct ActionView {}

impl ActionView
{
    newCmdId("Clip")
}

impl IActionUI for ActionView
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: #nonull *CommandStateEvent)->bool
    {
        let main    = cast(#nonull *MainWnd) assume cxt.wnd
        let capture = main.getCapture()
        switch cxt.id
        {
        case Clip:
            evt.setFlags |= .Name | .Disabled | .Checked
            evt.name     = "Hide Outside Box"
            evt.checked  = main.editorOptions.clipToSelection
            // We advertise .Disabled, so provide the state: clipping to the
            // selection is meaningless without a capture.
            evt.disabled = !capture
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main = cast(#nonull *MainWnd) assume cxt.wnd
        switch cxt.id
        {
        case Clip:
            main.editorOptions.clipToSelection = !main.editorOptions.clipToSelection
        }

        return true
    }
}
