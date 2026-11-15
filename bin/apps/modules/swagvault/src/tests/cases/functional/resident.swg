#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Gui

// Migration defaults and private mode persist only non-sensitive resident policy.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    Swag.require(not window.resident.settings.enabled)
    Swag.require(not window.resident.settings.startWithSession)
    Swag.require(window.resident.settings.showReminder)
    window.resident.settings.enabled      = true
    window.resident.settings.showReminder = false
    window.addVault("C:\\private-vault.bin")
    let saved = saveMainWindowState(window)
    window.resident.settings = {}
    loadMainWindowState(window, saved.toSlice())
    Swag.require(window.resident.settings.enabled and not window.resident.settings.showReminder)
    Swag.require(window.privacyMode and window.vaults.count == 0)
    Swag.require(window.optionsPage.resident.toggle.isChecked())
}

// The detached menu uses the same command catalog and discloses no container identity.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    fillPictureList(window)
    window.privacyMode = true
    let panel = ResidentMenu.create(window, window)
    Swag.require(panel.paths.count == 1)
    Swag.require(panel.menu.items[0]!.id == VaultCommands.ShowWindow)
    Swag.require(panel.menu.items[1]!.id == VaultCommands.OpenFile)
    for item in panel.menu.items
    {
        Swag.require(item!.popup == null)
        let text = item.name.raw.toString()
        Swag.require(not Utf8.contains(text, "papiers"))
        Swag.require(not Utf8.contains(text, "Users"))
    }

    for action in ["open", "unmount", "force"]
    {
        var found = false
        for item in panel.menu.items where item!.id == Format.toString("vault.resident.%.0", action) do
            found = true
        Swag.require(found)
    }

    panel.destroy()
    for id in [VaultCommands.ShowWindow, VaultCommands.UnmountAll, VaultCommands.Quit,
               VaultCommands.Resident, VaultCommands.SessionStartup]
    {
        var state: CommandStateEvent
        state.id = id
        Swag.require(window.computeCommandState(&state))
        Swag.require(state.name.count != 0)
    }
}

// Disabling residence also disables the dependent session-startup choice.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    window.resident.settings.enabled = true
    window.resident.applySettings()
    Swag.require(window.optionsPage.startup.toggle.isEnabled())
    window.resident.setEnabled(false)
    Swag.require(not window.optionsPage.startup.toggle.isEnabled())
    Swag.require(not window.resident.settings.startWithSession)
}

// A headless desktop cannot publish an icon: residency keeps the main surface accessible.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    window.resident.running = true
    window.resident.settings.enabled = true
    window.resident.icon    = expect Pixel.Image.decode(".png", AppIcon)
    window.resident.refreshTray()
    Swag.require(not host.surface.hasTrayIcon() and not host.surface.isHidden)
    Swag.require(window.statusDetail == appStrings().msg_TrayUnavailable)
}

// A security event can remove a drive while its menu is open; its stale choice never retargets.
#test
{
    var host: Testing.HeadlessHost
    let window = testSetupMainWindow(&host)
    fillPictureList(window)
    window.showPage(.Options, animate: false)
    let panel = unwrap ResidentMenu.open(window)
    var state: CommandStateEvent
    state.id = VaultCommands.Options
    panel.sendEvent(&state)
    Swag.require(not state.hidden and state.updatedFields.has(.Hidden))
    window.mountedDrives.drives.clear()
    panel.choose("vault.resident.unmount.0")
    host.pump()
    Swag.require(window.operation.kind == .None and not window.isPendingDestroy)
}
