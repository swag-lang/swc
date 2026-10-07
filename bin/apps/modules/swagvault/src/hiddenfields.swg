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
    let form  = dialog.form
    let texts = appStrings()
    VaultForm.configure(form)

    with var result: retval
    {
        .capacity = form.addTextField(texts.ui_FixedCapacity, "256", help: texts.ui_HiddenCreateHelp)
        .capacity.setUnsignedIntegerRange(1, 1024 * 1024)
        .unit = VaultForm.addCapacityUnit(form)

        .reserve = form.addTextField(texts.ui_OuterReserve, "256", help: texts.ui_OuterReserveHelp)
        .reserve.setUnsignedIntegerRange(1, 1024 * 1024)
        .reserveUnit = VaultForm.addCapacityUnit(form)

        .password = form.addPasswordField(texts.ui_HiddenPassword)
        .confirm  = form.addPasswordField(texts.ui_ConfirmPassword)
        .keyFiles = KeyFileField.create(form)
        discard form.addField(texts.ui_KeyFiles, .keyFiles, help: texts.ui_KeyFilesHelp)
    }

    VaultForm.finish(form)
    return result
}

// Fills `dialog` with the hidden access that protects a hidden volume during an outer mount, and
// returns its fields. Only `password` and `keyFiles` are set.
func buildHiddenProtectionForm(dialog: *FormDlg)->HiddenFields
{
    let form  = dialog.form
    let texts = appStrings()
    VaultForm.configure(form)

    with var result: retval
    {
        .password = form.addPasswordField(texts.ui_HiddenPassword, help: texts.ui_HiddenProtectionHelp)
        .keyFiles = KeyFileField.create(form, canGenerate: false)
        discard form.addField(texts.ui_KeyFiles, .keyFiles, help: texts.ui_KeyFilesHelp)
    }

    VaultForm.finish(form)
    return result
}
