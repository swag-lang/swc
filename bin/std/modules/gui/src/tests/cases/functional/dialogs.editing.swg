#global if #command == Swag.CompilerCommand.Test
#global private

using Core

// Both kinds of text prompt need one Escape to leave the editor and another to cancel.
#test
{
    var host: Testing.HeadlessHost
    host.setup(700, 500)
    for multiline in [false, true]
    {
        let dlg       = multiline ? EditDlg.createMultiLine(&host.surface) : EditDlg.createSingleLine(&host.surface)
        var cancelled = 0
        dlg.validateResult = func|&cancelled|(_, id)
        {
            if id == Dialog.BtnCancel do
                cancelled += 1
            return false
        }

        dlg.setText("Keep this text")
        if multiline do
            dlg.richEdit!.setFocus()
        else do
            dlg.edit!.setFocus()
        host.keyPress(.Escape)
        Swag.require(cancelled == 0 and dlg.hasFocus())
        Swag.require(dlg.text() == "Keep this text")
        host.keyPress(.Escape)
        Swag.require(cancelled == 1)
        dlg.surface!.destroy()
        host.pump()
    }
}

// A path's last level and the filter use the same full-width field, with no nested editor.
#test
{
    let root = Path.combine(Env.getSpecialDirectory(.Temp), Format.toString("folder-edit-%", Guid64.random()))
    expect Directory.create(Path.combine(root, "Child"), recurse: true)
    defer discard catch Directory.delete(root, recurse: true)
    var host: Testing.HeadlessHost
    host.setup(800, 600)
    let dlg       = FileDlg.create(&host.surface, {mode: .SelectFolder, initialFolder: root, showLocationsPane: false})
    let browser   = dlg.browser
    var cancelled = 0
    dlg.validateResult = func|&cancelled|(_, id)
    {
        if id == Dialog.BtnCancel do
            cancelled += 1
        return false
    }

    dlg.applyLayout()
    let bar = browser.pathBar
    Swag.require(bar.isLocallyVisible() and browser.listCtrl.hasFocus())
    bar.breadcrumb.sigItemPressed.call(bar.breadcrumb, bar.breadcrumb.items.count - 1)
    Swag.require(browser.pathField.hasFocus() and root == browser.pathField.text())
    Swag.require(not bar.isLocallyVisible() and not bar.edit.isLocallyVisible())
    host.keyPress(.Escape)
    Swag.require(dlg.hasFocus() and cancelled == 0)
    Swag.require(bar.isLocallyVisible() and browser.pathField.text().count == 0)
    browser.pathField.setFocus()
    Swag.require(not bar.isLocallyVisible())
    browser.pathField.setText("Child")
    Swag.require(browser.listCtrl.lineCount() == 1)
    host.keyPress(.Escape)
    Swag.require(cancelled == 0 and dlg.hasFocus())
    host.keyPress(.Escape)
    Swag.require(cancelled == 1)
    dlg.surface!.destroy()
    host.pump()
}

// Human-readable dates retain a predictable calendar in each shipped language.
#test
{
    var host: Testing.HeadlessHost
    host.setup(100, 100)
    defer discard catch host.app.setLanguage(ReferenceLanguage)
    let now = Time.DateTime{year: 2026, month: 11, day: 4, hour: 9, minute: 5}
    expect host.app.setLanguage(ReferenceLanguage)
    Swag.require(fileBrowserTime(now, now) == "Today · 09:05")
    Swag.require(fileBrowserTime({year: 2026, month: 10, day: 26, hour: 21, minute: 30}, now) == "26 Oct · 21:30")
    Swag.require(fileBrowserTime({year: 2025, month: 12, day: 19}, now) == "19 Dec 2025")
    expect host.app.setLanguage("fr")
    Swag.require(fileBrowserTime(now, now) == "Aujourd'hui · 09:05")
    Swag.require(fileBrowserTime({year: 2025, month: 2, day: 19}, now) == "19 févr. 2025")
}
