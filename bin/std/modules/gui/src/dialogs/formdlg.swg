#global public

// Configures the surface and buttons of a [[Gui.FormDlg]].
struct FormDlgOptions
{
    title:             string = ""           // Surface title.
    confirmButtonText: string = ""           // Confirmation-button text, or empty for the localized OK.
    showCancelButton:  bool   = true         // Whether the dialog offers a cancel button.
    cancelButtonText:  string = ""           // Cancel-button text, or empty for the localized Cancel.
    width                     = 520's32      // Initial surface width.
    height                    = 360's32      // Initial surface height.
    resizable:         bool                  // Whether the user can resize the surface.
    formOptions:       FormLayoutOptions     // Field-layout geometry.
}

// Modal dialog whose client area is a form the caller fills with typed fields.
//
// [[Gui.FormDlg.create]] builds the surface, its centered form, and the standard buttons.
// Add the fields through the [[Gui.FormLayoutCtrl]] builders, arrange them once they are
// all present, then run the dialog.
//
// ```swag
// let dlg  = FormDlg.create(surface, options)
// let name = dlg.form.addTextField("FOLDER NAME", "New Folder")
// dlg.form.computeLayout()
// if dlg.doModal() == Dialog.BtnOk do
//     createFolder(name.text())
// ```
struct FormDlg
{
    using dialog: Dialog     // Embedded modal-dialog behavior.

    readonly
    #[Swag.Late]
    form: *FormLayoutCtrl     // Form owned by the dialog, empty until the caller adds fields.
}

impl FormDlg
{
    // Creates a centered modal dialog holding an empty form and the standard buttons.
    #[Swag.Discardable]
    func create(from: *Surface, options: FormDlgOptions = {})->*FormDlg
    {
        Debug.assert(from != null)
        Debug.assert(options.width > 0 and options.height > 0, "form dialog dimensions must be positive")

        let result  = Wnd.create'FormDlg()
        let flags   = options.resizable ? SurfaceFlags.Resizable : SurfaceFlags.None
        let surface = result.createSurface(from, 0, 0, options.width, options.height, flags)
        surface.setTitle(options.title)
        surface.center(from)
        surface.minSize = {Math.min(options.width, 360), Math.min(options.height, 240)}

        result.form           = FormLayoutCtrl.create(surface.view(), options.formOptions)
        result.form.dockStyle = .Center
        result.form.setAllMargins(result.themeMetrics().dialog_Padding)

        result.addButton(@countof(options.confirmButtonText) ? options.confirmButtonText : strings().dlg_Ok, Dialog.BtnOk, true)
        if options.showCancelButton do
            result.addButton(@countof(options.cancelButtonText) ? options.cancelButtonText : strings().dlg_Cancel, Dialog.BtnCancel)
        result.applyLayout()
        return result
    }
}
