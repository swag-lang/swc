impl Capture
{
    mtd getSelectedBaseForm()->*BaseForm?
    {
        if .selection.isEmpty()
        {
            return null
        }

        return .forms[.selection.back()]
    }

    mtd getSelectedFormType()->typeinfo?
    {
        if .selection.isEmpty()
        {
            return null
        }

        return Swag.kindOf(.forms[.selection.back()])
    }

    mtd updateEditModeFromSelection()
    {
        if .selection.isEmpty()
        {
            return
        }

        let main = .editView!.main
        if main.editMode == .Selection
        {
            return
        }

        let f = .forms[.selection.back()]
        main.updateEditMode(f)
    }

    mtd updateModelValuesFromSelection()
    {
        if .selection.isEmpty()
        {
            return
        }

        let f = .forms[.selection.back()]
        .editView!.main.updateModelValues(f)
    }

    mtd updateModelFromSelection()
    {
        if .selection.isEmpty()
        {
            return
        }

        let f = .forms[.selection.back()]
        .editView!.main.updateModel(f)
    }

    mtd selectionHasChanged()
    {
        let view = .editView
        if view and view.isEditingText()
        {
            let keep = .selection.count == 1 and cast(*BaseForm, .forms[.selection[0]]) == view.textForm
            if not keep
            {
                view.endTextEdit()
            }
        }

        .updateEditModeFromSelection()
        .updateModelFromSelection()
        with let editView = unwrap .editView
        {
            .main.updateState()
            .main.timeline?.invalidate()
            .invalidate()
        }
    }
}
