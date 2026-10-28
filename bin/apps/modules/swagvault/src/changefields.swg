using Core, Gui, Pixel

// What the change-password box asks for after the unfolded vault already states current access.
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

    let replacement = form.addPasswordField(texts.ui_NewPassword, placeholder: texts.ui_OptionalPassword, help: texts.ui_RemovePasswordHelp)
    let confirm     = form.addPasswordField(texts.ui_ConfirmPassword, placeholder: texts.ui_EnterAgain)

    VaultForm.finish(form)
    return PasswordChangeFields{replacement, confirm}
}

// Fills `dialog` with the work-specific choices for resizing a vault, and returns its fields.
func buildVaultResizeForm(dialog: *FormDlg)->VaultResizeFields
{
    let texts = appStrings()
    let form  = dialog.form

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
    return VaultResizeFields{capacity, unit, keepCapacity}
}

// Builds the complete key-file set of an access from the current selection; the box contains
// only the list being changed. `canGenerate` offers the action that creates a random key file,
// which only makes sense where a new access is being chosen.
func buildKeyFileChangeForm(dialog: *FormDlg, current: const [..] String, canGenerate = true)->*KeyFileField
{
    let result = KeyFileField.create(dialog.form, canGenerate)
    result.setPaths(current)
    discard dialog.form.addField(appStrings().ui_KeyFiles, result, help: appStrings().ui_KeyFilesHelp)
    VaultForm.finish(dialog.form)
    return result
}
