#global if #command == Swag.CompilerCommand.Test and WINDOWS
#global private

// The installer receives a native Windows path even when the executable path uses slashes.
#test
{
    let package = WinFsp.installerPackagePath("C:/Swag Vault")
    Swag.require(package == "C:\\Swag Vault\\winfsp.msi")
}

// Canceling the first mount leaves the vault locked and still offers the choice next time.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    useTestDestination(window)
    window.openVault("/install-driver.vault")
    Swag.require(window.needsDriverChoice())
    host.clickModalButtonWhenShown(Dialog.BtnCancel)
    window.mountContainer()
    Swag.require(host.autoHandled and window.operation.kind == .None)
    Swag.require(window.needsDriverChoice() and not window.preferPortableWinFsp)
}

// Staying portable survives a state round trip and leaves installation in Options and the lens.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    host.clickModalButtonWhenShown(Dialog.BtnNo)
    let mount = window.chooseDriverForMount("/install-driver.vault")
    Swag.require(host.autoHandled and mount and window.preferPortableWinFsp)

    let state = saveMainWindowState(window)
    window.preferPortableWinFsp = false
    loadMainWindowState(window, state.toSlice())
    Swag.require(window.preferPortableWinFsp and not window.needsDriverChoice())

    window.showPage(.Options, animate: false)
    for language in Gui.languages()
    {
        expect host.app.setLanguage(language.tag)
        host.pump()
        let action = unwrap window.optionsPage.driverAction
        Testing.assertContentFits(action)
        Swag.require(action.firstLinkRect().width > 0)
        var command = CommandStateEvent{id: VaultCommands.InstallWinFsp}
        let known   = window.computeCommandState(&command)
        Swag.require(known and not command.hidden and not command.disabled)
    }

    expect host.app.setLanguage(ReferenceLanguage)
}

// The installer runs on the worker, with a target only when a mount asked for it.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    host.clickModalButtonWhenShown(Dialog.BtnOk)
    let path  = "/install-driver.vault"
    let mount = window.chooseDriverForMount(path)
    Swag.require(host.autoHandled and not mount and window.operation.kind == .InstallDriver)
    Swag.require(window.operation.path == path)

    // A lock cancels the pending mount while the install finishes independently.
    window.handleAutoUnmount(.SessionLock)
    Swag.require(window.operation.path.isEmpty())
    host.clickModalButtonWhenShown(Dialog.BtnOk)
    window.operation.task.wait()
    window.finishOperation()
    Swag.require(host.autoHandled and window.operation.kind == .None)
    Swag.require(window.statusMessage == .DriverInstallStopped)
}

// A successful installer result hands the original request back to the regular mount path.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    let path   = Testing.tempFilePath("vault-missing-for-install-", ".vault")
    window.openVault(path)
    useTestDestination(window)

    // The sandbox substitutes for the system installation. The missing vault keeps this
    // test away from the real driver while letting it observe a resubmitted mount.
    window.preferPortableWinFsp = true
    window.operation.path       = path
    window.operation.kind       = .InstallDriver
    window.operation.task.submit(func() {})
    window.finishOperation()
    Swag.require(window.operation.kind == .Mount and window.operation.path == path)
    host.clickModalButtonWhenShown(Dialog.BtnOk)
    window.finishOperation()
    Swag.require(host.autoHandled and window.operation.kind == .None)
}
