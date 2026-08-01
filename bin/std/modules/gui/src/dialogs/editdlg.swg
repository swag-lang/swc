using Core, Pixel

// Prompts for either a single line or a block of rich text.
public struct EditDlg
{
    using dialog: Dialog     // Embedded dialog state.
    readonly
    {
        #[Swag.Late]
        label:    *Label                  // Optional explanatory message.
        edit:     #null *EditBox          // Single-line editor, when created in single-line mode.
        richEdit: #null *RichEditCtrl     // Rich editor, when created in multi-line mode.
    }
}

public impl EditDlg
{
    // Creates a single-line text prompt.
    #[Swag.Discardable]
    func createSingleLine(from: *Surface)->*EditDlg
    {
        Debug.assert(from != null)
        let dlg     = Wnd.create'EditDlg()
        let metrics = from.wnd.themeMetrics()
        let srf     = dlg.createSurface(from, 0, 0, 450, 210)
        srf.center(from)

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

        dlg.addButton("OK", Dialog.BtnOk, true)
        dlg.addButton("Cancel", Dialog.BtnCancel)
        dlg.sendResizeEvent()
        return dlg
    }

    // Creates a resizable multi-line text prompt.
    #[Swag.Discardable]
    func createMultiLine(from: *Surface, editorHeight: s32 = 150)->*EditDlg
    {
        Debug.assert(from != null)
        Debug.assert(editorHeight > 0, "editor height must be positive")
        let dlg     = Wnd.create'EditDlg()
        let metrics = from.wnd.themeMetrics()
        let srf     = dlg.createSurface(from, 0, 0, 500, 180 + editorHeight, .Resizable)
        srf.center(from)
        srf.minSize.x = 500
        srf.minSize.y = 180 + editorHeight

        dlg.richEdit = RichEditCtrl.create(srf.view(), {0, 0, 0, editorHeight})
        with dlg.richEdit
        {
            .anchorStyle  = .Height
            .dockStyle    = .Bottom
            .margin       = metrics.dialog_Padding
            .setFlags(.flags | .AutoLoseFocus)
            .backgroundColorModel = "$dlg_BtnBarBk"
            .setForm(.Edit)
            .setFrameForm(.Round)
            .setFrameFlags(.FocusBorder)
            .setFocus()
        }

        dlg.addButton("OK", Dialog.BtnOk, true)
        dlg.addButton("Cancel", Dialog.BtnCancel)
        dlg.sendResizeEvent()
        return dlg
    }

    // Replaces the editor contents.
    mtd setText(text: string)
    {
        let edit = .edit
        if edit do
            edit.setText(text)
        else
        {
            let richEdit = notnull .richEdit
            richEdit.setText(text)
        }
    }

    // Returns a copy of the editor contents.
    mtd text()->String
    {
        let edit = .edit
        if edit do
            return edit.text()
        return (notnull .richEdit).text()
    }

    // Creates or updates an explanatory message above the editor.
    mtd setMessage(message: string, height: s32 = 40)
    {
        Debug.assert(height > 0, "message height must be positive")
        if !@isset(.label)
        {
            .label = Label.create((notnull .surface).view(), message, {0, 0, 0, height})
            with me.label
            {
                .dockStyle         = .Center
                .setTextAlignment(.Center, .Center)
            }

            let edit2 = .edit
            if edit2 do
                edit2.margin.y = 0
            else
            {
                let richEdit = notnull .richEdit
                richEdit.margin.y = 0
            }

            let surface = notnull .surface
            var pos     = surface.position
            pos.height        += height
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
