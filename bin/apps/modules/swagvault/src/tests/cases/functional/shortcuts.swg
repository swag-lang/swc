#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// Reassign Open File's chord to New Vault through the options page.
func editVaultShortcuts(host: *Testing.HeadlessHost, window: *MainWindow, save: bool)
{
    var stage: u32
    host.app.sigFrame += func|host, &stage, save|(app)
    {
        let root = app.surfaces.back().view()
        switch stage
        {
        case 0:
            let filter = assume cast(*EditBox, unwrap root.childById("gui.shortcuts.filter"))
            let list   = assume cast(*ListCtrl, unwrap root.childById("gui.shortcuts.list"))
            filter.setText(appStrings().ui_NewVault)
            Swag.require(list.lineCount() == 1)
            let row = unwrap list.selectedLine()
            Swag.require(row.items[1]!.name.text == Input.formatKeyShortcut(.Control, .N))
            stage = 1
            host.clickWnd(unwrap root.childById("gui.shortcuts.change"))
            Swag.require(stage == 3)
            stage = 4
            Swag.require(host.clickModalButton(save ? Dialog.BtnOk : Dialog.BtnCancel))

        case 1:
            stage = 2
            host.keyPress(.O, .Control)

        case 2:
            if root is MessageDlg as confirm
            {
                let message = Format.toString(Gui.strings().shortcuts_Taken,
                                              Input.formatKeyShortcut(.Control, .O),
                                              appStrings().ui_OpenFile)
                Swag.require(confirm.title.text == Gui.strings().shortcuts_Replace)
                Swag.require(Utf8.contains(confirm.label.text(), message.toString()))
                stage = 3
                Swag.require(host.clickModalButton(Dialog.BtnYes))
            }
        }
    }

    host.clickWnd(window.optionsPage.shortcuts)
    host.app.sigFrame.clear()
    Swag.require(stage == 4)
}

// Cancel discards a confirmed transfer. Saving applies it, survives a new window,
// and Restore All Defaults recovers both commands' original bindings.
#test
{
    let path = Testing.tempFilePath("vault-shortcuts-", ".scc")
    defer discard catch File.delete(path)

    scope
    {
        var host: Testing.HeadlessHost
        let window = testSetupMainWindow(&host, width: 1024, height: 800)
        host.app.setStatePath(path)
        host.clickWnd(window.optionsButton)
        Swag.require(window.page == .Options)

        editVaultShortcuts(&host, window, save: false)
        Swag.require(window.keyShortcut(.Control, .N) == VaultCommands.NewVault)
        Swag.require(window.keyShortcut(.Control, .O) == VaultCommands.OpenFile)
        Swag.require(not File.exists(path))

        editVaultShortcuts(&host, window, save: true)
        Swag.require(window.keyShortcut(.Control, .N) == null)
        Swag.require(window.keyShortcut(.Control, .O) == VaultCommands.NewVault)
        Swag.require(File.exists(path))
    }

    var reset: bool
    var host:  Testing.HeadlessHost
    let window = testSetupMainWindow(&host, width: 1024, height: 800)
    host.app.setStatePath(path)
    expect host.app.loadState()
    window.showPage(.List, animate: false)
    window.setFocus()
    host.keyPress(.O, .Control)
    Swag.require(window.page == .Create)
    Swag.require(window.keyShortcutName(VaultCommands.OpenFile).isEmpty())

    window.showPage(.List, animate: false)
    host.clickWnd(window.optionsButton)
    Swag.require(window.page == .Options)
    host.app.sigFrame += func|host = &host, &reset|(app)
    {
        if reset do
            return
        let root = app.surfaces.back().view()
        if root is Dialog as editor
        {
            let defaults = unwrap editor.leadingControl
            Swag.require(defaults.name.text == Gui.strings().shortcuts_ResetAll)
            reset = true
            host.clickWnd(defaults)
            Swag.require(host.clickModalButton(Dialog.BtnOk))
        }
    }

    host.clickWnd(window.optionsPage.shortcuts)
    host.app.sigFrame.clear()
    Swag.require(reset)
    Swag.require(window.keyShortcut(.Control, .N) == VaultCommands.NewVault)
    Swag.require(window.keyShortcut(.Control, .O) == VaultCommands.OpenFile)
}

// A single command can be removed and restored independently of the other default shortcuts.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host, width: 1024, height: 800)
    window.lens.open(Gui.strings().shortcuts_Title)
    Swag.require(lensHasEntry(window, Gui.strings().shortcuts_Open))
    window.lens.close()

    host.clickWnd(window.optionsButton)
    Swag.require(window.page == .Options)
    for remove in [true, false]
    {
        var edited: bool
        host.app.sigFrame += func|host = &host, &edited, remove|(app)
        {
            if edited do
                return
            let root    = app.surfaces.back().view()
            let filter  = assume cast(*EditBox, unwrap root.childById("gui.shortcuts.filter"))
            let change  = unwrap root.childById("gui.shortcuts.change")
            let actions = unwrap change.parent
            filter.setText(appStrings().ui_NewVault)
            let text   = Gui.strings()
            let action = remove ? text.shortcuts_Clear : text.shortcuts_Reset
            for button in actions.children where button.name.text == action
            {
                edited = true
                Swag.require(button.isEnabled())
                host.clickWnd(button)
                Swag.require(host.clickModalButton(Dialog.BtnOk))
                return
            }

            Swag.require(false, action)
        }

        host.clickWnd(window.optionsPage.shortcuts)
        host.app.sigFrame.clear()
        Swag.require(edited)
        Swag.require(window.keyShortcut(.Control, .N) == (remove ? null : VaultCommands.NewVault))
        Swag.require(window.keyShortcut(.Control, .O) == VaultCommands.OpenFile)
    }
}
