#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Windows
#global private

using Swag, Core, Win32

// Both Shell callback layouts identify the icon and expose its context-menu and activation.
#test
{
    var host: Testing.HeadlessHost
    host.setup(160, 80)
    defer host.shutdown()

    let surface = &host.surface
    Swag.require(surface.trayActionForNotification(1, WM_RBUTTONDOWN) == .None)
    Swag.require(surface.trayActionForNotification(1, WM_RBUTTONUP) == .ContextMenu)
    Swag.require(surface.trayActionForNotification(1, WM_LBUTTONDBLCLK) == .Activate)
    Swag.require(surface.trayActionForNotification(1, WM_LBUTTONUP) == .None)
    Swag.require(surface.trayActionForNotification(2, WM_RBUTTONUP) == .None)

    surface.native.trayIconVersion4 = true
    let icon = 1 << 16
    Swag.require(surface.trayActionForNotification(0, icon | WM_CONTEXTMENU) == .ContextMenu)
    Swag.require(surface.trayActionForNotification(0, icon | WM_LBUTTONDBLCLK) == .Activate)
    Swag.require(surface.trayActionForNotification(0, icon | (WM_USER + 1)) == .Activate)
    Swag.require(surface.trayActionForNotification(0, icon | WM_LBUTTONUP) == .None)
    Swag.require(surface.trayActionForNotification(0, (2 << 16) | WM_CONTEXTMENU) == .None)
}
