using Gui

struct ActionSelection {}

impl ActionSelection
{
    newCmdId("SelectAll")
    newCmdId("SelectSameAll")
    newCmdId("DeSelectAll")
    newCmdId("InvertSelection")
    newCmdId("DeleteSelection")
    newCmdId("Snap")
    newCmdId("Freeze")
}

impl IActionUI for ActionSelection
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main    = cast(*MainWnd) cxt.wnd!
        let capture = main.getCapture()
        let hasSel  = capture and capture.selection.count
        let isLib   = main.libraryMode

        switch cxt.id
        {
        case .SelectAll:
            evt.updatedFields |= .Disabled | .Name
            evt.disabled      = !capture or !capture.forms.count or isLib
            evt.name          = appStrings().act_SelectAll

        case .SelectSameAll:
            evt.updatedFields |= .Disabled | .Name
            evt.disabled      = !capture or !capture.forms.count or !hasSel or isLib
            evt.name          = appStrings().act_SelectSimilar

        case .DeSelectAll:
            evt.updatedFields |= .Disabled | .Name
            evt.disabled      = !capture or !hasSel or isLib
            evt.name          = appStrings().act_DeselectAll

        case .InvertSelection:
            evt.updatedFields |= .Disabled | .Name

            // Nothing to invert when there are no forms (matches SelectAll).
            evt.disabled = !capture or !capture.forms.count or isLib
            evt.name     = appStrings().act_InvertSelection

        case .DeleteSelection:
            evt.updatedFields |= .Disabled | .Name | .Icon
            evt.disabled      = !hasSel
            evt.name          = appStrings().act_Delete
            evt.icon          = main.theme().icon(.Remove)

        case .Snap:
            evt.updatedFields |= .Name | .Checked
            evt.name          = appStrings().act_SnapToForms
            evt.checked       = main.snap

        case .Freeze:
            evt.updatedFields |= .Name | .Checked | .Disabled
            evt.name          = appStrings().act_FreezeSelection
            evt.checked       = main.freezeSel
            evt.disabled      = !capture or isLib
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main    = cast(*MainWnd) cxt.wnd!
        let capture = main.getCapture()!

        switch cxt.id
        {
        case .SelectAll:
            capture.selection.clear()
            for i in capture.forms.count do
                capture.selection.add(i)
            capture.selectionHasChanged()

        case .SelectSameAll:
            let firstType = capture.getSelectedFormType()
            capture.selection.clear()
            for form, i in capture.forms
            {
                if Swag.kindOf(form) == firstType do
                    capture.selection.add(i)
            }

            capture.selectionHasChanged()

        case .DeSelectAll:
            capture.selection.clear()
            capture.selectionHasChanged()

        case .InvertSelection:
            var newSel: Array'u64
            for i in capture.forms.count where !capture.selection.contains(i) do
                newSel.add(i)
            capture.selection = newSel
            capture.selectionHasChanged()

        case .DeleteSelection:
            capture.pushUndo(capture.newUndo(.DeleteSelection))

        case .Snap:
            main.snap = !main.snap

        case .Freeze:
            main.freezeSelection(!main.freezeSel)
        }

        return true
    }
}
