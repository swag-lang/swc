using Core, Pixel

public struct EditDlg
{
    using dialog: Dialog
    label:        #late *Label
    edit:         #null *EditBox
    richEdit:     #null *RichEditCtrl
}

public impl EditDlg
{
    // Creates the message box
    func createSingleLine(from: *Surface)->*EditDlg
    {
        let dlg     = Wnd.create'EditDlg()
        let metrics = from.wnd.getThemeMetrics()
        let srf     = dlg.createSurface(from, 0, 0, 450, 210)

        dlg.edit = EditBox.create(srf.getView(), "")
        with dlg.edit
        {
            .dockStyle = .Bottom
            .margin    = metrics.dialog_Padding
            .style.addStyleSheetColors("edit_Bk $dlg_BtnBarBk")
            .style.addStyleSheetColors("edit_FocusBk $dlg_BtnBarBk")
            .setForm(.Round)
            .setFocus()
        }

        dlg.addButton("OK", Dialog.BtnOk, true)
        dlg.addButton("Cancel", Dialog.BtnCancel)
        dlg.sendResizeEvent()
        return dlg
    }

    // Creates the message box
    func createMultiLine(from: *Surface, heightEdit = 150)->*EditDlg
    {
        let dlg     = Wnd.create'EditDlg()
        let metrics = from.wnd.getThemeMetrics()
        let srf     = dlg.createSurface(from, 0, 0, 500, 180 + heightEdit, .Sizeable)
        srf.minSize.x = 500
        srf.minSize.y = 180 + heightEdit

        dlg.richEdit = RichEditCtrl.create(srf.getView(), {0, 0, 0, heightEdit})
        with dlg.richEdit
        {
            .anchorStyle  = .Height
            .dockStyle    = .Bottom
            .margin       = metrics.dialog_Padding
            .richEdFlags  |= .AutoLoseFocus
            .bkColorModel = "$dlg_BtnBarBk"
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

    // Set the text
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

    // Get the text
    mtd getText()->String
    {
        let edit = .edit
        if edit do
            return edit.text
        return (notnull .richEdit).getText()
    }

    // Associate a message above the editbox
    mtd setMessage(message: string, height: s32 = 40)
    {
        if !@isset(.label)
        {
            .label = Label.create((notnull .surface).getView(), message, {0, 0, 0, height})
            with me.label
            {
                .dockStyle         = .Center
                .vertAlignmentText = .Center
                .horzAlignmentText = .Center
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
            var pos = surface.position
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
