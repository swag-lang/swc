using Core, Pixel

// Prompts for either a single line or a block of rich text.
public struct EditDlg
{
    public using dialog: Dialog     // Embedded dialog state.

    public readonly
    {
        late label: *Label             // Optional explanatory message.
        edit:       *EditBox?          // Single-line editor, when created in single-line mode.
        richEdit:   *RichEditCtrl?     // Rich editor, when created in multi-line mode.
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
        let dlg = Wnd.create'EditDlg()
        let srf = dlg.createSurface(from, 0, 0, 450, 210)
        srf.setTitle(options.title)

        dlg.edit = EditBox.create(dlg.createContentView(), "")
        with dlg.edit
        {
            .dockStyle = .Bottom
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
        let dlg = Wnd.create'EditDlg()
        let srf = dlg.createSurface(from, 0, 0, 500, 180 + options.editorHeight, .Resizable)
        srf.setTitle(options.title)
        srf.minSize.x = 500

        dlg.richEdit = RichEditCtrl.create(dlg.createContentView(), {0, 0, 0, options.editorHeight})
        with dlg.richEdit
        {
            .anchorStyle = .Height
            .dockStyle   = .Bottom
            .setFlags(.flags | .AutoLoseFocus)
            .setForm(.Edit)
            .setFrameForm(.Square)
            .setFrameFlags(.FocusBorder)
            .setFocus()
        }

        dlg.addButton(strings().dlg_Ok, Dialog.BtnOk, true)
        dlg.addButton(strings().dlg_Cancel, Dialog.BtnCancel)
        dlg.sendResizeEvent()

        var appliedOptions = options
        if !appliedOptions.message.count do
            appliedOptions.message = strings().dlg_MultiLineHint
        dlg.applyOptions(appliedOptions)
        return dlg
    }

    // Applies the shared creation options once the editor exists, then centers the
    // surface: the message can grow the surface, so centering must come last.
    private mtd applyOptions(options: EditDlgOptions)
    {
        if options.message.count
        {
            // A one-line prompt needs one line of explanation, not the taller band that keeps a
            // rich editor's keyboard hint easy to scan above a large text area.
            let messageHeight = .edit ? cast(s32) Math.ceil(.font().regular!.height) : 40
            .setMessage(options.message, messageHeight)
            if .edit do
                .label.margin.w = .themeMetrics().dialog_BtnPadding
        }

        .setText(options.text)
        if options.selectAll
        {
            let edit = .edit
            if edit do
                edit.selectAll()
            else do
                .richEdit!.selectAll()
        }

        .fitContent()
        let surface = .surface!
        surface.center(.parentSurface!)
    }

    // Fits the shared dialog layers around the editor and its optional explanation.
    private mtd fitContent()
    {
        .applyLayout()

        let edit          = .edit
        var contentHeight = edit ? edit.position.height : .richEdit!.position.height
        if .label != null
        {
            // The explanation is as tall as its own wording at the width it has, floored by the
            // band the caller asked to keep for it. Read back from the layout instead, the band
            // was whatever the authored shell had left over, so a message needing a second line
            // was cut in half by a box that had never measured it.
            let wording = .label.itf.measureContent({.label.position.width, 0}).y
            contentHeight += Math.max(wording, .label.preferredSize.y) + .label.margin.w
        }

        // The rich editor keeps its authored height while the surface is fitted around it.
        let richEdit = .richEdit
        if richEdit do
            richEdit.anchorStyle = .None
        .fitHeightToContent(contentHeight)
        if richEdit do
            richEdit.anchorStyle = .Height

        // A resizable editor may grow, but it must not shrink below its fitted content.
        if richEdit
        {
            let surface = .surface!
            surface.minSize.y = surface.position.height / surface.dpiScale
        }
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
    //
    // The box refits around the wording, so an explanation running onto a second line is given
    // that line instead of losing it. `height` is the band kept for a message shorter than that,
    // not a height the message is held to.
    mtd setMessage(message: string, height: s32 = 40)
    {
        Debug.assert(height > 0, "message height must be positive")
        if !(.label != null)
        {
            Swag.assert(.surface != null)
            .label = Label.create(.contentView!, message, {0, 0, 0, height}, flags: .WordWrap | .SecondaryText)
            with me.label
            {
                .dockStyle = .Center
                .margin.w  = .themeMetrics().dialog_BtnPadding * 2
                .setTextAlignment(.Left, .Center)
            }
        }
        else
        {
            .label.preferredSize.y = cast(f32) height
            .label.setText(message)
        }

        .fitContent()
        .surface!.center(.parentSurface!)
    }
}
