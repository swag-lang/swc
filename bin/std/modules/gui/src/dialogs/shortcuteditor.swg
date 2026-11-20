using Core

internal struct ShortcutCommand
{
    id:       String
    title:    String
    system:   bool
    source:   bool
    defaults: Array'KeyShortcut
}

internal func addShortcutCommand(commands: *Array'ShortcutCommand, owner: *Wnd, id: WndId, chord: const *KeyShortcut?, system = false)
{
    var command: *ShortcutCommand?
    for &existing in commands[] where existing.id == id
    {
        command = existing
        break
    }
    if not command
    {
        let state = owner.sendComputeCommandStateEvent(id)
        command = commands.emplaceInitAddress()
        command.id = id
        command.title = state.name.isEmpty() ? String.from(id) : state.name
    }
    if system and not command.system
    {
        command.system = true
        command.defaults.clear()
    }
    if let binding = chord
    {
        if command.system == system and not hasShortcutChord(command.defaults.toSlice(), binding[]) do
            command.defaults.add(binding[])
    }
}

internal func collectShortcutCommands(owner: *Wnd, commands: *Array'ShortcutCommand)
{
    for &chord in owner.keyShortcuts do
        addShortcutCommand(commands, owner, chord.id, chord)
    for child in owner.children do
        collectShortcutCommands(child, commands)
}

private struct ShortcutEditor
{
    using wnd: Wnd
    commands:  const [..] ShortcutCommand = []
    late draft: *Array'ShortcutOverride
    late list: *ListCtrl
    late filter: *EditBox
    late change: *PushButton
    late clear:  *PushButton
    late reset:  *PushButton
}

impl ShortcutEditor
{
    func create(dialog: *Dialog, commands: const [..] ShortcutCommand, draft: *Array'ShortcutOverride)->*ShortcutEditor
    {
        let result      = Wnd.create'ShortcutEditor(dialog.createContentView())
        result.dockStyle = .Center
        result.commands  = commands
        result.draft     = draft

        let text    = strings()
        let metrics = result.themeMetrics()
        let height  = metrics.control_DialogHeight
        let gap     = metrics.dialog_BtnPadding
        with result.filter = EditBox.create(result, "", {0, 0, 0, height}, "gui.shortcuts.filter")
        {
            .dockStyle = .Top
            .margin.w = gap * 2
            .setPlaceholder(text.shortcuts_Search)
            .sigTextChanged += func|result|(_) { result.fill() }
        }

        with let actions = StackLayoutCtrl.create(result, .Left, {0, 0, 0, height})
        {
            .dockStyle = .Bottom
            .spacing   = gap
            .margin.y  = gap * 2
            result.change = PushButton.create(actions, text.shortcuts_Change, id: "gui.shortcuts.change")
            result.clear  = PushButton.create(actions, text.shortcuts_Clear)
            result.reset  = PushButton.create(actions, text.shortcuts_Reset)
        }
        for button in [result.change, result.clear, result.reset] do
            button.fitWidthToLabel(metrics.btnPush_Width)

        result.change.sigPressed += func|result|(_) { result.changeSelected() }
        result.clear.sigPressed  += func|result|(_) { result.clearSelected() }
        result.reset.sigPressed  += func|result|(_) { result.resetSelected() }

        let all = PushButton.create(dialog, text.shortcuts_ResetAll, {0, 0, 0, height}, form: .Flat)
        all.fitWidthToLabel(metrics.btnPush_Width)
        all.sigPressed += func|result|(_)
        {
            result.draft.clear()
            result.fill()
        }
        dialog.setLeadingControl(all)

        with result.list = ListCtrl.createMultiColumns(result, id: "gui.shortcuts.list")
        {
            .dockStyle = .Center
            .addColumn(text.shortcuts_Command, MessageDlg.MinMessageWidth * 0.68)
            .addColumn(text.shortcuts_Binding, MessageDlg.MinMessageWidth * 0.40)
            .addColumn(text.shortcuts_Scope, MessageDlg.MinMessageWidth * 0.26)
            .sigSelectionChanged += func|result|(_) { result.updateActions() }
        }
        result.fill()
        return result
    }

    mtd selected()->const *ShortcutCommand?
    {
        let row = .list.selectedLine()
        return row ? cast(const *ShortcutCommand?, row.userData0) : null
    }

    mtd updateActions()
    {
        let selected = .selected()
        .change.enable(selected != null)
        .clear.enable(selected != null)
        .reset.enable(selected != null and shortcutOverride(.draft.toSlice(), selected.id) != null)
    }

    mtd bindingText(command: const *ShortcutCommand)->String
    {
        if let custom = shortcutOverride(.draft.toSlice(), command.id)
        {
            if custom.key != .None do
                return Input.formatKeyShortcut(custom.modifiers, custom.key)
            return {}
        }

        var result: #returntype
        for chord in command.defaults
        {
            if not result.isEmpty() do
                result += ", "
            result += Input.formatKeyShortcut(chord.modifiers, chord.key)
        }
        return result
    }

    mtd fill()
    {
        let selected = .selected()
        let query    = String.toLower(.filter.text())
        let text     = strings()
        var index: u32
        var restore  = Swag.U32.Max
        .list.clear()
        for &command in .commands
        {
            let chord = .bindingText(command)
            var reach = text.shortcuts_Local
            if command.system do
                reach = text.shortcuts_Global
            elif command.source do
                reach = text.shortcuts_Document
            if not query.isEmpty() and not Utf8.contains(command.title.toLower().toString(), query.toString()) and
               not Utf8.contains(chord.toLower().toString(), query.toString()) do
                continue
            let row       = .list.createLine(command.title)
            row.userData0 = cast #unconst (*void, command)
            row.setItem(1, chord)
            row.setItem(2, reach)
            if command == selected do
                restore = index
            index += 1
        }
        if index do
            .list.selectLine(restore != Swag.U32.Max ? restore : 0)
        .list.invalidate()
        .updateActions()
    }

    mtd changeSelected()
    {
        let selected = .selected()
        if not selected do
            return
        let surface = unwrap .surface
        let chord   = captureShortcut(surface, selected.system)
        if chord.key == .None do
            return

        let text = strings()
        var conflicts: Array'(const *ShortcutCommand)
        var names: String
        for &command in .commands where command.id != selected.id
        {
            let custom = shortcutOverride(.draft.toSlice(), command.id)
            let taken  = custom ? custom.key == chord.key and custom.modifiers == chord.modifiers :
                                  hasShortcutChord(command.defaults.toSlice(), chord)
            if taken
            {
                conflicts.add(command)
                if not names.isEmpty() do
                    names += ", "
                names += command.title
            }
        }
        if not conflicts.isEmpty()
        {
            let message = Format.toString(text.shortcuts_Taken, Input.formatKeyShortcut(chord.modifiers, chord.key), names)
            if MessageDlg.confirm(surface, message, options: {title: text.shortcuts_Replace}) != Dialog.BtnYes do
                return
            for command in conflicts do
                setShortcutOverride(.draft, command.id, .None, .None, source: command.source)
        }
        setShortcutOverride(.draft, selected.id, chord.modifiers, chord.key, source: selected.source)
        .fill()
    }

    mtd clearSelected()
    {
        if let command = .selected()
        {
            setShortcutOverride(.draft, command.id, .None, .None, source: command.source)
            .fill()
        }
    }

    mtd resetSelected()
    {
        if let selected = .selected()
        {
            for chord in selected.defaults
            {
                for &other in .commands where other.id != selected.id
                {
                    if let custom = shortcutOverride(.draft.toSlice(), other.id)
                    {
                        if custom.key == chord.key and custom.modifiers == chord.modifiers
                        {
                            MessageDlg.error(unwrap .surface, Format.toString(strings().shortcuts_ResetTaken, other.title))
                            return
                        }
                    }
                }
            }
            resetShortcutOverride(.draft, selected.id)
            .fill()
        }
    }
}

private func canBindShortcut(key: Input.Key)->bool
{
    switch key
    {
    case .None, .Shift, .LShift, .RShift, .Control, .LControl, .RControl, .MenuCtrl, .LMenu, .RMenu, .LWin, .RWin,
         .LButton, .RButton, .MButton, .XButton1, .XButton2:
        return false
    default:
        return true
    }
}

// The desktop may consume a chord before the window sees it. System shortcuts also offer a picker.
private func addSystemShortcutPicker(dialog: *Dialog, body: *Wnd, choices: *Array'Input.Key, result: *KeyShortcut)->f32
{
    let text    = strings()
    let metrics = body.themeMetrics()
    let height  = metrics.comboBox_Height
    let gap     = metrics.dialog_BtnPadding * 2
    let row     = StackLayoutCtrl.create(body, .Left, {0, 0, 0, height})
    row.dockStyle = .Top
    row.margin.y  = gap
    row.spacing   = gap
    let width     = MessageDlg.MinMessageWidth * 0.40
    let mods      = ComboBox.create(row, {0, 0, width, height}, "gui.shortcuts.modifiers")
    let keys      = ComboBox.create(row, {0, 0, width, height}, "gui.shortcuts.key")
    let apply     = dialog.addButton(text.shortcuts_Assign, Dialog.BtnOk, true)
    apply.enable(false)

    let modifierNames = [text.shortcuts_NoModifier, "Shift", "Ctrl", "Ctrl Shift", "Alt", "Alt Shift", "Alt Ctrl", "Alt Ctrl Shift"]
    let modifiers = [Input.KeyModifiers.None, .Shift, .Control, .CtrlShift,
                     .Alt, Input.KeyModifiers.Alt | .Shift, .CtrlAlt, Input.KeyModifiers.CtrlAlt | .Shift]
    for name in modifierNames do
        mods.addItem(name)
    mods.setSelectedIndex(0, notify: false)
    mods.sigChanged += func|result, modifiers|(_, index) { result.modifiers = modifiers[index] }

    choices.add(.None)
    keys.addItem(text.shortcuts_ChooseKey)
    for key in Input.Key where canBindShortcut(key) and Input.Keyboard.keyToVirtualKey(key) != 0
    {
        choices.add(key)
        keys.addItem(Input.formatKeyShortcut(.None, key))
    }
    keys.setSelectedIndex(0, notify: false)
    keys.sigChanged += func|result, apply, choices|(_, index)
    {
        result.key = choices[][index]
        apply.enable(result.key != .None)
    }
    return height + gap
}

private func captureShortcut(surface: *Surface, system: bool)->KeyShortcut
{
    let app = surface.app
    let enabled = not app.hotKeysDisabled
    app.setGlobalHotKeysEnabled(false)
    defer app.setGlobalHotKeysEnabled(enabled)

    let text    = strings()
    let metrics = surface.wnd.themeMetrics()
    let dialog  = Dialog.create(surface, cast(s32, MessageDlg.MinMessageWidth), 0, title: text.shortcuts_Change)
    dialog.addButton(text.dlg_Cancel, Dialog.BtnCancel)
    var result: #returntype
    var choices: Array'Input.Key
    let body    = dialog.createContentView()
    var height  = metrics.control_DialogHeight
    let field   = EditBox.create(body, "", {0, 0, 0, height}, flags: .ReadOnly)
    field.dockStyle = .Top
    field.setPlaceholder(text.shortcuts_Press)
    field.hookOnEvent = func|dialog, system, &result|(_, event)->bool
    {
        if event is KeyEvent as key where key.kind == .Pressed
        {
            if system and key.key == .Tab and (key.modifiers == .None or key.modifiers == .Shift) do
                return false
            if canBindShortcut(key.key)
            {
                result.key       = key.key
                result.modifiers = key.modifiers
                discard dialog.closeWithResult(Dialog.BtnOk)
            }
            return true
        }
        return false
    }
    if system do
        height += addSystemShortcutPicker(dialog, body, &choices, &result)
    dialog.fitHeightToContent(height)
    if dialog.doModal() != Dialog.BtnOk do
        return {}
    return result
}

internal func editKeyboardShortcuts(surface: *Surface, commands: const [..] ShortcutCommand)
{
    let app  = surface.app
    let text = strings()
    var draft = app.shortcutOverrides
    while true
    {
        let width  = MessageDlg.MinMessageWidth + MessageDlg.MaxMessageWidth * 0.5
        let height = MessageDlg.MaxMessageWidth
        let dialog = Dialog.create(surface, cast(s32, width), cast(s32, height), title: text.shortcuts_Title, flags: .Resizable)
        dialog.addButton(text.dlg_Cancel, Dialog.BtnCancel)
        dialog.addButton(text.shortcuts_Save, Dialog.BtnOk, true)
        discard ShortcutEditor.create(dialog, commands, &draft)
        if dialog.doModal() != Dialog.BtnOk do
            return
        catch app.updateShortcuts(draft)
        {
            MessageDlg.error(surface, text.shortcuts_Failed, Swag.err)
            continue
        }
        return
    }
}
