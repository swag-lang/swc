#global if #command == Swag.CompilerCommand.Test and WINDOWS
#global private

using Core, Gui, Pixel, Win32

// Native close, tray activation, shell restart and relaunch all keep one accessible owner.
#[Swag.TestTag("integration.application.journey")]
#test
{
    let state = Testing.tempFilePath("vault-resident-journey-", ".scc")
    defer discard catch File.delete(state)
    g_App.setStatePath(state)
    g_App.setAppIcon(expect Image.decode(".png", AppIcon))
    registerAppStrings(&g_App.resources)
    let surface = expect g_App.createSurface(80, 80, 900, 720, surfaceId: "vault-resident-journey")
    let window  = MainWindow.create(surface.wnd)
    defer
    {
        if g_App.surfaces.contains(surface) do
            surface.destroy()
        Swag.drop(&g_App, 1)
        Swag.init(&g_App, 1)
    }

    window.initialize()
    window.resident.settings.enabled      = true
    window.resident.settings.showReminder = false
    window.resident.start()
    g_App.runFrame()
    Swag.require(surface.hasTrayIcon() and not surface.isHidden)
    window.mountPassword.storage[0]  = 'x'
    window.mountPassword.byteCount   = 1
    window.createPassword.storage[0] = 'y'
    window.createPassword.byteCount  = 1
    var close = SysCommandEvent{kind: .Close}
    window.sendEvent(&close)
    Swag.require(close.accepted and surface.isHidden)
    Swag.require(window.mountPassword.isEmpty() and window.createPassword.isEmpty())
    Swag.require(window.securityTimer != null and not window.shuttingDown)

    // The desktop discards its registrations when Explorer restarts. Retain the application's
    // owned image and verify that the real TaskbarCreated route restores the registration.
    var icon: NOTIFYICONDATAA
    icon.cbSize = #sizeof(NOTIFYICONDATAA)
    icon.hWnd   = surface.win32Handle()
    icon.uID    = 1
    expect Shell_NotifyIconA(NIM_DELETE, &icon)
    let message = Utf16.toZeroTerminated("TaskbarCreated")
    discard SendMessageW(surface.win32Handle(), RegisterWindowMessageW(message.buffer), 0, 0)
    var rectangle: RECT
    var identifier = NOTIFYICONIDENTIFIER{cbSize: #sizeof(NOTIFYICONIDENTIFIER), hWnd: surface.win32Handle(), uID: 1}
    Swag.require(Shell_NotifyIconGetRect(&identifier, &rectangle) == S_OK)

    // The tray menu owns its complete surface and returns directly to the resident window.
    var contextMenu = SysUserEvent{kind: .TrayIcon, trayAction: .ContextMenu}
    window.sendEvent(&contextMenu)
    let panel       = unwrap window.resident.menu
    let menuSurface = unwrap panel.surface
    var menuWatch: Time.Stopwatch
    menuWatch.start()
    while not (expect Testing.verifyNativePresentation(menuSurface))
    {
        Swag.require(menuWatch.elapsedMilliseconds() < 5000, "resident menu presentation exceeded its deadline")
        g_App.runFrame()
    }

    var nativeBounds: RECT
    let gotBounds = GetWindowRect(menuSurface.win32Handle(), &nativeBounds)
    Swag.require(gotBounds != 0)
    Swag.require(Math.abs(cast(f32, nativeBounds.left) - menuSurface.position.x) < 1)
    Swag.require(Math.abs(cast(f32, nativeBounds.top) - menuSurface.position.y) < 1)
    for item in panel.menu.items do
        Swag.require(item!.popup == null)
    panel.choose(VaultCommands.ShowWindow)
    g_App.runFrame()
    Swag.require(window.resident.menu == null and not surface.isHidden)
    window.resident.hideWindow()

    Swag.require(Surface.sendCustomMessage("vault-resident-journey", ShowWindowMessage, 0))
    Swag.require(not surface.isHidden)
    window.resident.hideWindow()
    var activation = SysUserEvent{kind: .TrayIcon, trayAction: .Activate}
    window.sendEvent(&activation)
    Swag.require(not surface.isHidden)
    window.resident.hideWindow()

    let path = Testing.tempFilePath("vault launch é-", ".container-data")
    defer discard catch File.delete(path)
    let keyPath = Testing.tempFilePath("vault launch key-", ".bin")
    defer discard catch File.delete(keyPath)
    discard expect File.writeAllText(keyPath, "key file")
    var access: VaultAccess
    access.keyFiles.add(keyPath)
    let credential = expect access.derive()
    var volume     = expect Volume.create(path, credential.toSlice(), MinimumSize)
    volume.close()
    let forwarded = expect forwardVaultLaunch("vault-resident-journey", path)
    Swag.require(forwarded and not surface.isHidden)
    var launchWatch: Time.Stopwatch
    launchWatch.start()
    while window.chosenLockedPath() != path.toString() or window.operation.kind != .None
    {
        Swag.require(launchWatch.elapsedMilliseconds() < 5000, "vault launch did not select the container")
        g_App.runFrame()
    }

    Swag.require(window.list.card.panel.isLocallyVisible())
    Swag.require(window.mountPassword.isEmpty() and window.statusMessage == .Ready)
    Swag.require(window.mountedDrives.drives.isEmpty() and window.mountButton.isEnabled())

    window.resident.hideWindow()
    window.resident.setEnabled(false)
    Swag.require(not surface.isHidden and not surface.hasTrayIcon())

    window.sendEvent(&close)
    Swag.require(close.accepted and surface.wnd.isPendingDestroy)
    g_App.runFrame()
    Swag.require(not g_App.surfaces.contains(surface))
}
