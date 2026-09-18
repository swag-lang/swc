using Core, Gui

// The two hidden-volume forms share credential controls, with capacity and confirmation only
// when creating. Their builders remain callable by the application's layout tests.
struct HiddenFields
{
    late
    {
        password:    *PasswordEdit
        keyFiles:    *KeyFileField
        confirm:     *PasswordEdit
        capacity:    *EditBox
        unit:        *ComboBox
        reserve:     *EditBox
        reserveUnit: *ComboBox
    }
}

// Fills `dialog` with what creating a hidden volume asks for, and returns its fields.
//
// The capacity comes first, then the room the outer volume keeps, then the hidden access. The
// units are listed in the order `parseCapacity` reads them.
func buildHiddenCreateForm(dialog: *FormDlg)->HiddenFields
{
    var result: retval
    let form = dialog.form
    VaultForm.configure(form)
    let texts = appStrings()
    result.capacity = form.addTextField(texts.ui_FixedCapacity, "256", help: texts.ui_HiddenCreateHelp)
    result.capacity.setUnsignedIntegerRange(1, 1024 * 1024)
    result.unit = form.addRowChoice()
    result.unit.addItem("MiB")
    result.unit.addItem("GiB")
    result.unit.setSelectedIndex(0, notify: false)
    result.reserve = form.addTextField(texts.ui_OuterReserve, "256", help: texts.ui_OuterReserveHelp)
    result.reserve.setUnsignedIntegerRange(1, 1024 * 1024)
    result.reserveUnit = form.addRowChoice()
    result.reserveUnit.addItem("MiB")
    result.reserveUnit.addItem("GiB")
    result.reserveUnit.setSelectedIndex(0, notify: false)
    result.password = form.addPasswordField(texts.ui_HiddenPassword)
    result.confirm  = form.addPasswordField(texts.ui_ConfirmPassword)
    result.keyFiles = KeyFileField.create(form)
    discard form.addField(texts.ui_KeyFiles, result.keyFiles, help: texts.ui_KeyFilesHelp)
    VaultForm.finish(form)
    return result
}

// Fills `dialog` with the hidden access that protects a hidden volume during an outer mount, and
// returns its fields. Only `password` and `keyFiles` are set.
func buildHiddenProtectionForm(dialog: *FormDlg)->HiddenFields
{
    var result: retval
    let form = dialog.form
    VaultForm.configure(form)
    let texts = appStrings()
    result.password = form.addPasswordField(texts.ui_HiddenPassword, help: texts.ui_HiddenProtectionHelp)
    result.keyFiles = KeyFileField.create(form, canGenerate: false)
    discard form.addField(texts.ui_KeyFiles, result.keyFiles, help: texts.ui_KeyFilesHelp)
    VaultForm.finish(form)
    return result
}
