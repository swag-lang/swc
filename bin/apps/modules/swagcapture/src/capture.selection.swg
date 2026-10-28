impl Capture
{
    mtd getSelectedBaseForm()->*BaseForm?
    {
        if .selection.isEmpty() do
            return null
        return .forms[.selection.back()]
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
        let view = .editView
        if view and view.textForm
        {
            var keep = false
            if .selection.count == 1
            {
                if .forms[.selection[0]] is FormCallout as callout do
                    keep = callout == view.textForm
            }

            if not keep do
                view.endTextEdit()
        }

        .updateEditModeFromSelection()
        .updateModelFromSelection()
        with let editView = unwrap .editView
        {
            .main.updateState()
            .invalidate()
        }
    }
}
