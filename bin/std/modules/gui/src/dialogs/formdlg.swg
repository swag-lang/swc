#global public

// Configures the surface and buttons of a [[Gui.FormDlg]].
struct FormDlgOptions
{
    public
    {
        title:             string = ""           // Surface title.
        confirmButtonText: string = ""           // Confirmation-button text, or empty for the localized OK.
        showCancelButton:  bool   = true         // Whether the dialog offers a cancel button.
        cancelButtonText:  string = ""           // Cancel-button text, or empty for the localized Cancel.
        width                     = 520's32      // Surface width.
        height                    = 360's32      // Surface height before the form is measured; see [[Gui.FormDlg.doModal]].
        resizable:         bool                  // Whether the user can resize the surface.
        formOptions:       FormLayoutOptions     // Field-layout geometry.
    }
}

// Modal dialog whose client area is a form the caller fills with typed fields.
//
// [[Gui.FormDlg.create]] builds the surface, its centered form, and the standard buttons.
// Add the fields through the [[Gui.FormLayoutCtrl]] builders, arrange them once they are
// all present, then run the dialog. The height in [[Gui.FormDlgOptions]] is only what the
// surface starts at: [[Gui.FormDlg.doModal]] gives it the height the fields actually need.
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
    public
    {
        using dialog: Dialog     // Embedded modal-dialog behavior.

        readonly late form: *FormLayoutCtrl     // Form owned by the dialog, empty until the caller adds fields.
    }
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

        result.form           = FormLayoutCtrl.create(result.createContentView(), options.formOptions)
        result.form.dockStyle = .Center

        result.addButton(options.confirmButtonText.count ? options.confirmButtonText : strings().dlg_Ok, Dialog.BtnOk, true)
        if options.showCancelButton do
            result.addButton(options.cancelButtonText.count ? options.cancelButtonText : strings().dlg_Cancel, Dialog.BtnCancel)
        result.applyLayout()
        return result
    }

    // Adapts the surface to the form it holds, centers it on its owner, and returns the modal result.
    mtd doModal()->WndId
    {
        .adaptSizeToForm()
        .surface!.center(.parentSurface!)
        return Dialog.doModal(me)
    }

    // Gives the surface exactly the height its fields need at the width they are laid out in.
    //
    // A box is as tall as what it asks for and no taller. Help text wraps, so a language saying
    // the same thing in more words needs another line of it, and a height authored as a number is
    // right in the language it was tuned in and cuts the last paragraph off in every other one.
    // The form is docked into the view, so the width it wraps at is the width it already has;
    // measuring at any other one answers for a wrapping that will not happen.
    private mtd adaptSizeToForm()
    {
        .applyLayout()

        let grow = .form.measure({.form.position.width, 0}).preferred.y - .form.position.height
        if Math.abs(grow) < 0.5 do
            return

        // Everything measured above is in logical units; a surface rectangle is physical.
        let srf = .surface!
        var pos = srf.position
        pos.height += grow * srf.dpiScale
        srf.setPosition(pos)
        .applyLayout()
    }
}
