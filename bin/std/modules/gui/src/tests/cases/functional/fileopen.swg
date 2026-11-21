#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, File

// Enter navigates into a selected folder before it can confirm a file choice.
#test
{
    let root   = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("swag-file-open-%", Guid64.random().toString()))
    let folder = Path.combine(root, "sub")
    let file   = Path.combine(folder, "inner.txt")
    expect Directory.create(folder, recurse: true)
    defer discard catch Directory.delete(root, recurse: true)
    discard expect File.writeAllText(Path.combine(root, "outer.txt"), "outer")
    discard expect File.writeAllText(file, "inner")

    for mode in [FileDlgMode.SelectFile, .SelectFiles]
    {
        var host: Testing.HeadlessHost
        host.setup(900, 700)
        let dlg = FileDlg.create(&host.surface, {mode: mode, showLocationsPane: false, initialFolder: root.toString(), initialName: "outer.txt"})
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
            Swag.require(browser.listCtrl.hasFocus() and browser.listCtrl.isLineSelected(0))
            Swag.require(browser.hasValidSelection())

            host.keyPress(.Return)
            Swag.require(not host.app.endModal and browser.currentFolder == folder[])
            Swag.require(browser.listCtrl.hasFocus())

            host.keyPress(.Down)
            host.keyPress(.Return)
            Swag.require(host.app.endModal)
        }

        let result = dlg.doModal()
        Swag.require(browsed and result == Dialog.BtnOk and dlg.selectedPath() == file)
        host.pump()
    }
}
