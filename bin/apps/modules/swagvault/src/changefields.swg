using Core, Gui, Pixel

// What the change-password box asks for after the open card already states current access.
struct PasswordChangeFields
{
    replacement: *PasswordEdit     // Password it opens with from now on, or empty to remove it.
    confirm:     *PasswordEdit     // `replacement`, entered again.
}

// What the resize box asks for.
struct VaultResizeFields
{
    capacity:     *EditBox         // Capacity the vault should hold from now on.
    unit:         *ComboBox        // Unit `capacity` is written in; `parseCapacity` reads this order.
    keepCapacity: *CheckButton     // Whether only the physical camouflage is refreshed.
}

// Fills `dialog` with what a password change asks for, and returns its fields.
//
// Built apart from the gesture that opens the box so the shape of the form can be measured in
// every language without running a modal loop.
func buildPasswordChangeForm(dialog: *FormDlg)->PasswordChangeFields
{
    let texts = appStrings()
    let form  = dialog.form
    VaultForm.configure(form)

    let replacement = form.addPasswordField(texts.ui_NewPassword, placeholder: texts.ui_OptionalPassword, help: texts.ui_RemovePasswordHelp)
    let confirm     = form.addPasswordField(texts.ui_ConfirmPassword, placeholder: texts.ui_EnterAgain)

    VaultForm.finish(form)
    return {replacement, confirm}
}

// Fills `dialog` with the work-specific choices for resizing a vault, and returns its fields.
func buildVaultResizeForm(dialog: *FormDlg)->VaultResizeFields
{
    let texts = appStrings()
    let form  = dialog.form
    VaultForm.configure(form)

    with let capacity = form.addTextField(texts.ui_NewCapacity, "256", help: texts.ui_NewCapacityHelp)
    {
        .setUnsignedIntegerRange(1, 1024 * 1024)
        .selectAll()
        .enable(false)
        setMachineFont(capacity)
    }

    let unit = VaultForm.addCapacityUnit(form)
    unit.enable(false)

    with let keepCapacity = form.addOptionField(texts.ui_KeepCapacity, help: texts.ui_KeepCapacityHelp)
    {
        .setState(.Checked)
        .sigChanged += func|capacity, unit|(button)
        {
            let enabled = not button.isChecked()
            capacity.enable(enabled)
            unit.enable(enabled)
        }
    }

    VaultForm.finish(form)
    return {capacity, unit, keepCapacity}
}

// Builds the complete replacement key-file set from the current selection. The current files
// remain on the open card; the box contains only the list being changed.
func buildKeyFileChangeForm(dialog: *FormDlg, current: const [..] String)->*KeyFileField
{
    VaultForm.configure(dialog.form)
    let result = KeyFileField.create(dialog.form)
    result.setPaths(current)
    discard dialog.form.addField(appStrings().ui_KeyFiles, result, help: appStrings().ui_KeyFilesHelp)
    VaultForm.finish(dialog.form)
    return result
}
