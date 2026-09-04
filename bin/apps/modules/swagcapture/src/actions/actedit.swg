using Gui

struct ActionEdit {}

impl ActionEdit
{
    newCmdId("EditText")
    newCmdId("ClearImageInside")
    newCmdId("ResetRotation")
}

impl IActionUI for ActionEdit
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main    = cast(*MainWnd) cxt.wnd!
        let capture = main.getCapture()
        let hasSel  = capture and capture.selection.count

        // Null-initialized: '!lastSelType' below is a genuine "no selection" test.
        var lastSelType: typeinfo?
        if capture
        {
            if capture.selection.count
            {
                let f = capture.forms[capture.selection.back()]
                lastSelType = Swag.kindOf(f)
            }
        }

        switch cxt.id
        {
        case .EditText:
            evt.updatedFields |= .Disabled | .Name | .Hidden
            evt.disabled      = !hasSel or !lastSelType or (lastSelType != FormText and lastSelType != FormCallout)
            evt.hidden        = evt.disabled
            evt.name          = appStrings().ui_MenuEdit

        case .ClearImageInside:
            evt.updatedFields        |= .Disabled | .Name | .Hidden
            evt.disabled, evt.hidden = true
            evt.name                 = appStrings().act_ClearInsideImage

            if capture and hasSel
            {
                for it in capture.selection
                {
                    let itfForm = capture.forms[it]
                    if Swag.kindOf(itfForm) != FormImage do
                        continue
                    let b = cast(*FormImage) itfForm.buffer
                    if b.kind != .Image do
                        continue
                    evt.hidden = false
                    if b.image.isValid()
                    {
                        evt.disabled = false
                        break
                    }
                }
            }

        case .ResetRotation:
            evt.updatedFields        |= .Disabled | .Name | .Hidden
            evt.disabled, evt.hidden = true
            evt.name                 = appStrings().act_ResetRotation

            if capture and hasSel
            {
                for it in capture.selection
                {
                    let itfForm = capture.forms[it]
                    if !itfForm.canRotate() do
                        continue
                    evt.hidden = false
                    let b = cast(*BaseForm) itfForm.buffer
                    if !Math.isZeroEpsilon(b.rotate)
                    {
                        evt.disabled = false
                        break
                    }
                }
            }
        }

        return true
    }

    mtd impl execute(cxt: ActionContext)->bool
    {
        let main    = cast(*MainWnd) cxt.wnd!
        let capture = main.getCapture()!

        switch cxt.id
        {
        case .EditText:

            // Works for both FormText and FormCallout; editText prefills with the current
            // text and pushes a SetText undo that updates every selected editable form.
            let f = capture.forms[capture.selection.back()]
            let t = formEditableText(f)
            if t do
                discard PropWnd.editText(main, t[])
            capture.selectionHasChanged()

        case .ClearImageInside:
            capture.clearImageInside()

        case .ResetRotation:
            capture.pushUndo(capture.newUndo(.ResetRotation))
        }

        return true
    }
}
