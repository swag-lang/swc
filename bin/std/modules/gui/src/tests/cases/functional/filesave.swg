#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, File

// Enter navigates into the selected folder and keeps the filename for the save.
#test
{
    let root     = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("swag-file-save-%", Guid64.random().toString()))
    let folder   = Path.combine(root, "sub")
    let fileName = "draft.txt"
    expect Directory.create(folder, recurse: true)
    defer discard catch Directory.delete(root, recurse: true)

    var host: Testing.HeadlessHost
    host.setup(900, 700)
    let dlg = FileDlg.create(&host.surface, {mode: .CreateFile, showLocationsPane: false, initialFolder: root.toString(), initialName: fileName})
    var browsed: bool

    host.app.sigFrame += func|host = &host, dlg, folder = &folder, browsed = &browsed|(_)
    {
        if browsed[] do
            return
        browsed[] = true

        let browser = dlg.browser
        browser.listCtrl.setFocus()
        host.keyPress(.Down)
        Swag.require(browser.listCtrl.hasFocus() and browser.listCtrl.isLineSelected(0))
        Swag.require(browser.hasValidSelection())

        host.keyPress(.Return)
        Swag.require(not host.app.endModal and browser.currentFolder == folder[])
        Swag.require(browser.listCtrl.hasFocus())

        let clicked = host.clickModalButton(Dialog.BtnOk)
        Swag.require(clicked)
    }

    let result = dlg.doModal()
    Swag.require(browsed and result == Dialog.BtnOk and dlg.selectedPath() == Path.combine(folder, fileName))
    host.pump()
}
