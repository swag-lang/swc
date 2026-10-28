#global public

// Configures the surface and buttons of a [[Gui.FormDlg]].
struct FormDlgOptions
{
    public
    {
        title:             string = ""           // Title of the box: the label of the command it carries out.
        confirmButtonText: string = ""           // Confirmation-button text, or empty for the localized OK.
        showCancelButton:  bool   = true         // Whether the dialog offers a cancel button.
        cancelButtonText:  string = ""           // Cancel-button text, or empty for the localized Cancel.
        width                     = 520's32      // Width of the box.
        height                    = 360's32      // Height of the box before the form is measured; see [[Gui.FormDlg.doModal]].
        resizable:         bool                  // Whether the user can resize the surface.
        formOptions:       FormLayoutOptions     // Field-layout geometry; the labels always stand above their fields.
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
    // Creates a centered modal dialog holding an empty form, Cancel and the primary action.
    //
    // The labels of the form stand above their fields in the soft ink, the way every form of a
    // box reads.
    #[Swag.Discardable]
    func create(from: *Surface, options: FormDlgOptions = {})->*FormDlg
    {
        Swag.assert(from != null)
        Swag.assert(options.width > 0 and options.height > 0, "form dialog dimensions must be positive")

        let result  = Wnd.create'FormDlg()
        let flags   = options.resizable ? SurfaceFlags.Resizable : SurfaceFlags.None
        let surface = result.createSurface(from, 0, 0, options.width, options.height, flags)
        result.setTitle(options.title)
        surface.center(from)
        result.setMinSize(Math.min(options.width, 360), Math.min(options.height, 240))

        var formOptions = options.formOptions
        formOptions.labelPlacement = .Above
        formOptions.labelFlags     |= .SecondaryText
        result.form = FormLayoutCtrl.create(result.createContentView(), formOptions)
        result.form.dockStyle      = .Center

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
        .surface!.center(unwrap .parentSurface)
        return Dialog.doModal(me)
    }

    // Gives the surface exactly the height its fields need at the width they are laid out in.
    //
    // A box is as tall as what it asks for and no taller. Help text wraps, so a language saying
    // the same thing in more words needs another line of it, and a height authored as a number is
    // right in the language it was tuned in and cuts the last paragraph off in every other one.
    // The form is docked into the body, so the width it wraps at is the width it already has;
    // measuring at any other one answers for a wrapping that will not happen.
    internal mtd adaptSizeToForm()
    {
        .applyLayout()
        .fitHeightToContent(.form.measure(Math.Point{.form.position.width, 0}).preferred.y)
    }
}
