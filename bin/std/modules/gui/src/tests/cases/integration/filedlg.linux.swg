#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Core

// The common file chooser runs modally on a real X11 surface with Linux path rules.
#[Swag.TestTag("integration.desktop")]
#test
{
    Swag.require(Env.variable("SWAG_TEST_ISOLATED_X11") == "1")
    var temporary = Path.combine(Env.getSpecialDirectory(.Temp), "swag-native-filedlg-XXXXXX")
    Swag.require(Linux.mkdtemp(temporary.storage()) == temporary.buffer)
    defer expect Directory.delete(temporary, recurse: true)
    let file = Path.combine(temporary, "colon:é.txt")
    expect File.writeAllText(file.toString(), "native")

    var app: Application
    app.setMotionPreference(.Reduced)
    let surface = expect app.createSurface(60, 50, 420, 300, surfaceId: "linux-native-filedlg")
    surface.show()
    for 4 do
        app.runFrame()

    var pending: *FileDlg?
    var action:  u32
    app.sigFrame += func|&pending, &action|(_)
    {
        if not pending do
            return
        let dlg = unwrap pending
        pending = null
        switch action
        {
        case 0:
            dlg.browser.setFileName("colon:é.txt")
            Swag.require(dlg.closeWithResult(Dialog.BtnOk))
        case 1:
            dlg.browser.setFileName("new:é.txt")
            Swag.require(dlg.closeWithResult(Dialog.BtnOk))
        case 2:
            dlg.browser.setFileName("missing/sub")
            Swag.require(not dlg.closeWithResult(Dialog.BtnOk))
            Swag.require(dlg.closeWithResult(Dialog.BtnCancel))
        }
    }

    var selected = FileDlg.create(surface, {mode: .SelectFile, initialFolder: temporary.toString(), showLocationsPane: false})
    action = 0
    pending = selected
    Swag.require(selected.doModal() == Dialog.BtnOk)
    Swag.require(selected.selectedPath() == file)

    var saved = FileDlg.create(surface, {mode: .CreateFile, initialFolder: temporary.toString(), showLocationsPane: false})
    action = 1
    pending = saved
    Swag.require(saved.doModal() == Dialog.BtnOk)
    let newFile = Path.combine(temporary, "new:é.txt")
    Swag.require(saved.selectedPath() == newFile and not File.exists(newFile))

    var cancelled = FileDlg.create(surface, {mode: .SelectFile, initialFolder: temporary.toString(), showLocationsPane: false})
    action = 2
    pending = cancelled
    Swag.require(cancelled.doModal() == Dialog.BtnCancel)
    Swag.require(pending == null)
}
