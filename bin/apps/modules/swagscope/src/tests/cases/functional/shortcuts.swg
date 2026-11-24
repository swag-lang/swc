#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// General Options can rebind an active viewer command and replace the viewer's original key handler.
#test
{
    let fileName = Testing.tempFilePath("scope-shortcut-", ".txt")
    defer discard catch File.delete(fileName)
    discard expect File.writeAllText(fileName, "A line of plain text to wrap.\n")

    var stage: u32
    var host:  Testing.HeadlessHost
    let window = openFramedViewerWindow(&host, fileName, light: false, width: 1100, height: 860)
    registerAppStrings(&host.app.resources)
    let view     = assume cast(*PlainText.Panel, unwrap window.currentView)
    let wrapping = view.wrapping
    view.editor.setFocus()
    host.keyPress(.W, .CtrlShift)
    Swag.require(view.wrapping != wrapping)
    host.keyPress(.W, .CtrlShift)
    Swag.require(view.wrapping == wrapping)

    host.app.sigFrame += func|host = &host, &stage|(app)
    {
        let root = app.surfaces.back().view()
        switch stage
        {
        case 0:
            if root is Dialog as options
            {
                Swag.require(options.title.text == appStrings().ui_GeneralOptionsTitle)
                stage = 1
                host.clickWnd(unwrap options.leadingControl)
                Swag.require(stage == 3)
                stage = 4
                Swag.require(host.clickModalButton(Dialog.BtnCancel))
            }

        case 1:
            let filter = assume cast(*EditBox, unwrap root.childById("gui.shortcuts.filter"))
            let list   = assume cast(*ListCtrl, unwrap root.childById("gui.shortcuts.list"))
            filter.setText(PlainText.texts().ui_Wrap)
            Swag.require(list.lineCount() == 1)
            let row = unwrap list.selectedLine()
            Swag.require(row.items[1]!.name.text == Input.formatKeyShortcut(.CtrlShift, .W))
            Swag.require(row.items[2]!.name.text == Gui.strings().shortcuts_Document)
            stage = 2
            host.clickWnd(unwrap root.childById("gui.shortcuts.change"))
            Swag.require(stage == 3)
            Swag.require(host.clickModalButton(Dialog.BtnOk))

        case 2:
            stage = 3
            host.keyPress(.F8, .Control)
        }
    }

    window.sendCommandEvent(ViewerCommands.GeneralOptions)
    host.app.sigFrame.clear()
    Swag.require(stage == 4)
    view.editor.setFocus()
    host.keyPress(.W, .CtrlShift)
    Swag.require(view.wrapping == wrapping)
    host.keyPress(.F8, .Control)
    Swag.require(view.wrapping != wrapping)
}
