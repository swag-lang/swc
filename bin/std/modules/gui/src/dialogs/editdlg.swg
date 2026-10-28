using Core, Pixel

// Prompts for either a single line or a block of rich text.
//
// The box is the composition of [[Gui.Dialog]]: its title names the command it carries out, the
// editor follows, and a help line in the faint ink stands under the editor when the prompt needs
// one. Cancel and the primary action end the body.
public struct EditDlg
{
    public using dialog: Dialog     // Embedded dialog state.

    public readonly
    {
        late label: *Label             // Optional help line under the editor.
        edit:       *EditBox?          // Single-line editor, when created in single-line mode.
        richEdit:   *RichEditCtrl?     // Rich editor, when created in multi-line mode.
    }
}

// Configures the title, help line, actions and initial contents of an [[Gui.EditDlg]].
public struct EditDlgOptions
{
    public
    {
        title:             string = ""      // Title of the box: the label of the command it carries out.
        message:           string = ""      // Optional help line shown under the editor.
        text:              string = ""      // Initial editor contents.
        confirmButtonText: string = ""      // Caption of the primary action, or empty for the localized OK.
        selectAll = true     // Whether the initial contents start selected.
        editorHeight:      s32    = 150     // Editor height, used by the multi-line form.
    }
}

public impl EditDlg
{
    // Creates a single-line text prompt, centered on its owner.
    //
    // Run it with [[Gui.Dialog.doModal]]; when the result is `Dialog.BtnOk`, read the answer with
    // [[Gui.EditDlg.text]].
    #[Swag.Discardable]
    func createSingleLine(from: *Surface, options: EditDlgOptions = {})->*EditDlg
    {
        Swag.assert(from != null)
        let dlg = Wnd.create'EditDlg()
        discard dlg.createSurface(from, 0, 0, cast(s32, MessageDlg.MinMessageWidth), 210)
        dlg.setTitle(options.title)

        with dlg.edit = EditBox.create(dlg.createContentView(), "")
        {
            .dockStyle       = .Top
            .position.height = dlg.themeMetrics().control_DialogHeight
            .setFocus()
        }

        dlg.addActions(options)
        dlg.sendResizeEvent()
        dlg.applyOptions(options)
        return dlg
    }

    // Creates a resizable multi-line text prompt, centered on its owner.
    #[Swag.Discardable]
    func createMultiLine(from: *Surface, options: EditDlgOptions = {})->*EditDlg
    {
        Swag.assert(from != null)
        Swag.assert(options.editorHeight > 0, "editor height must be positive")
        let dlg = Wnd.create'EditDlg()
        discard dlg.createSurface(from, 0, 0, 512, 180 + options.editorHeight, .Resizable)
        dlg.setTitle(options.title)
        dlg.setMinSize(MessageDlg.MinMessageWidth, 0)

        with dlg.richEdit = RichEditCtrl.create(dlg.createContentView(), Math.Rectangle{0, 0, 0, options.editorHeight})
        {
            .anchorStyle = .Height
            .dockStyle   = .Top
            .setFlags(.flags | .AutoLoseFocus)
            .setForm(.Edit)
            .setFrameForm(.Square)
            .setFrameFlags(.FocusBorder)
            .setFocus()
        }

        dlg.addActions(options)
        dlg.sendResizeEvent()

        var appliedOptions = options
        if not appliedOptions.message.count do
            appliedOptions.message = strings().dlg_MultiLineHint
        dlg.applyOptions(appliedOptions)
        return dlg
    }

    // Adds the primary action and Cancel, which Escape presses.
    private mtd addActions(options: EditDlgOptions)
    {
        .addButton(options.confirmButtonText.count ? options.confirmButtonText : strings().dlg_Ok, Dialog.BtnOk, true)
        .addButton(strings().dlg_Cancel, Dialog.BtnCancel)
    }

    // Applies the shared creation options once the editor exists, then centers the
    // surface: the message can grow the surface, so centering must come last.
    private mtd applyOptions(options: EditDlgOptions)
    {
        if options.message.count do
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

        .fitContent()
        .surface!.center(unwrap .parentSurface)
    }

    // Fits the shared dialog layers around the editor and its optional help line.
    private mtd fitContent()
    {
        .applyLayout()

        let edit = .edit
        var contentHeight = edit ? edit.position.height : .richEdit!.position.height
        if .label != null
        {
            // The help line is as tall as its own wording at the width it has. Read back from the
            // layout instead, it was whatever the authored shell had left over, so a help line
            // needing a second line was cut in half by a box that had never measured it.
            let wording = Math.ceil(.label.itf.measureContent(Math.Point{.label.position.width, 0}).y)
            .label.position.height = wording
            contentHeight += wording + .label.margin.y
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
            let surface = unwrap .surface
            surface.minSize.y = surface.position.height / surface.dpiScale
        }
    }

    // Replaces the editor contents.
    mtd setText(text: string)
    {
        let edit = .edit
        if edit do
            edit.setText(text)
        else do
            .richEdit!.setText(text)
    }

    // Returns a copy of the editor contents.
    mtd text()->String
    {
        let edit = .edit
        if edit do
            return edit.text()
        return .richEdit!.text()
    }

    // Creates or updates the help line under the editor.
    //
    // The box refits around the wording, so a help line running onto a second line is given that
    // line instead of losing it.
    mtd setMessage(message: string)
    {
        if .label == null
        {
            Swag.assert(.surface != null)
            with me.label = Label.create(unwrap .contentView, message, flags: .WordWrap)
            {
                .dockStyle = .Top
                .margin.y  = me.themeMetrics().dialog_BtnPadding * 2
                .style.addStyleSheetColors("label_Text $faintText")
                .setTextAlignment(.Left, .Top)
            }
        }
        else
        {
            .label.setText(message)
        }

        .fitContent()
        .surface!.center(unwrap .parentSurface)
    }
}
