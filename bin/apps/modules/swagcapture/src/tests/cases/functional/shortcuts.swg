#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

enum CaptureShortcutStep
{
    OpenOptions
    EditOccupied
    PickOccupied
    RejectOccupied
    EditAvailable
    PickAvailable
    CloseOptions
    Done
}

func pickCaptureShortcut(host: *Testing.HeadlessHost, root: *Wnd, key: Input.Key)
{
    let mods = assume cast(*ComboBox, unwrap root.childById("gui.shortcuts.modifiers"))
    let keys = assume cast(*ComboBox, unwrap root.childById("gui.shortcuts.key"))
    mods.setSelectedIndex(2)
    let name = Input.formatKeyShortcut(.None, key)
    for item, index in keys.items where item!.name.text == name
    {
        keys.setSelectedIndex(cast(u32, index))
        break
    }
    Swag.require(keys.selectedItem()!.name.text == name)
    Swag.require(host.clickModalButton(Dialog.BtnOk))
}

// The system picker reports an occupied chord, preserves Print Screen, and offers the draft again.
// A corrected binding then replaces Print Screen in Capture's system registry.
#test
{
    var step: CaptureShortcutStep
    var host: Testing.HeadlessHost
    let main = testSetupEditorSurface(&host, dark: false, text: false)
    defer
    {
        main.libWnd.requestClose()
        host.shutdown()
        g_Main = null
    }

    // The headless host keeps its registrations local. Reserve a chord through the unmanaged
    // API to drive the same error path without taking a hotkey from the desktop.
    expect host.app.registerHotKey(.Control, .F9, "test.capture.occupied", main)
    let original = Input.formatKeyShortcut(.None, .PrintScreen)
    Swag.require(main.sendComputeCommandStateEvent(ActionCapture.Area).shortcut == original)
    host.app.sigFrame += func|host = &host, main, &step|(app)
    {
        let root = app.surfaces.back().view()
        switch step
        {
        case .OpenOptions:
            if root is Dialog as options
            {
                Swag.require(options.title.text == appStrings().dlg_TitleOptions)
                step = .EditOccupied
                host.clickWnd(unwrap options.leadingControl)
                Swag.require(step == .CloseOptions)
                step = .Done
                Swag.require(host.clickModalButton(Dialog.BtnCancel))
            }
        case .EditOccupied, .EditAvailable:
            let retry  = step == .EditAvailable
            let filter = assume cast(*EditBox, unwrap root.childById("gui.shortcuts.filter"))
            let list   = assume cast(*ListCtrl, unwrap root.childById("gui.shortcuts.list"))
            filter.setText(appStrings().act_CaptureArea)
            Swag.require(list.lineCount() == 1)
            let row = unwrap list.selectedLine()
            let expected = retry ? Input.formatKeyShortcut(.Control, .F9) : Input.formatKeyShortcut(.None, .PrintScreen)
            Swag.require(row.items[1]!.name.text == expected)
            Swag.require(row.items[2]!.name.text == Gui.strings().shortcuts_Global)
            step = retry ? .PickAvailable : .PickOccupied
            host.clickWnd(unwrap root.childById("gui.shortcuts.change"))
            Swag.require(step == (retry ? .CloseOptions : .RejectOccupied))
            Swag.require(host.clickModalButton(Dialog.BtnOk))
        case .PickOccupied:
            step = .RejectOccupied
            pickCaptureShortcut(host, root, .F9)
        case .RejectOccupied:
            if root is MessageDlg as failure
            {
                Swag.require(failure.failure and failure.label.name.text == Gui.strings().shortcuts_Failed)
                let state = main.sendComputeCommandStateEvent(ActionCapture.Area)
                Swag.require(state.shortcut == Input.formatKeyShortcut(.None, .PrintScreen))
                step = .EditAvailable
                Swag.require(host.clickModalButton(Dialog.BtnOk))
            }
        case .PickAvailable:
            step = .CloseOptions
            pickCaptureShortcut(host, root, .F8)

        case .CloseOptions, .Done: break
        }
    }

    main.sendCommandEvent(ActionOptions.Options)
    host.app.sigFrame.clear()
    Swag.require(step == .Done)
    Swag.require(main.sendComputeCommandStateEvent(ActionCapture.Area).shortcut == Input.formatKeyShortcut(.Control, .F8))
    Swag.require(not host.app.unregisterHotKey(.None, .PrintScreen))
    Swag.require(host.app.unregisterHotKey(.Control, .F8))
    Swag.require(host.app.unregisterHotKey(.Control, .F9))
}
