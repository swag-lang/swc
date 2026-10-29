using Gui

// The commands that edit the selected form in place: its text and how it is set, its inner
// image, its rotation, and the counter of the step markers.
struct ActionEdit {}

impl ActionEdit
{
    newCmdId("EditText")
    newCmdId("ClearImageInside")
    newCmdId("ResetRotation")
    newCmdId("Bold")
    newCmdId("Italic")
    newCmdId("ResetSteps")
}

// Returns the face style of the selected text or callout; `found` is false when the selection is
// neither.
func selectedFontStyle(capture: *Capture?)->{found: bool, style: FontFamilyStyle}
{
    switch capture?.getSelectedBaseForm()
    {
    case FormText as text:       return {true, text.fontStyle}
    case FormCallout as callout: return {true, callout.fontStyle}
    }

    return {false, .Regular}
}

// Returns `style` with its weight (`bold`) or its slant turned on or off.
func toggledFontStyle(style: FontFamilyStyle, bold: bool)->FontFamilyStyle
{
    var isBold   = style == .Bold or style == .BoldItalic
    var isItalic = style == .Italic or style == .BoldItalic
    if bold do
        isBold = not isBold
    else do
        isItalic = not isItalic
    if isBold and isItalic do
        return .BoldItalic
    if isBold do
        return .Bold
    if isItalic do
        return .Italic
    return .Regular
}

impl IActionUI for ActionEdit
{
    acceptOwnCmdIds()

    mtd impl update(cxt: ActionContext, evt: *CommandStateEvent)->bool
    {
        let main    = mainWndOf(cxt)
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
            evt.disabled      = not hasSel or
                                not lastSelType or
                                (lastSelType != FormText and lastSelType != FormCallout and lastSelType != FormStep)
            evt.hidden = evt.disabled
            evt.name   = appStrings().ui_MenuEdit

        case .ClearImageInside:
            evt.updatedFields        |= .Disabled | .Name | .Hidden
            evt.disabled, evt.hidden = true
            evt.name = appStrings().act_ClearInsideImage

            if capture and hasSel
            {
                for it in capture.selection
                {
                    if capture.forms[it] is FormImage as image where image.kind == .Image
                    {
                        evt.hidden = false
                        if image.image.isValid()
                        {
                            evt.disabled = false
                            break
                        }
                    }
                }
            }

        case .Bold, .Italic:
            let {found, style} = selectedFontStyle(capture)
            evt.updatedFields |= .Disabled | .Name | .Checked
            evt.disabled      = not found
            if cxt.id == .Bold
            {
                evt.name    = appStrings().prop_StyleBold
                evt.checked = found and (style == .Bold or style == .BoldItalic)
            }
            else
            {
                evt.name    = appStrings().prop_StyleItalic
                evt.checked = found and (style == .Italic or style == .BoldItalic)
            }

        case .ResetSteps:
            evt.updatedFields |= .Disabled | .Name | .ToolTip
            evt.name          = appStrings().act_ResetSteps
            evt.toolTip       = appStrings().tip_ResetSteps
            evt.disabled      = not capture

        case .ResetRotation:
            evt.updatedFields        |= .Disabled | .Name | .Hidden
            evt.disabled, evt.hidden = true
            evt.name = appStrings().act_ResetRotation

            if capture and hasSel
            {
                for it in capture.selection
                {
                    let itfForm = capture.forms[it]
                    if not itfForm.canRotate() do
                        continue
                    evt.hidden = false
                    if not Math.isZeroEpsilon(itfForm.rotate)
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
        let main    = mainWndOf(cxt)
        let capture = unwrap main.getCapture()

        switch cxt.id
        {
        case .EditText:

            // The words of the last selected form are typed in place, on the canvas.
            let f = capture.forms[capture.selection.back()]
            if inlineTextOf(f).found
            {
                let index = capture.selection.back()
                capture.selection.clear()
                capture.selection.add(index)
                capture.selectionHasChanged()
                main.editWnd.editView.beginTextEdit(f)
            }

        case .ClearImageInside:
            capture.clearImageInside()

        case .ResetRotation:
            capture.pushUndo(capture.newUndo(.ResetRotation))

        case .Bold, .Italic:
            let {found, style} = selectedFontStyle(capture)
            if not found do
                return true
            let toggled = toggledFontStyle(style, bold: cxt.id == .Bold)
            main.propWnd.pushTypedValue(cast(u32, toggled), unwrap capture.getSelectedFormType(), #nameof(FormText.fontStyle), true)
            capture.selectionHasChanged()

        case .ResetSteps:
            capture.nextStepIndex = 1
        }

        return true
    }
}
