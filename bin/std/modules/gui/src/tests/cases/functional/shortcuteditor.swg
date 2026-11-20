#global if #command == Swag.CompilerCommand.Test
#global private

using Core

const Open    = "shortcut-editor.open"
const Close   = "shortcut-editor.close"
const Inspect = "shortcut-editor.inspect"
const Read    = "shortcut-editor.read"

func setupShortcutEditor(host: *Testing.HeadlessHost)->*Lens.View
{
    host.setup(1000, 750)
    host.root.hookOnEvent = func(_, evt)->bool
    {
        if evt is CommandStateEvent as state where state.kind == .Compute
        {
            switch state.id
            {
            case Open:    state.name = "Open document"
            case Close:   state.name = "Close document"
            case Inspect: state.name = "Show inspector"
            default:      return false
            }

            state.updatedFields.add(.Name)
            return true
        }

        return false
    }

    let lens = Lens.View.create(&host.root)
    lens.addCommands("Document", [Open, Close, Inspect])
    return lens
}

func runShortcutEditor(host: *Testing.HeadlessHost, lens: *Lens.View, drive: FrameCallback)
{
    host.app.sigFrame += drive
    defer host.app.sigFrame.clear()
    lens.showKeyboardShortcuts()
}

func editorList(editor: *Wnd)->*ListCtrl  => assume cast(*ListCtrl, unwrap editor.childById("gui.shortcuts.list"))
func editorFilter(editor: *Wnd)->*EditBox => assume cast(*EditBox, unwrap editor.childById("gui.shortcuts.filter"))
func editorChange(editor: *Wnd)->*Wnd     => unwrap editor.childById("gui.shortcuts.change")

func editorRow(editor: *Wnd, title: string)->*ListLine
{
    let list = editorList(editor)
    for index in list.lineCount()
    {
        let row = unwrap list.lineAt(index)
        if row.items[0]!.name.text == title do
            return row
    }

    Swag.panic(Format.toString("Missing shortcut row for %", title), #curlocation)
}

func editorAction(editor: *Wnd, title: string)->*Wnd
{
    for button in (unwrap editorChange(editor).parent).children where button.name.text == title do
        return button
    Swag.panic(Format.toString("Missing shortcut action %", title), #curlocation)
}

// The filter ignores case, matches a secondary binding, and keeps the active row when it still matches.
#test
{
    var checked: bool
    var host:    Testing.HeadlessHost
    let lens = setupShortcutEditor(&host)
    host.root.registerKeyShortcut(.Control, .F1, Open)
    host.root.registerKeyShortcut(.Shift, .F2, Open)
    host.root.registerKeyShortcut(.Control, .F3, Close)

    let drive: FrameCallback = func|host = &host, &checked|(app)
    {
        if checked do
            return
        checked = true
        let editor = app.modalSurfaces.back().view()
        let filter = editorFilter(editor)
        let list   = editorList(editor)
        let change = editorChange(editor)
        Swag.require(filter.hasFocus() and list.lineCount() == 3)

        // Type through the focused field so text input and the live filter share the same path.
        host.sendRune(.C, 'C')
        host.sendRune(.L, 'l')
        Swag.require(list.lineCount() == 1 and list.selectedLine() == editorRow(editor, "Close document"))
        filter.setText("DOCUMENT")
        Swag.require(list.lineCount() == 2 and list.selectedLine() == editorRow(editor, "Close document"))
        filter.setText("shift f2")
        Swag.require(list.lineCount() == 1 and list.selectedLine() == editorRow(editor, "Open document"))
        Swag.require(list.selectedLine()!.items[1]!.name.text == "Ctrl F1, Shift F2")

        filter.setText("nothing matches this")
        Swag.require(list.lineCount() == 0 and list.selectedLine() == null)
        Swag.require(not change.isEnabled())
        Swag.require(not editorAction(editor, strings().shortcuts_Clear).isEnabled())
        Swag.require(not editorAction(editor, strings().shortcuts_Reset).isEnabled())

        host.keyPress(.A, .Control)
        host.keyPress(.Back)
        Swag.require(filter.text().count == 0 and list.lineCount() == 3 and change.isEnabled())
        Swag.require(editorRow(editor, "Show inspector").items[1]!.name.text.count == 0)
        host.keyPress(.Escape)
        Swag.require(not app.endModal)
        host.keyPress(.Escape)
        Swag.require(app.endModal)
    }

    runShortcutEditor(&host, lens, drive)
    Swag.require(checked and host.app.shortcutOverrides.isEmpty())
}

// A stolen secondary default blocks an individual reset. Global reset recovers both commands.
#test
{
    var stage: u32
    var host:  Testing.HeadlessHost
    let lens = setupShortcutEditor(&host)
    host.root.registerKeyShortcut(.Control, .F1, Open)
    host.root.registerKeyShortcut(.Control, .F2, Open)
    host.root.registerKeyShortcut(.Control, .F3, Close)
    var draft: Array'ShortcutOverride
    setShortcutOverride(&draft, Open, .None, .None)
    setShortcutOverride(&draft, Close, .Control, .F2)
    expect host.app.updateShortcuts(draft)

    let drive: FrameCallback = func|host = &host, &stage|(app)
    {
        let editor = app.modalSurfaces.back().view()
        switch stage
        {
        case 0:
            let reset = editorAction(editor, strings().shortcuts_Reset)
            Swag.require(reset.isEnabled())
            stage = 1
            host.clickWnd(reset)
            Swag.require(stage == 2)
            Swag.require(reset.isEnabled())
            Swag.require(editorRow(editor, "Open document").items[1]!.name.text.count == 0)
            Swag.require(editorRow(editor, "Close document").items[1]!.name.text == "Ctrl F2")

            let dialog = assume cast(*Dialog, editor)
            host.clickWnd(unwrap dialog.leadingControl)
            Swag.require(not reset.isEnabled())
            Swag.require(editorRow(editor, "Open document").items[1]!.name.text == "Ctrl F1, Ctrl F2")
            Swag.require(editorRow(editor, "Close document").items[1]!.name.text == "Ctrl F3")
            Swag.require(host.root.keyShortcut(.Control, .F2) == Close)
            stage = 3
            Swag.require(host.clickModalButton(Dialog.BtnOk))

        case 1:
            if editor is MessageDlg as failure
            {
                let message = Format.toString(strings().shortcuts_ResetTaken, "Close document")
                Swag.require(failure.failure and failure.label.text() == message)
                stage = 2
                Swag.require(host.clickModalButton(Dialog.BtnOk))
            }
        }
    }

    runShortcutEditor(&host, lens, drive)
    Swag.require(stage == 3 and host.app.shortcutOverrides.isEmpty())
    Swag.require(host.root.keyShortcut(.Control, .F1) == Open)
    Swag.require(host.root.keyShortcut(.Control, .F2) == Open)
    Swag.require(host.root.keyShortcut(.Control, .F3) == Close)
}

// System capture ignores standalone modifiers, allows keyboard navigation, and discards a cancelled draft.
#test
{
    var stage: u32
    var host:  Testing.HeadlessHost
    let lens = setupShortcutEditor(&host)
    host.app.setGlobalHotKeysEnabled(false)
    expect host.app.registerUserHotKey(.Control, .F6, Open, &host.root)

    let drive: FrameCallback = func|host = &host, &stage|(app)
    {
        let editor = app.modalSurfaces.back().view()
        switch stage
        {
        case 0:
            stage = 1
            host.clickWnd(editorChange(editor))
            Swag.require(stage == 2)
            Swag.require(editorRow(editor, "Open document").items[1]!.name.text == "Ctrl F6")
            Swag.require(app.hotKeysDisabled)
            stage = 3
            Swag.require(host.clickModalButton(Dialog.BtnOk))

        case 1:
            stage = 2
            let dialog = assume cast(*Dialog, editor)
            let field  = unwrap dialog.keyboardEntry()
            let mods   = assume cast(*ComboBox, unwrap editor.childById("gui.shortcuts.modifiers"))
            let keys   = assume cast(*ComboBox, unwrap editor.childById("gui.shortcuts.key"))
            let assign = unwrap editor.childById(Dialog.BtnOk)
            Swag.require(field.hasFocus() and not assign.isEnabled())
            for key in [Input.Key.Shift, .LControl, .RMenu] do
                host.keyPress(key)
            Swag.require(field.hasFocus() and not app.endModal)
            host.keyPress(.Tab)
            Swag.require(mods.hasFocus() and not app.endModal)
            host.keyPress(.Tab)
            Swag.require(keys.hasFocus() and not app.endModal)
            host.keyPress(.Tab, .Shift)
            Swag.require(mods.hasFocus())

            mods.setSelectedIndex(7)
            Swag.require(not assign.isEnabled())
            keys.setSelectedIndex(1)
            Swag.require(assign.isEnabled())
            keys.setSelectedIndex(0)
            Swag.require(not assign.isEnabled())
            keys.setSelectedIndex(1)
            Swag.require(host.clickModalButton(Dialog.BtnCancel))
        }
    }

    runShortcutEditor(&host, lens, drive)
    Swag.require(stage == 3 and host.app.shortcutOverrides.isEmpty())
    Swag.require(host.app.hotKeyShortcut(.Control, .F6).id == Open)
    Swag.require(host.app.hotKeysDisabled)
}

// A failed state write preserves the live bindings and reopens the editor with its draft intact.
#test
{
    let path = Testing.tempFilePath("shortcut-editor-", ".scc")
    discard expect File.writeAllText(path, "existing file")
    defer discard catch File.delete(path)
    let fixedPath = Testing.tempFilePath("shortcut-editor-retry-", ".scc")
    defer discard catch File.delete(fixedPath)

    var stage: u32
    var host:  Testing.HeadlessHost
    let lens = setupShortcutEditor(&host)
    host.root.registerKeyShortcut(.Control, .F1, Open)
    host.app.setStatePath(Path.combine(path, "preferences.scc"))

    let drive: FrameCallback = func|host = &host, &stage, fixedPath = fixedPath.toString()|(app)
    {
        let editor = app.modalSurfaces.back().view()
        switch stage
        {
        case 0:
            stage = 1
            host.clickWnd(editorChange(editor))
            Swag.require(stage == 2)
            Swag.require(editorRow(editor, "Open document").items[1]!.name.text == "Ctrl F8")
            Swag.require(host.clickModalButton(Dialog.BtnOk))

        case 1:
            stage = 2
            host.keyPress(.F8, .Control)

        case 2:
            if editor is MessageDlg as failure
            {
                Swag.require(failure.failure and failure.label.text() == strings().shortcuts_Failed)
                Swag.require(app.shortcutOverrides.isEmpty())
                Swag.require(host.root.keyShortcut(.Control, .F1) == Open)
                Swag.require(host.root.keyShortcut(.Control, .F8) == null)
                app.setStatePath(fixedPath)
                stage = 3
                Swag.require(host.clickModalButton(Dialog.BtnOk))
            }

        case 3:
            if editor.childById("gui.shortcuts.filter")
            {
                Swag.require(editorRow(editor, "Open document").items[1]!.name.text == "Ctrl F8")
                Swag.require(host.root.keyShortcut(.Control, .F1) == Open)
                stage = 4
                Swag.require(host.clickModalButton(Dialog.BtnOk))
            }
        }
    }

    runShortcutEditor(&host, lens, drive)
    Swag.require(stage == 4 and File.exists(fixedPath))
    let original = expect File.readAllText(path)
    Swag.require(original == "existing file")
    Swag.require(host.root.keyShortcut(.Control, .F1) == null)
    Swag.require(host.root.keyShortcut(.Control, .F8) == Open)
}

// Cancelling capture leaves an unassigned command alone. A second attempt can give it its first binding.
#test
{
    var stage: u32
    var host:  Testing.HeadlessHost
    let lens = setupShortcutEditor(&host)

    let drive: FrameCallback = func|host = &host, &stage|(app)
    {
        let editor = app.modalSurfaces.back().view()
        switch stage
        {
        case 0:
            editorFilter(editor).setText("inspector")
            let change = editorChange(editor)
            stage = 1
            host.clickWnd(change)
            Swag.require(stage == 2)
            Swag.require(not app.hotKeysDisabled)
            Swag.require(editorRow(editor, "Show inspector").items[1]!.name.text.count == 0)
            stage = 3
            host.clickWnd(change)
            Swag.require(stage == 4)
            Swag.require(editorRow(editor, "Show inspector").items[1]!.name.text == "Ctrl F8")
            Swag.require(host.root.keyShortcut(.Control, .F8) == null)
            stage = 5
            Swag.require(host.clickModalButton(Dialog.BtnOk))

        case 1:
            Swag.require(app.hotKeysDisabled)
            stage = 2
            Swag.require(host.clickModalButton(Dialog.BtnCancel))

        case 3:
            stage = 4
            host.keyPress(.F8, .Control)
        }
    }

    runShortcutEditor(&host, lens, drive)
    Swag.require(stage == 5 and host.root.keyShortcut(.Control, .F8) == Inspect)
}

// A collision can name two owners. No leaves both bindings intact and Yes clears both.
#test
{
    var host: Testing.HeadlessHost
    let lens = setupShortcutEditor(&host)
    host.root.registerKeyShortcut(.Control, .F1, Open)
    host.root.registerKeyShortcut(.Control, .F2, Close)
    host.root.registerKeyShortcut(.Control, .F3, Close)
    lens.addSource(.Action, func(results)
    {
        with let entry = results.addSection("Page").addEntry("Read page")
        {
            .bindId     = Read
            .defaultKey = {modifiers: .Control, key: .F3}
            .run        = func() {}
        }
    })

    for replace in [false, true]
    {
        var stage: u32
        let drive: FrameCallback = func|host = &host, &stage, replace|(app)
        {
            let editor = app.modalSurfaces.back().view()
            switch stage
            {
            case 0:
                stage = 1
                host.clickWnd(editorChange(editor))
                Swag.require(stage == 3)
                let open  = editorRow(editor, "Open document")
                let close = editorRow(editor, "Close document")
                let read  = editorRow(editor, "Read page")
                Swag.require(open.items[1]!.name.text == (replace ? "Ctrl F3" : "Ctrl F1"))
                Swag.require(close.items[1]!.name.text == (replace ? "" : "Ctrl F2, Ctrl F3"))
                Swag.require(read.items[1]!.name.text == (replace ? "" : "Ctrl F3"))
                stage = 4
                Swag.require(host.clickModalButton(Dialog.BtnOk))

            case 1:
                stage = 2
                host.keyPress(.F3, .Control)

            case 2:
                if editor is MessageDlg as prompt
                {
                    let message = Format.toString(strings().shortcuts_Taken, "Ctrl F3", "Close document, Read page")
                    Swag.require(prompt.title.text == strings().shortcuts_Replace)
                    Swag.require(Utf8.contains(prompt.label.text(), message.toString()))
                    stage = 3
                    Swag.require(host.clickModalButton(replace ? Dialog.BtnYes : Dialog.BtnNo))
                }
            }
        }

        runShortcutEditor(&host, lens, drive)
        Swag.require(stage == 4)
        Swag.require(host.root.keyShortcut(.Control, .F3) == (replace ? Open : Close))
        Swag.require(host.root.keyShortcutName(Read, "Ctrl F3") == (replace ? "" : "Ctrl F3"))
        if not replace do
            Swag.require(host.app.shortcutOverrides.isEmpty())
    }
}
