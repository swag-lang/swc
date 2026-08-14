#global if #os == Swag.TargetOs.Windows

using Core, Gui

#foreignlib("comctl32")
#foreignlib("wtsapi32")
#foreignlib("user32")
#foreignlib("kernel32")

private const PbtApmSuspend = 0x0004'u64
private const WtsSessionLock = 0x0007'u64
private const NotifyForThisSession = 0'u32
private const AutoUnmountSubclassId = 0x7353_4372'u64
private const WmPowerBroadcast = 0x0218'u32
private const WmWtsSessionChange = 0x02B1'u32

private alias NativeWindow = #null const *void

private struct LastInputInfo
{
    cbSize: u32
    dwTime: u32
}

private alias AutoUnmountSubclassProc = func(NativeWindow, u32, u64, s64, u64, u64)->s64

private #[Swag.Foreign("comctl32")]
{
    func SetWindowSubclass(hwnd: NativeWindow, callback: AutoUnmountSubclassProc, id, data: u64)->s32
    func RemoveWindowSubclass(hwnd: NativeWindow, callback: AutoUnmountSubclassProc, id: u64)->s32
    func DefSubclassProc(hwnd: NativeWindow, message: u32, wParam: u64, lParam: s64)->s64
}

private #[Swag.Foreign("wtsapi32")]
{
    func WTSRegisterSessionNotification(hwnd: NativeWindow, flags: u32)->s32
    func WTSUnRegisterSessionNotification(hwnd: NativeWindow)->s32
}

private #[Swag.Foreign("user32")]
{
    func GetLastInputInfo(info: *LastInputInfo)->s32
}

private #[Swag.Foreign("kernel32")]
{
    func GetTickCount()->u32
}

// Receives the two notifications that must be handled before the window's ordinary event queue.
private func autoUnmountSubclass(hwnd: NativeWindow, message: u32, wParam: u64, lParam: s64, id, data: u64)->s64
{
    discard id
    let window = cast(*MainWindow) cast #bit (u64) data
    if message == WmWtsSessionChange and wParam == WtsSessionLock do
        window.handleAutoUnmount(.SessionLock)
    elif message == WmPowerBroadcast and wParam == PbtApmSuspend do
        window.handleAutoUnmount(.Suspend)
    return DefSubclassProc(hwnd, message, wParam, lParam)
}

// Native registrations owned by the main surface.
struct AutoUnmountMonitor
{
    hwnd: NativeWindow
}

impl AutoUnmountMonitor
{
    mtd start(window: *MainWindow)
    {
        if .hwnd do
            return
        let hwnd = window.surface!.win32Handle()
        if !hwnd do
            return
        if !SetWindowSubclass(hwnd, cast() &autoUnmountSubclass, AutoUnmountSubclassId, cast(u64) window) do
            return
        .hwnd = hwnd
        discard WTSRegisterSessionNotification(hwnd, NotifyForThisSession)
    }

    mtd stop()
    {
        if !.hwnd do
            return
        discard WTSUnRegisterSessionNotification(.hwnd)
        discard RemoveWindowSubclass(.hwnd, cast() &autoUnmountSubclass, AutoUnmountSubclassId)
        .hwnd = null
    }
}

// Milliseconds since the current Windows session last received keyboard or pointer input.
func autoUnmountIdleMilliseconds()->u64
{
    var info: LastInputInfo
    info.cbSize = #sizeof(LastInputInfo)
    if !GetLastInputInfo(&info) do
        return 0

    let now = GetTickCount()
    if now >= info.dwTime do
        return now - info.dwTime
    return cast(u64) Swag.U32.Max - info.dwTime + now + 1
}
