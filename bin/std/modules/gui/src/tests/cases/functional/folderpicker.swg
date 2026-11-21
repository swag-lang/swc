#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, File

// Enter belongs to the folder list while it has focus, including when the list is empty.
#test
{
    let root   = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("swag-folder-picker-%", Guid64.random().toString()))
    let folder = Path.combine(root, "sub")
    expect Directory.create(folder, recurse: true)
    defer discard catch Directory.delete(root, recurse: true)

    var host: Testing.HeadlessHost
    host.setup(900, 700)
    let dlg = FileDlg.create(&host.surface, {mode: .SelectFolder, showLocationsPane: false, initialFolder: root.toString()})
    var browsed: bool

    host.app.sigFrame += func|host = &host, dlg, folder = &folder, browsed = &browsed|(_)
    {
        if browsed[] do
            return
        browsed[] = true

        let browser = dlg.browser
        browser.pathField.setFocus()
        browser.pathField.setText("sub")
        host.keyPress(.Down)
        Swag.require(browser.listCtrl.hasFocus() and dlg.selectedPath() == folder[])

        host.keyPress(.Return)
        Swag.require(not host.app.endModal and browser.currentFolder == folder[])
        Swag.require(browser.listCtrl.hasFocus() and browser.listCtrl.lines.isEmpty())

        host.keyPress(.Return)
        Swag.require(not host.app.endModal)

        let clicked = host.clickModalButton(Dialog.BtnOk)
        Swag.require(clicked)
    }

    let result = dlg.doModal()
    Swag.require(browsed and result == Dialog.BtnOk and dlg.selectedPath() == folder)
    host.pump()
}
