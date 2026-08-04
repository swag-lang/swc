#global public

// Configures a modal form materialized entirely from field descriptions.
struct FormDlgOptions
{
    title:             string = ""                   // Surface title.
    confirmButtonText: string = "OK"                 // Confirmation-button text.
    cancelButtonText:  string = "Cancel"             // Cancel-button text, or empty to omit it.
    width                     = 520's32              // Initial surface width.
    height                    = 360's32              // Initial surface height.
    resizable:         bool                          // Whether the user can resize the surface.
    formOptions:       FormLayoutOptions             // Field-layout geometry.
    fields:            Array'FormFieldDefinition     // Fields in display order.
}

// Modal data-driven dialog composed of a [[Gui.FormCtrl]] and standard buttons.
struct FormDlg
{
    using dialog: Dialog     // Embedded modal-dialog behavior.

    readonly
    #[Swag.Late]
    form: *FormCtrl     // Materialized form owned by the dialog.
}

impl FormDlg
{
    // Creates a centered modal form from `options`.
    #[Swag.Discardable]
    func create(from: *Surface, options: FormDlgOptions)->*FormDlg
    {
        Debug.assert(from != null)
        Debug.assert(options.width > 0 and options.height > 0,
                     "form dialog dimensions must be positive")

        let result  = Wnd.create'FormDlg()
        let flags   = options.resizable ? SurfaceFlags.Resizable : SurfaceFlags.None
        let surface = result.createSurface(from, 0, 0, options.width, options.height, flags)
        surface.setTitle(options.title)
        surface.center(from)
        surface.minSize = {Math.min(options.width, 360), Math.min(options.height, 240)}

        result.form           = FormCtrl.create(surface.view(), options.fields.toSlice(), options.formOptions)
        result.form.dockStyle = .Center
        result.form.setAllMargins(result.themeMetrics().dialog_Padding)

        result.addButton(@countof(options.confirmButtonText) ?
        options.confirmButtonText : "OK",
                         Dialog.BtnOk,
                         true)
        if @countof(options.cancelButtonText) do
            result.addButton(options.cancelButtonText, Dialog.BtnCancel)
        result.applyLayout()
        return result
    }

    // Finds a materialized field by identifier.
    mtd findField(id: WndId)->#null const *FormField => .form.findField(id)

    // Returns the text editor for `id`, or null when it has another kind.
    mtd textField(id: WndId)->#null *EditBox => .form.textField(id)

    // Returns the password editor for `id`, or null when it has another kind.
    mtd passwordField(id: WndId)->#null *PasswordEdit => .form.passwordField(id)

    // Returns the choice control for `id`, or null when it has another kind.
    mtd choiceField(id: WndId)->#null *ComboBox => .form.choiceField(id)
}
