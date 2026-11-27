#global export

#foreignlib("dwmapi")

const DWM_BB_ENABLE                   = 0x00000001_u32
const DWM_BB_BLURREGION               = 0x00000002_u32
const DWMWA_TRANSITIONS_FORCEDISABLED = 3_u32
const DWMWA_WINDOW_CORNER_PREFERENCE  = 33_u32
const DWMWA_BORDER_COLOR              = 34_u32
const DWMWA_COLOR_NONE                = 0xFFFFFFFE_u32
const DWMWCP_DONOTROUND               = 1_u32
const DWMWCP_ROUND                    = 2_u32

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
    func DwmFlush()->HRESULT
    func DwmSetWindowAttribute(hwnd: HWND, dwAttribute: DWORD, pvAttribute: LPCVOID, cbAttribute: DWORD)->HRESULT
    func DwmEnableBlurBehindWindow(hWnd: HWND, pBlurBehind: const *DWM_BLURBEHIND)->HRESULT
}
