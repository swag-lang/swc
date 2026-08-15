using Core, Pixel, Gui

// Host-owned text view available for every file without loading a plugin.
struct BasicTextView
{
    using wnd: Wnd

    #[Swag.Late]
    {
        commands:   *Wnd
        editor:     *RichEditCtrl
        wrapButton: *PushButton
    }

    wrapping = true
}

impl BasicTextView
{
    mtd updateWrap()
    {
        .editor.setFlags(.ReadOnly | (.wrapping ? RichEditFlags.WordWrap : .None))
        .wrapButton.setText(.wrapping ? "Wrap on" : "Wrap off")
    }

    mtd toggleWrap()
    {
        .wrapping = !.wrapping
        .updateWrap()
    }
}

impl IWnd for BasicTextView
{
    mtd impl onKeyEvent(evt: *KeyEvent)
    {
        if evt.kind == .Pressed and evt.key == .W and evt.modifiers.has(.Control) do
            .toggleWrap()
        else do
            evt.accepted = false
    }
}

impl BasicTextView
{
    func create(contentParent, commandParent: *Wnd, fileName: string)->*BasicTextView
    {
        let result = Wnd.create'BasicTextView(contentParent, "sViewer.basicText")
        result.backgroundStyle = .View

        result.commands = Wnd.create'Wnd(commandParent, {0, 0, 88, 32})
        result.commands.backgroundStyle = .Window

        with result.wrapButton = PushButton.create(result.commands, "Wrap on", {0, 0, 84, 32})
        {
            .dockStyle = .Left
            .sigPressed += func|view = result|(button)
            {
                discard button
                view.toggleWrap()
            }
        }

        result.editor             = RichEditCtrl.create(result)
        result.editor.dockStyle   = .Center
        result.editor.marginLeft  = 12
        result.editor.marginRight = 12
        result.editor.style.setFont(result.theme().createDefaultFontFS(result.themeMetrics().defaultFixedFontSize), .Regular)

        let source = catch File.readAllText(fileName) as readError
        let valid = readError == null and Utf8.isValid(source.toSlice()) and Utf8.indexOf(source.toSlice(), 0'rune) == Swag.U64.Max
        result.editor.setText(valid ? source.toString() : "This file does not contain supported UTF-8 text. Select Hexadecimal to inspect its bytes.")
        result.updateWrap()
        result.applyLayout()
        result.setInitialFocus(result.editor)
        return result
    }
}
