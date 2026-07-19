#global #[Swag.ExplicitNullability]
using Gui

struct ActionFlatten {}

impl ActionFlatten
{
    newCmdId("Flatten")
    newCmdId("FlattenAll")
}

impl IActionUI for ActionFlatten
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: #nonull *CommandStateEvent)->bool
    {
        return updateFromTable(cxt, evt, [
            {Flatten, "Flatten", .Selection},
            {FlattenAll, "Flatten All", .Forms}])
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main    = cast(#nonull *MainWnd) cxt.wnd
        let capture = assume main.getCapture()

        var undo: #nonull *Undo = undefined
        switch cxt.id
        {
        case Flatten:
            undo = capture.newUndo(.Flatten)
        case FlattenAll:
            undo = capture.newUndo(.FlattenAll)
        }

        Debug.assert(undo != null)
        capture.pushUndo(undo)
        return true
    }
}
