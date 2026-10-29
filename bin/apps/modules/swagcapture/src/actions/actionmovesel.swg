using Gui

// The keyboard commands that nudge the selected forms by five pixels, or by one.
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
        let main = mainWndOf(cxt)

        let capture = main.getCapture()
        let hasSel  = capture and capture.selection.count

        switch cxt.id
        {
        case .Left, .Top, .Right, .Bottom:
            evt.updatedFields |= .Disabled
            evt.disabled      = not hasSel

        case .Left1, .Top1, .Right1, .Bottom1:
            evt.updatedFields |= .Disabled
            evt.disabled      = not hasSel
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main    = mainWndOf(cxt)
        let capture = unwrap main.getCapture()

        var undo: *Undo
        switch cxt.id
        {
        case .Left1:
            undo         = capture.newUndo(.OffsetSelection)
            undo.newPosX = -1

        case .Top1:
            undo         = capture.newUndo(.OffsetSelection)
            undo.newPosY = -1

        case .Right1:
            undo         = capture.newUndo(.OffsetSelection)
            undo.newPosX = 1

        case .Bottom1:
            undo         = capture.newUndo(.OffsetSelection)
            undo.newPosY = 1

        case .Left:
            undo         = capture.newUndo(.OffsetSelection)
            undo.newPosX = -NudgeFar

        case .Top:
            undo         = capture.newUndo(.OffsetSelection)
            undo.newPosY = -NudgeFar

        case .Right:
            undo         = capture.newUndo(.OffsetSelection)
            undo.newPosX = NudgeFar

        case .Bottom:
            undo         = capture.newUndo(.OffsetSelection)
            undo.newPosY = NudgeFar

        default:
            return false
        }

        Swag.assert(undo != null)
        capture.pushUndo(undo)
        main.invalidate()

        return true
    }
}

// How far Shift and an arrow nudge the selection, in pixels of the capture.
const NudgeFar = 10
