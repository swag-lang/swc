using Core, Pixel

// Prompts for either a single line or a block of rich text.
public struct EditDlg
{
    public using dialog: Dialog     // Embedded dialog state.
    public readonly
    {
        #[Swag.Late]
        label:    *Label                  // Optional explanatory message.
        edit:     #null *EditBox          // Single-line editor, when created in single-line mode.
        richEdit: #null *RichEditCtrl     // Rich editor, when created in multi-line mode.
    }
}

// Configures the title, message and initial contents of an [[Gui.EditDlg]].
public struct EditDlgOptions
{
    public
    {
        title:        string = ""       // Surface title.
        message:      string = ""       // Optional explanatory text shown above the editor.
        text:         string = ""       // Initial editor contents.
        selectAll            = true     // Whether the initial contents start selected.
        editorHeight: s32    = 150      // Editor height, used by the multi-line form.
    }
}

public impl EditDlg
{
    // Creates a single-line text prompt, centered on its owner.
    #[Swag.Discardable]
    func createSingleLine(from: *Surface, options: EditDlgOptions = {})->*EditDlg
    {
        Debug.assert(from != null)
        let dlg     = Wnd.create'EditDlg()
        let metrics = from.wnd.themeMetrics()
        let srf     = dlg.createSurface(from, 0, 0, 450, 210)
        srf.setTitle(options.title)

        dlg.edit = EditBox.create(srf.view(), "")
        with dlg.edit
        {
            .dockStyle = .Bottom
            .margin    = metrics.dialog_Padding
            .style.addStyleSheetColors("edit_Bk $dlg_BtnBarBk")
            .style.addStyleSheetColors("edit_FocusBk $dlg_BtnBarBk")
            .setForm(.RoundedRectangle)
            .setFocus()
        }

        dlg.addButton(strings().dlg_Ok, Dialog.BtnOk, true)
        dlg.addButton(strings().dlg_Cancel, Dialog.BtnCancel)
        dlg.sendResizeEvent()
        dlg.applyOptions(options)
        return dlg
    }

    // Creates a resizable multi-line text prompt, centered on its owner.
    #[Swag.Discardable]
    func createMultiLine(from: *Surface, options: EditDlgOptions = {})->*EditDlg
    {
        Debug.assert(from != null)
        Debug.assert(options.editorHeight > 0, "editor height must be positive")
        let dlg     = Wnd.create'EditDlg()
        let metrics = from.wnd.themeMetrics()
        let srf     = dlg.createSurface(from, 0, 0, 500, 180 + options.editorHeight, .Resizable)
        srf.setTitle(options.title)
        srf.minSize.x = 500
        srf.minSize.y = 180 + options.editorHeight

        dlg.richEdit = RichEditCtrl.create(srf.view(), {0, 0, 0, options.editorHeight})
        with dlg.richEdit
        {
            .anchorStyle = .Height
            .dockStyle   = .Bottom
            .margin      = metrics.dialog_Padding
            .setFlags(.flags | .AutoLoseFocus)
            .backgroundColorModel = "$dlg_BtnBarBk"
            .setForm(.Edit)
            .setFrameForm(.Round)
            .setFrameFlags(.FocusBorder)
            .setFocus()
        }

        dlg.addButton(strings().dlg_Ok, Dialog.BtnOk, true)
        dlg.addButton(strings().dlg_Cancel, Dialog.BtnCancel)
        dlg.sendResizeEvent()
        dlg.applyOptions(options)
        return dlg
    }

    // Applies the shared creation options once the editor exists, then centers the
    // surface: the message can grow the surface, so centering must come last.
    private mtd applyOptions(options: EditDlgOptions)
    {
        if @countof(options.message) do
            .setMessage(options.message)
        .setText(options.text)
        if options.selectAll
        {
            let edit = .edit
            if edit do
                edit.selectAll()
            else do
                .richEdit!.selectAll()
        }

        let surface = .surface!
        surface.center(.parentSurface!)
    }

    // Replaces the editor contents.
    mtd setText(text: string)
    {
        let edit = .edit
        if edit do
            edit.setText(text)
        else
        {
            let richEdit = .richEdit!
            richEdit.setText(text)
        }
    }

    // Returns a copy of the editor contents.
    mtd text()->String
    {
        let edit = .edit
        if edit do
            return edit.text()
        return .richEdit!.text()
    }

    // Creates or updates an explanatory message above the editor.
    mtd setMessage(message: string, height: s32 = 40)
    {
        Debug.assert(height > 0, "message height must be positive")
        if !@isset(.label)
        {
            @assert(.surface != null)
            .label = Label.create(.surface.view(), message, {0, 0, 0, height})
            with me.label
            {
                .dockStyle = .Center
                .setTextAlignment(.Center, .Center)
            }

            let edit2 = .edit
            if edit2 do
                edit2.margin.y = 0
            else
            {
                let richEdit = .richEdit!
                richEdit.margin.y = 0
            }

            // The surface rectangle is physical; the added message height is logical.
            let surface = .surface
            var pos     = surface.position
            pos.height        += height * surface.dpiScale
            surface.minSize.y += height

            // A single-line dialog has only '.edit' (no '.richEdit'). Temporarily
            // drop the rich edit anchor (when present) so it does not fight the
            // resize, then restore it.
            let richEdit2 = .richEdit
            if richEdit2 do
                richEdit2.anchorStyle = .None
            surface.setPosition(pos)
            if richEdit2 do
                richEdit2.anchorStyle = .Height
        }
        else
        {
            .label.setText(message)
        }
    }
}
