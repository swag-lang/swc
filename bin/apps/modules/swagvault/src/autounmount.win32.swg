#global if #os == Swag.TargetOs.Windows

using Core, Gui, Win32

private const AutoUnmountSubclassId = 0x7353_4372'u64

// Receives the two notifications that must be handled before the window's ordinary event queue.
private func autoUnmountSubclass(hwnd: HWND, message: u32, wParam: u64, lParam: s64, id, data: u64)->s64
{
    discard id
    let window = cast(*MainWindow) cast #bit (u64) data
    if message == WM_WTSSESSION_CHANGE and wParam == WTS_SESSION_LOCK do
        window.handleAutoUnmount(.SessionLock)
    elif message == WM_POWERBROADCAST and wParam == PBT_APMSUSPEND do
        window.handleAutoUnmount(.Suspend)
    return DefSubclassProc(hwnd, message, wParam, lParam)
}

// Native registrations owned by the main surface.
struct AutoUnmountMonitor
{
    hwnd: HWND
}

impl AutoUnmountMonitor
{
    mtd start(window: *MainWindow)
    {
        if .hwnd do
            return
        let hwnd = window.surface!.win32Handle()
        if not hwnd do
            return
        if not SetWindowSubclass(hwnd, cast() &autoUnmountSubclass, AutoUnmountSubclassId, cast(u64) window) do
            return
        .hwnd = hwnd
        discard WTSRegisterSessionNotification(hwnd, NOTIFY_FOR_THIS_SESSION)
    }

    mtd stop()
    {
        if not .hwnd do
            return
        discard WTSUnRegisterSessionNotification(.hwnd)
        discard RemoveWindowSubclass(.hwnd, cast() &autoUnmountSubclass, AutoUnmountSubclassId)
        .hwnd = null
    }
}

// Milliseconds since the current Windows session last received keyboard or pointer input.
func autoUnmountIdleMilliseconds()->u64
{
    var info: LASTINPUTINFO
    info.cbSize = #sizeof(LASTINPUTINFO)
    if not GetLastInputInfo(&info) do
        return 0

    let now = GetTickCount()
    if now >= info.dwTime do
        return now - info.dwTime
    return cast(u64) Swag.U32.Max - info.dwTime + now + 1
}
