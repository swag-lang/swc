using Core, Gui

// What the boxes that change a vault share: the spacing of their help, and the capacity unit.
//
// Their labels stand above the fields in the soft ink, the way every form of a box reads, so the
// boxes keep the toolkit's own form options.
struct VaultForm {}

impl VaultForm
{
    // Spaces the help paragraphs of `form` and lays it out again, once its rows are all present.
    func finish(form: *FormLayoutCtrl)
    {
        for row in form.rows where row.help != null do
            row.help.setLineGap(cast(s32, form.themeMetrics().dialog_BtnPadding / 2))
        form.computeLayout()
        form.invalidateLayout()
    }

    // Adds the unit choice that follows a capacity field, in the order `parseCapacity` reads.
    func addCapacityUnit(form: *FormLayoutCtrl)->*ComboBox
    {
        with let result = form.addRowChoice()
        {
            for unit in [appStrings().ui_UnitMiB, appStrings().ui_UnitGiB] do
                .addItem(unit)
            .setSelectedIndex(0, notify: false)
            setMachineFont(result)
        }

        return result
    }
}
