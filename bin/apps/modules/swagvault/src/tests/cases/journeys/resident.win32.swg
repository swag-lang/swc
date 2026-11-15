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

    Swag.require(Surface.sendCustomMessage("vault-resident-journey", ShowWindowMessage, 0))
    Swag.require(not surface.isHidden)
    window.resident.hideWindow()
    var activation = SysUserEvent{kind: .TrayIcon, trayAction: .Activate}
    window.sendEvent(&activation)
    Swag.require(not surface.isHidden)
    window.resident.hideWindow()
    window.resident.setEnabled(false)
    Swag.require(not surface.isHidden and not surface.hasTrayIcon())
}
