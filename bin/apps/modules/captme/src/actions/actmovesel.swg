using Gui

struct ActionMoveSel {}

impl ActionMoveSel
{
    newCmdId("Left")
    newCmdId("Top")
    newCmdId("Right")
    newCmdId("Bottom")
    newCmdId("Left1")
    newCmdId("Top1")
    newCmdId("Right1")
    newCmdId("Bottom1")
}

impl IActionUI for ActionMoveSel
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main = cast(*MainWnd) assume cxt.wnd

        let capture = main.getCapture()
        let hasSel  = capture and capture.selection.count

        switch cxt.id
        {
        case Left, Top, Right, Bottom:
            evt.setFlags |= .Disabled
            evt.disabled = !hasSel
        case Left1, Top1, Right1, Bottom1:
            evt.setFlags |= .Disabled
            evt.disabled = !hasSel
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main    = cast(*MainWnd) assume cxt.wnd
        let capture = assume main.getCapture()

        var undo: *Undo = undefined
        switch cxt.id
        {
        case Left1:
            undo         = capture.newUndo(.OffsetSelection)
            undo.newPosX = -1
        case Top1:
            undo         = capture.newUndo(.OffsetSelection)
            undo.newPosY = -1
        case Right1:
            undo         = capture.newUndo(.OffsetSelection)
            undo.newPosX = 1
        case Bottom1:
            undo         = capture.newUndo(.OffsetSelection)
            undo.newPosY = 1
        case Left:
            undo         = capture.newUndo(.OffsetSelection)
            undo.newPosX = -5
        case Top:
            undo         = capture.newUndo(.OffsetSelection)
            undo.newPosY = -5
        case Right:
            undo         = capture.newUndo(.OffsetSelection)
            undo.newPosX = 5
        case Bottom:
            undo         = capture.newUndo(.OffsetSelection)
            undo.newPosY = 5
        }

        Debug.assert(undo != null)
        capture.pushUndo(undo)
        main.invalidate()

        return true
    }
}
