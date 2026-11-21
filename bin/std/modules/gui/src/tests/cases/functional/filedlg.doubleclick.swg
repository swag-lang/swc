#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core, File

// Double-clicking a folder shows its contents and keeps the file dialog open.
#test
{
    let root   = Path.combine(Env.getSpecialDirectory(.Temp).toString(), Format.toString("swag-filedlg-double-click-%", Guid64.random().toString()))
    let folder = Path.combine(root, "sub")
    expect Directory.create(Path.combine(folder, "inside"), recurse: true)
    defer discard catch Directory.delete(root, recurse: true)
    discard expect File.writeAllText(Path.combine(root, "outer.txt"), "outer")

    for mode in [FileDlgMode.SelectFolder, .SelectFile, .SelectFiles, .CreateFile]
    {
        var host: Testing.HeadlessHost
        host.setup(900, 700)
        let dlg = FileDlg.create(&host.surface, {mode: mode, showLocationsPane: false, initialFolder: root.toString(), initialName: "draft.txt"})
        var checked: bool

        host.app.sigFrame += func|host = &host, dlg, folder = &folder, checked = &checked|(_)
        {
            if checked[] do
                return
            checked[] = true

            let list  = dlg.browser.listCtrl
            let view  = list.listView
            let room  = view.paddedClientRect()
            var point = view.localToSurface(Math.Point{room.x + 60, room.y + list.lineHeight() * 0.5})
            view.surface!.surfaceToScreen(&point)

            host.click(point)
            Swag.require(list.isLineSelected(0) and list.lines[0]!.itemAt(0).name.text == "sub")

            host.doubleClick(point)
            Swag.require(not host.app.endModal and dlg.browser.currentFolder == folder[])
            Swag.require(list.lineCount() == 1 and list.lines[0]!.itemAt(0).name.text == "inside")

            let cancelled = host.clickModalButton(Dialog.BtnCancel)
            Swag.require(cancelled)
        }

        let result = dlg.doModal()
        Swag.require(checked and result == Dialog.BtnCancel)
        host.pump()
    }
}
