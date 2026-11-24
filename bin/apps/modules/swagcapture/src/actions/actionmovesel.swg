using Gui

// The commands that nudge the selected forms by one or ten pixels of the capture.
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
        let main    = mainWndOf(cxt)
        let capture = editorCaptureOf(main)
        let texts   = appStrings()
        let far     = cxt.id == .Left or cxt.id == .Top or cxt.id == .Right or cxt.id == .Bottom

        switch cxt.id
        {
        case .Left1, .Left:
            evt.name = Format.toString(texts.act_NudgeLeft, far ? NudgeFar : 1)
            evt.icon = main.theme().icon(.ChevronLeft)

        case .Right1, .Right:
            evt.name = Format.toString(texts.act_NudgeRight, far ? NudgeFar : 1)
            evt.icon = main.theme().icon(.ChevronRight)

        case .Top1, .Top:
            evt.name = Format.toString(texts.act_NudgeUp, far ? NudgeFar : 1)
            evt.icon = main.theme().icon(.ChevronUp)

        case .Bottom1, .Bottom:
            evt.name = Format.toString(texts.act_NudgeDown, far ? NudgeFar : 1)
            evt.icon = main.theme().icon(.ChevronDown)
        }

        evt.updatedFields |= .Name | .Icon | .Disabled | .Hidden
        evt.disabled      = main.libraryMode or not capture or capture.selection.isEmpty()
        evt.hidden        = evt.disabled
        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main      = mainWndOf(cxt)
        let capture   = unwrap main.getCapture()
        with let undo = capture.newUndo(.OffsetSelection)
        {
            switch cxt.id
            {
            case ActionMoveSel.Left1:   .newPosX = -1
            case ActionMoveSel.Right1:  .newPosX = 1
            case ActionMoveSel.Top1:    .newPosY = -1
            case ActionMoveSel.Bottom1: .newPosY = 1
            case ActionMoveSel.Left:    .newPosX = -NudgeFar
            case ActionMoveSel.Right:   .newPosX = NudgeFar
            case ActionMoveSel.Top:     .newPosY = -NudgeFar
            case ActionMoveSel.Bottom:  .newPosY = NudgeFar
            }
        }

        capture.pushUndo(undo)
        main.placeMiniBar()
        main.invalidate()
        return true
    }
}

// How far Shift and an arrow nudge the selection, in pixels of the capture.
const NudgeFar = 10
