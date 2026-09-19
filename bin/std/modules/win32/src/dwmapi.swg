#global export

#foreignlib("dwmapi")

const DWM_BB_ENABLE                   = 0x00000001'u32
const DWM_BB_BLURREGION               = 0x00000002'u32
const DWMWA_TRANSITIONS_FORCEDISABLED = 3'u32
const DWMWA_WINDOW_CORNER_PREFERENCE  = 33'u32
const DWMWA_BORDER_COLOR              = 34'u32
const DWMWA_COLOR_NONE                = 0xFFFFFFFE'u32
const DWMWCP_DONOTROUND               = 1'u32
const DWMWCP_ROUND                    = 2'u32

struct DWM_BLURBEHIND
{
    public
    {
        dwFlags:  DWORD
        fEnable:  BOOL
        hRgnBlur: HRGN
        fTransitionOnMaximized: BOOL
    }
}

#[Swag.Foreign("dwmapi", callconv: Swag.CallConv.C)]
{
    func DwmSetWindowAttribute(hwnd: HWND, dwAttribute: DWORD, pvAttribute: LPCVOID, cbAttribute: DWORD)->HRESULT
    func DwmEnableBlurBehindWindow(hWnd: HWND, pBlurBehind: const *DWM_BLURBEHIND)->HRESULT
}
