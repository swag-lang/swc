using Gui

struct ActionAlign {}

impl ActionAlign
{
    newCmdId("AlignLeft")
    newCmdId("AlignCenter")
    newCmdId("AlignRight")
    newCmdId("AlignTop")
    newCmdId("AlignMiddle")
    newCmdId("AlignBottom")
    newCmdId("SendToFront")
    newCmdId("SendToBack")
    newCmdId("MoveForward")
    newCmdId("MoveBackward")
}

impl IActionUI for ActionAlign
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main = cast(*MainWnd) cxt.wnd!

        if updateFromTable(cxt, evt, [
            {AlignLeft,   appStrings().act_AlignLeft,   .MultiSel, hideDisabled: false},
            {AlignCenter, appStrings().act_AlignCenter, .MultiSel, hideDisabled: false},
            {AlignRight,  appStrings().act_AlignRight,  .MultiSel, hideDisabled: false},
            {AlignTop,    appStrings().act_AlignTop,    .MultiSel, hideDisabled: false},
            {AlignMiddle, appStrings().act_AlignMiddle, .MultiSel, hideDisabled: false},
            {AlignBottom, appStrings().act_AlignBottom, .MultiSel, hideDisabled: false}])
        {
            return true
        }

        let capture = main.getCapture()
        let hasSel  = capture and capture.selection.count

        switch cxt.id
        {
        case .SendToFront:
            evt.updatedFields |= .Disabled | .Icon | .Name
            evt.name          = appStrings().act_SendToFront
            evt.disabled      = !hasSel or capture!.selection.contains(capture!.forms.count - 1)
            evt.icon          = main.theme().icon(.BringToFront)

        case .SendToBack:
            evt.updatedFields |= .Disabled | .Icon | .Name
            evt.name          = appStrings().act_SendToBack
            evt.disabled      = !hasSel or capture!.selection.contains(0)
            evt.icon          = main.theme().icon(.SendToBack)

        case .MoveForward:
            evt.updatedFields |= .Disabled | .Icon | .Name
            evt.name          = appStrings().act_MoveForward
            evt.disabled      = !hasSel or capture!.selection.contains(capture!.forms.count - 1)
            evt.icon          = main.theme().icon(.BringForward)

        case .MoveBackward:
            evt.updatedFields |= .Disabled | .Icon | .Name
            evt.name          = appStrings().act_MoveBackward
            evt.disabled      = !hasSel or capture!.selection.contains(0)
            evt.icon          = main.theme().icon(.SendBackward)
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main    = cast(*MainWnd) cxt.wnd!
        let capture = main.getCapture()!

        var undo: *Undo
        switch cxt.id
        {
        case .AlignLeft:    undo = capture.newUndo(.AlignLeft)
        case .AlignCenter:  undo = capture.newUndo(.AlignCenter)
        case .AlignRight:   undo = capture.newUndo(.AlignRight)
        case .AlignTop:     undo = capture.newUndo(.AlignTop)
        case .AlignMiddle:  undo = capture.newUndo(.AlignMiddle)
        case .AlignBottom:  undo = capture.newUndo(.AlignBottom)
        case .SendToFront:  undo = capture.newUndo(.MoveToFront)
        case .SendToBack:   undo = capture.newUndo(.MoveToBack)
        case .MoveForward:  undo = capture.newUndo(.MoveForward)
        case .MoveBackward: undo = capture.newUndo(.MoveBackward)
        default:            return false
        }

        Debug.assert(undo != null)
        capture.pushUndo(undo)
        main.invalidate()

        return true
    }
}
