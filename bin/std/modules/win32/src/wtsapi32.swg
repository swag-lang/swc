#global export

#foreignlib("wtsapi32")

const WTS_SESSION_LOCK        = 0x7'u32
const NOTIFY_FOR_THIS_SESSION = 0'u32

#[Swag.Foreign("wtsapi32", callconv: Swag.CallConv.C)]
{
    func WTSRegisterSessionNotification(hWnd: HWND, dwFlags: DWORD)->BOOL
    func WTSUnRegisterSessionNotification(hWnd: HWND)->BOOL
}
