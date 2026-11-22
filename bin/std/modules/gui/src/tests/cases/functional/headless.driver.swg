#global if #command == Swag.CompilerCommand.Test
#global private

using Swag, Core

// Timeout diagnostics distinguish an absent modal from an observed modal with the wrong action.
#test
{
    var host: Testing.HeadlessHost
    host.setup(300, 120)

    host.clickModalButtonWhenShown("missing", maxFrames: 1)
    host.driveAutoStages(&host.app)
    host.driveAutoStages(&host.app)
    Swag.require(not host.autoArmed and not host.autoHandled)
    Swag.require(host.autoFailure == "modal did not appear while waiting for button 'missing'")

    discard PushButton.create(&host.root, "Close", {10, 10, 90, 28}, id: "close")
    host.clickModalButtonWhenShown("missing", maxFrames: 1)
    Swag.require(host.autoFailure.isEmpty())
    host.app.modalSurfaces.add(&host.surface)
    host.driveAutoStages(&host.app)
    host.app.modalSurfaces.removeBack()

    // Remember an observed modal even if it disappears before the timeout is reached.
    host.driveAutoStages(&host.app)
    Swag.require(not host.autoArmed and not host.autoHandled)
    Swag.require(host.autoFailure == "modal appeared without button 'missing'; observed button identifiers: 'close'")
}

// A visible button whose validator refuses the action remains pending until the driver reports
// that preparation did not complete; finding the button alone is not a successful stage.
#test
{
    var host: Testing.HeadlessHost
    host.setup(300, 120)

    let dlg = Dialog.create(&host.surface, 260, 150, title: "Validate")
    dlg.addButton("Ok", Dialog.BtnOk, true)
    dlg.validateResult = func(_, _)->bool
    {
        return false
    }

    host.clickModalButtonWhenShown(Dialog.BtnOk, maxFrames: 1)
    let modalResult = dlg.doModal()
    Swag.require(modalResult == Dialog.BtnCancel)
    Swag.require(not host.autoArmed and not host.autoHandled)
    Swag.require(host.autoFailure == "modal preparation did not complete for button 'Dialog.BtnOk'")
}

// Advancing a stage before its click lets a validator open a nested confirmation synchronously;
// the nested modal consumes the next action and the original action then completes.
#test
{
    var host: Testing.HeadlessHost
    host.setup(300, 120)

    let dlg = Dialog.create(&host.surface, 260, 150, title: "Validate")
    dlg.addButton("Ok", Dialog.BtnOk, true)
    dlg.validateResult = func(bdlg, id)->bool
    {
        if id != Dialog.BtnOk do
            return true
        return MessageDlg.confirm(unwrap bdlg.surface, "Continue?") == Dialog.BtnYes
    }

    host.clickModalButtonWhenShown(Dialog.BtnOk)
    host.thenClickModalButton(Dialog.BtnYes)
    let modalResult = dlg.doModal()
    Swag.require(modalResult == Dialog.BtnOk)
    Swag.require(host.autoHandled and host.autoFailure.isEmpty())
}

// Destroying a parent dialog while a nested dialog is open must not leave its modal loop running.
#test
{
    var host: Testing.HeadlessHost
    host.setup(300, 120)

    let parent        = Dialog.create(&host.surface, 260, 150, title: "Parent")
    let parentSurface = unwrap parent.surface
    parent.addButton("Close", Dialog.BtnCancel, true)
    var stage: u32
    host.app.sigFrame += func|host = &host, parentSurface, &stage|(app)
    {
        if stage == 0 and app.modalSurfaces.count == 1
        {
            stage = 1
            let child = Dialog.create(parentSurface, 220, 120, title: "Child")
            child.addButton("Ok", Dialog.BtnOk, true)
            parentSurface.wnd.destroyNow()
            Swag.require(child.doModal() == Dialog.BtnOk)
        }
        elif stage == 1 and app.modalSurfaces.count == 2
        {
            stage = 2
            Swag.require(host.clickModalButton(Dialog.BtnOk))
        }
    }

    let result = parent.doModal()
    host.app.sigFrame.clear()
    Swag.require(stage == 2, "destroying a covered modal must end its loop after the child closes")
    Swag.require(result == "")
    Swag.require(host.app.modalSurfaces.isEmpty() and host.app.inModalLoop == 0)
    Swag.require(not host.surface.isDisabled)
}
