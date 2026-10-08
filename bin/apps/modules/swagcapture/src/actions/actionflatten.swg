using Gui

// The commands that burn the selected forms, or all of them, into the capture image.
struct ActionFlatten {}

impl ActionFlatten
{
    newCmdId("Flatten")
    newCmdId("FlattenAll")
}

impl IActionUI for ActionFlatten
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        return updateFromTable(cxt, evt, [
            {Flatten,    appStrings().act_Flatten,    .Selection, hideDisabled: false},
            {FlattenAll, appStrings().act_FlattenAll, .Forms,     hideDisabled: false}])
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main    = mainWndOf(cxt)
        let capture = main.getCapture()!

        var undo: *Undo
        switch cxt.id
        {
        case .Flatten:    undo = capture.newUndo(.Flatten)
        case .FlattenAll: undo = capture.newUndo(.FlattenAll)
        default:          return false
        }

        Swag.assert(undo != null)
        capture.pushUndo(undo)
        return true
    }
}
