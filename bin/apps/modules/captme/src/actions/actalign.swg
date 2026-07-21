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
        let main = cast(*MainWnd) notnull cxt.wnd

        if updateFromTable(cxt, evt, [
            {AlignLeft, "Left", .MultiSel},
            {AlignCenter, "Center", .MultiSel},
            {AlignRight, "Right", .MultiSel},
            {AlignTop, "Top", .MultiSel},
            {AlignMiddle, "Middle", .MultiSel},
            {AlignBottom, "Bottom", .MultiSel}])
        {
            return true
        }

        let capture = main.getCapture()
        let hasSel  = capture and capture.selection.count

        switch cxt.id
        {
        case SendToFront:
            evt.setFlags |= .Disabled | .Icon | .Name
            evt.name     = "Send To Front"
            evt.disabled = !hasSel or capture.selection.contains(capture.forms.count - 1)
            evt.icon     = main.getTheme().getIcon24(.BringToFront)

        case SendToBack:
            evt.setFlags |= .Disabled | .Icon | .Name
            evt.name     = "Send To Back"
            evt.disabled = !hasSel or capture.selection.contains(0)
            evt.icon     = main.getTheme().getIcon24(.SendToBack)

        case MoveForward:
            evt.setFlags |= .Disabled | .Icon | .Name
            evt.name     = "Move Forward"
            evt.disabled = !hasSel or capture.selection.contains(capture.forms.count - 1)
            evt.icon     = main.getTheme().getIcon24(.BringForward)

        case MoveBackward:
            evt.setFlags |= .Disabled | .Icon | .Name
            evt.name     = "Move Backward"
            evt.disabled = !hasSel or capture.selection.contains(0)
            evt.icon     = main.getTheme().getIcon24(.SendBackward)
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main    = cast(*MainWnd) notnull cxt.wnd
        let capture = notnull main.getCapture()

        var undo: *Undo = undefined
        switch cxt.id
        {
        case AlignLeft:
            undo = capture.newUndo(.AlignLeft)
        case AlignCenter:
            undo = capture.newUndo(.AlignCenter)
        case AlignRight:
            undo = capture.newUndo(.AlignRight)
        case AlignTop:
            undo = capture.newUndo(.AlignTop)
        case AlignMiddle:
            undo = capture.newUndo(.AlignMiddle)
        case AlignBottom:
            undo = capture.newUndo(.AlignBottom)
        case SendToFront:
            undo = capture.newUndo(.MoveToFront)
        case SendToBack:
            undo = capture.newUndo(.MoveToBack)
        case MoveForward:
            undo = capture.newUndo(.MoveForward)
        case MoveBackward:
            undo = capture.newUndo(.MoveBackward)
        }

        Debug.assert(undo != null)
        capture.pushUndo(undo)
        main.invalidate()

        return true
    }
}
