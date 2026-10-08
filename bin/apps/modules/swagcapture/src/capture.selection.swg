impl Capture
{
    mtd getSelectedBaseForm()->*BaseForm?
    {
        if .selection.isEmpty() do
            return null
        return assume cast(*BaseForm, .forms[.selection.back()])
    }

    mtd getSelectedFormType()->typeinfo?
    {
        if .selection.isEmpty() do
            return null
        return Swag.kindOf(.forms[.selection.back()])
    }

    mtd updateEditModeFromSelection()
    {
        if .selection.isEmpty() do
            return

        let main = .editView!.main
        if main.editMode == .Selection do
            return

        let f = .forms[.selection.back()]
        main.updateEditMode(f)
    }

    mtd updateModelValuesFromSelection()
    {
        if .selection.isEmpty() do
            return
        let f = .forms[.selection.back()]
        .editView!.main.updateModelValues(f)
    }

    mtd updateModelFromSelection()
    {
        if .selection.isEmpty() do
            return
        let f = .forms[.selection.back()]
        .editView!.main.updateModel(f)
    }

    mtd selectionHasChanged()
    {
        .updateEditModeFromSelection()
        .updateModelFromSelection()
        with let editView = .editView!
        {
            .main.updateState()
            .invalidate()
        }
    }
}
