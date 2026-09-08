#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Timeout diagnostics distinguish an absent modal from an observed modal with the wrong action.
#test
{
    var host: Testing.HeadlessHost
    host.setup(300, 120)
    defer host.shutdown()

    host.clickModalButtonWhenShown("missing", maxFrames: 1)
    host.driveAutoStages(&host.app)
    host.driveAutoStages(&host.app)
    Swag.assert(!host.autoArmed and !host.autoHandled)
    Swag.assert(host.autoFailure == "modal did not appear while waiting for button 'missing'")

    discard PushButton.create(&host.root, "Close", {10, 10, 90, 28}, id: "close")
    host.clickModalButtonWhenShown("missing", maxFrames: 1)
    Swag.assert(host.autoFailure.isEmpty())
    host.app.modalSurfaces.add(&host.surface)
    host.driveAutoStages(&host.app)
    host.app.modalSurfaces.removeBack()

    // Remember an observed modal even if it disappears before the timeout is reached.
    host.driveAutoStages(&host.app)
    Swag.assert(!host.autoArmed and !host.autoHandled)
    Swag.assert(host.autoFailure == "modal appeared without button 'missing'; observed button identifiers: 'close'")
}

// A visible button whose validator refuses the action remains pending until the driver reports
// that preparation did not complete; finding the button alone is not a successful stage.
#test
{
    var host: Testing.HeadlessHost
    host.setup(300, 120)
    defer host.shutdown()

    let dlg = Dialog.create(&host.surface, 260, 150, title: "Validate")
    dlg.addButton("Ok", Dialog.BtnOk, true)
    dlg.validateResult = func(bdlg, id)->bool
    {
        discard bdlg
        discard id
        return false
    }

    host.clickModalButtonWhenShown(Dialog.BtnOk, maxFrames: 1)
    let modalResult = dlg.doModal()
    Swag.assert(modalResult == Dialog.BtnCancel)
    Swag.assert(!host.autoArmed and !host.autoHandled)
    Swag.assert(host.autoFailure == "modal preparation did not complete for button 'Dialog.BtnOk'")
}

// Advancing a stage before its click lets a validator open a nested confirmation synchronously;
// the nested modal consumes the next action and the original action then completes.
#test
{
    var host: Testing.HeadlessHost
    host.setup(300, 120)
    defer host.shutdown()

    let dlg = Dialog.create(&host.surface, 260, 150, title: "Validate")
    dlg.addButton("Ok", Dialog.BtnOk, true)
    dlg.validateResult = func(bdlg, id)->bool
    {
        if id != Dialog.BtnOk do
            return true
        return MessageDlg.confirm(bdlg.surface!, "Continue?") == Dialog.BtnYes
    }

    host.clickModalButtonWhenShown(Dialog.BtnOk)
    host.thenClickModalButton(Dialog.BtnYes)
    let modalResult = dlg.doModal()
    Swag.assert(modalResult == Dialog.BtnOk)
    Swag.assert(host.autoHandled and host.autoFailure.isEmpty())
}
