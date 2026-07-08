#global public
#global #if #os == Swag.TargetOs.Windows
#foreignlib("dwmapi")
using Core, Win32

#[Swag.Foreign("dwmapi")]
{
    func DwmSetWindowAttribute(hWnd: HWND, dwAttribute: DWORD, pvAttribute: LPCVOID, cbAttribute: DWORD)->s32;
}

const DWMWA_WINDOW_CORNER_PREFERENCE = 33'u32
const DWMWA_BORDER_COLOR             = 34'u32
const DWMWA_COLOR_NONE               = 0xFFFFFFFE'u32

const DWMWCP_DONOTROUND = 1'u32
const DWMWCP_ROUND      = 2'u32
const HTCLIENT          = 1
const HTCAPTION         = 2
const HTLEFT            = 10
const HTRIGHT           = 11
const HTTOP             = 12
const HTTOPLEFT         = 13
const HTTOPRIGHT        = 14
const HTBOTTOM          = 15
const HTBOTTOMLEFT      = 16
const HTBOTTOMRIGHT     = 17

#[Swag.NoCopy]
struct NativeSurface
{
    hWnd:             HWND
    lastDeadChar:     WPARAM
    topMost:          bool
    trayIcon:         HICON
}

// Fixed notification-area icon id. A surface owns at most one tray icon.
const TrayIconID = 1

private func postSurfaceSysCommand(surface: *Surface, kind: SysCommandEvent.Kind)
{
    if surface.wnd.isPendingDestroy do
        return

    let evt = Event.create'SysCommandEvent()
    evt.kind = kind
    surface.wnd.view.postEvent(evt)
}

private func winProc(hWnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM)->LRESULT
{
    // Associate pointer to surface with 'hWnd'
    if msg == WM_CREATE
    {
        let lpcs = cast(*CREATESTRUCTW) cast(u64) lParam
        SetWindowLongPtrW(hWnd, GWLP_USERDATA, lpcs.lpCreateParams)
    }

    // Get 'Surface' pointer
    let surface = cast(*Surface) GetWindowLongPtrW(hWnd, GWLP_USERDATA)
    if surface
    {
        if msg >= WM_USER
        {
            var evt = SysUserEvent{}
            evt.userMsg = msg
            evt.param0  = wParam
            evt.param1  = lParam
            surface.wnd.view.sendEvent(&evt)
            return TRUE
        }

        switch msg
        {
        case WM_CLOSE:
            postSurfaceSysCommand(surface, .Close)
            return 0

        case WM_NCDESTROY:
            SetWindowLongPtrW(hWnd, GWLP_USERDATA, null)
            break

        case WM_SYSKEYDOWN, WM_SYSKEYUP, WM_SYSCHAR:
            return 0
        case WM_KEYDOWN, WM_KEYUP:
            return 0

        case WM_DEADCHAR:
            if (wParam == 27) do
                return 1
            if surface.lastDeadChar != wParam
            {
                surface.lastDeadChar = wParam
                break
            }

            fallthrough

        case WM_CHAR:
            if (wParam == 27) do
                return 1

            surface.lastDeadChar = 0

            let scanCode = cast(UINT) (lParam & 0xFF0000) >> 16
            let x        = MapVirtualKeyW(scanCode, MAPVK_VSC_TO_VK_EX)
            let y        = Input.Keyboard.virtualKeyToKey(x)

            surface.app.sendRuneEvent(y, cast(rune) wParam)
            return 0

        case WM_MOUSEWHEEL:
            let z = GET_WHEEL_DELTA_WPARAM(wParam) / WHEEL_DELTA
            surface.app.sendMouseWheelEvent(z)
            return 0
        case WM_SETCURSOR:
            return 0

        case WM_ACTIVATEAPP:
            surface.app.setActivated(wParam ? true : false)
            return 0

        case WM_ERASEBKGND:
            return 0
        case WM_NCPAINT:
            return 0
        case WM_NCCALCSIZE:
            return 0
        case WM_NCHITTEST:
            var pt = Math.Point{GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam)}
            surface.screenToSurface(&pt)

            if surface.wnd.hitTestCaptionButton(pt) do
                return HTCLIENT

            if !surface.isMaximized
            {
                let sizingBorder = surface.wnd.hitTestBorders(pt)
                switch sizingBorder
                {
                case Left | Top:
                    return HTTOPLEFT
                case Right | Top:
                    return HTTOPRIGHT
                case Left | Bottom:
                    return HTBOTTOMLEFT
                case Right | Bottom:
                    return HTBOTTOMRIGHT
                case Left:
                    return HTLEFT
                case Right:
                    return HTRIGHT
                case Top:
                    return HTTOP
                case Bottom:
                    return HTBOTTOM
                }
            }

            if surface.wnd.hitTestCaption(pt) do
                return HTCAPTION

            return HTCLIENT

        case WM_PAINT:
            var ps: PAINTSTRUCT
            discard BeginPaint(hWnd, &ps)
            surface.invalidate()
            surface.paint()
            EndPaint(hWnd, &ps)
            return 0

        case WM_WINDOWPOSCHANGING:
            return 0

        case WM_GETMINMAXINFO:
            let mm = cast(*MINMAXINFO) cast(u64) lParam

            // Enforce the surface min/max size during interactive (border-drag) resizing,
            // which is handled by the OS sizing loop and only honours the track sizes.
            if surface.minSize.x > 0 do
                mm.ptMinTrackSize.x = cast(s32) surface.minSize.x
            if surface.minSize.y > 0 do
                mm.ptMinTrackSize.y = cast(s32) surface.minSize.y
            if surface.maxSize.x > 0 do
                mm.ptMaxTrackSize.x = cast(s32) surface.maxSize.x
            if surface.maxSize.y > 0 do
                mm.ptMaxTrackSize.y = cast(s32) surface.maxSize.y

            var pt: POINT
            pt.x = cast(s32) surface.position.x
            pt.y = cast(s32) surface.position.y
            let hm = MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST)
            if hm != null
            {
                var info: MONITORINFO
                catch GetMonitorInfoA(hm, &info)
                let sdw = cast(s32) surface.app.theme.metrics.surfaceWnd_ShadowSize

                mm.ptMaxPosition.x = (info.rcWork.left - info.rcMonitor.left) - sdw
                mm.ptMaxPosition.y = (info.rcWork.top - info.rcMonitor.top) - sdw
                mm.ptMaxSize.x     = (info.rcWork.right - info.rcWork.left) + 2 * sdw
                mm.ptMaxSize.y     = (info.rcWork.bottom - info.rcWork.top) + 2 * sdw
            }

            return 0

        case WM_MOVE:
            // lParam holds the client origin in screen space as *signed* 16-bit coordinates.
            // A maximized window is positioned slightly off the work area (negative origin
            // because of the surface shadow), so a raw LOWORD/HIWORD would wrap to a huge
            // positive value and corrupt every screenToSurface() mouse mapping.
            surface.position.x = GET_X_LPARAM(lParam)
            surface.position.y = GET_Y_LPARAM(lParam)
        case WM_SIZE:
            surface.sendResizeEvent(cast(f32) LOWORD(lParam), cast(f32) HIWORD(lParam))

        case WM_SYSCOMMAND:
            switch wParam & 0xFFF0
            {
            case SC_MINIMIZE:
                postSurfaceSysCommand(surface, .Minimize)
                return 0
            case SC_MAXIMIZE:
                postSurfaceSysCommand(surface, .Maximize)
                return 0
            case SC_CLOSE:
                postSurfaceSysCommand(surface, .Close)
                return 0
            case SC_RESTORE:
                postSurfaceSysCommand(surface, .Restore)
                return 0
            }
        }
    }

    return DefWindowProcW(hWnd, msg, wParam, lParam)
}

private impl Surface
{
    mtd setFocus()
    {
        SetFocus(.hWnd)
    }

    // Creates a new (invisible) surface
    func createNative(app: *Application, result: *Surface, x, y, width, height: s32, flags: SurfaceFlags, mainSurface: *Surface) throw
    {
        // Create class
        #[Swag.Global]
        var doneClass: bool
        let className16   = Utf16.toZeroTerminated("Swag.Gui.Surface")
        let surfaceName16 = Utf16.toZeroTerminated(result.surfaceID)
        let className     = @dataof(className16)
        let surfaceName   = @dataof(surfaceName16)
        if !doneClass
        {
            doneClass = true

            var hIcon: HICON
            if app.appIcon.isValid() do
                hIcon = app.appIcon.toHICON()

            var wc: WNDCLASSW
            wc.hInstance     = GetModuleHandleW(null)
            wc.cbWndExtra    = #sizeof(*void)
            wc.style         = CS_OWNDC | CS_DBLCLKS | CS_HREDRAW | CS_VREDRAW
            wc.lpfnWndProc   = cast() &winProc
            wc.hCursor       = LoadCursorA(null, MAKEINTRESOURCEA(IDC_ARROW))
            wc.hIcon         = hIcon
            wc.lpszClassName = className
            try RegisterClassW(wc)
        }

        var winFlags = 0'u32
        winFlags |= WS_POPUP | WS_CLIPCHILDREN

        var winFlagsEx = 0'u32
        if flags & .Secondary do
            winFlagsEx |= WS_EX_TOOLWINDOW
        if flags & .TopMost
        {
            result.topMost = true
            winFlagsEx |= WS_EX_TOPMOST
        }

        // Create window
        result.hWnd = cast(const *void) CreateWindowExW(winFlagsEx, className, surfaceName, winFlags, x, y, width, height, null, null, GetModuleHandleW(null), result)

        result.applyNativeDwmStyle()

        result.rc = try app.renderer.native.createContext(result.hWnd, width, height, mainSurface ? mainSurface.rc.hRC : null)
    }

    mtd destroyNative()
    {
        if .app.renderer.headless do
            return

        if .trayIcon
        {
            var tnid: NOTIFYICONDATAA
            tnid.cbSize = #sizeof(NOTIFYICONDATAA)
            tnid.hWnd   = .hWnd
            tnid.uID    = TrayIconID
            catch Shell_NotifyIconA(NIM_DELETE, &tnid)
            catch DestroyIcon(.trayIcon)
            .trayIcon = null
        }

        catch DestroyWindow(.hWnd)
    }
}

impl Surface
{
    private mtd applyNativeDwmStyle()
    {
        var cornerPreference = .getCornerRadius() > 0 ? DWMWCP_ROUND : DWMWCP_DONOTROUND
        discard DwmSetWindowAttribute(.hWnd, DWMWA_WINDOW_CORNER_PREFERENCE, cast(LPCVOID) &cornerPreference, #sizeof(cornerPreference))

        var borderColor = DWMWA_COLOR_NONE
        discard DwmSetWindowAttribute(.hWnd, DWMWA_BORDER_COLOR, cast(LPCVOID) &borderColor, #sizeof(borderColor))
    }

    // Show 'icon' for this surface in the notification area (system tray), with an
    // optional tooltip. Mouse interactions are delivered to the surface as WM_USER
    // SysUserEvents whose 'param1' holds the raw mouse message (e.g. WM_RBUTTONDOWN
    // for a right-click); handle them in the surface view's onSysUserEvent. The icon
    // is removed automatically when the surface is destroyed.
    //
    // This uses the legacy (version 0) NOTIFYICON behaviour on purpose: the callback
    // carries the mouse message directly in 'lParam', which is what the window proc
    // forwards as 'param1'. NIM_SETVERSION/NOTIFYICON_VERSION_4 would change that
    // layout and is intentionally not used.
    mtd setTrayIcon(icon: Pixel.Image, tip: string = null)
    {
        var img   = icon
        .trayIcon = catch img.toHICON()

        var tnid: NOTIFYICONDATAA
        tnid.cbSize           = #sizeof(NOTIFYICONDATAA)
        tnid.hWnd             = .hWnd
        tnid.uID              = TrayIconID
        tnid.uFlags           = NIF_ICON | NIF_MESSAGE
        tnid.uCallbackMessage = WM_USER
        tnid.hIcon            = .trayIcon

        if tip
        {
            tnid.uFlags |= NIF_TIP
            let count = Math.min(@countof(tip), #sizeof(tnid.szTip) - 1)
            Memory.copy(&tnid.szTip[0], @dataof(tip), count)
        }

        catch Shell_NotifyIconA(NIM_ADD, &tnid)
    }

    mtd requestClose()
    {
        catch PostMessageW(.hWnd, WM_CLOSE, 0, 0)
    }

    mtd requestMinimize()
    {
        catch PostMessageW(.hWnd, WM_SYSCOMMAND, SC_MINIMIZE, 0)
    }

    mtd requestMaximize()
    {
        catch PostMessageW(.hWnd, WM_SYSCOMMAND, SC_MAXIMIZE, 0)
    }

    mtd requestRestore()
    {
        catch PostMessageW(.hWnd, WM_SYSCOMMAND, SC_RESTORE, 0)
    }

    mtd applyNativeSurfaceFlags()
    {
        if .app.renderer.headless do
            return

        var exStyle = cast(u64) GetWindowLongPtrA(.hWnd, GWL_EXSTYLE)
        if .flags & .Secondary do
            exStyle |= WS_EX_TOOLWINDOW
        else do
            exStyle &= ~WS_EX_TOOLWINDOW
        if .flags & .TopMost do
            exStyle |= WS_EX_TOPMOST
        else do
            exStyle &= ~WS_EX_TOPMOST
        SetWindowLongPtrA(.hWnd, GWL_EXSTYLE, cast(LONG_PTR) exStyle)
        .applyNativeDwmStyle()
    }

    // Send a custom message to the surface application with name 'surfaceID'
    func sendCustomMessage(surfaceID: string, id: u32, param: u64)->bool
    {
        let hwnd = Win32.FindWindowA(@dataof("Swag.Gui.Surface"), @dataof(surfaceID))
        if !hwnd do
            return false
        discard SendMessageA(hwnd, WM_USER + id, 0, param)
        return true
    }

    // Set the surface position
    mtd setPosition(pos: Math.Rectangle)
    {
        var clampPos = pos

        if .minSize.x > 0 do
            clampPos.width = Math.max(clampPos.width, .minSize.x)
        if .minSize.y > 0 do
            clampPos.height = Math.max(clampPos.height, .minSize.y)
        if .maxSize.x > 0 do
            clampPos.width = Math.min(clampPos.width, .maxSize.x)
        if .maxSize.y > 0 do
            clampPos.height = Math.min(clampPos.height, .maxSize.y)

        .position = clampPos
        if .app.renderer.headless
        {
            .sendResizeEvent(clampPos.width, clampPos.height)
            return
        }

        catch SetWindowPos(.hWnd, null, cast(s32) clampPos.x, cast(s32) clampPos.y, cast(s32) clampPos.width, cast(s32) clampPos.height, SWP_NOCOPYBITS | SWP_DEFERERASE | SWP_NOREDRAW | SWP_NOSENDCHANGING)
    }

    // Set the window as a topmost window (above all non topmost)
    mtd setTopMost()
    {
        if .app.renderer.headless
        {
            .topMost = true
            return
        }

        catch SetWindowPos(.hWnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)
        .topMost = true
    }

    mtd isTopMost()->bool
    {
        return .topMost
    }

    // Bring the surface at the top of the Z order
    mtd bringToTop()
    {
        if .app.renderer.headless do
            return

        BringWindowToTop(.hWnd)
    }

    // Enable the surface
    mtd enable()
    {
        if !.isDisabled do
            return
        .isDisabled = false
        if .app.renderer.headless
        {
            .invalidate()
            return
        }

        EnableWindow(.hWnd, TRUE)
    }

    // Enable the surface
    mtd disable()
    {
        if .isDisabled do
            return
        .isDisabled = true
        if .app.renderer.headless
        {
            .invalidate()
            return
        }

        EnableWindow(.hWnd, FALSE)
    }

    // Show the surface
    mtd show()
    {
        if !.isHidden do
            return

        .isHidden = false

        // First-show initialization stage. Runs while the window is still hidden,
        // so the application can perform slow setup (restoring state, loading
        // content, resizing the surface, ...). The window is only made visible
        // afterwards, once a first frame has been rendered.
        if !.isInitialized
        {
            .isInitialized = true
            .wnd.view.sendStateEvent(.Init)
        }

        .invalidate()
        .wnd.applyLayout({.position.width, .position.height})

        // Render the first complete frame into the back buffer *before* the window
        // becomes visible. Otherwise ShowWindow composites the still-empty (black)
        // GL surface, and the user sees a black flash until the first runFrame()
        // paint completes (which is slow on the first frame because of the lazy
        // font/glyph generation it triggers). Painting while still hidden means the
        // window appears already showing correct content.
        .paint()

        if .app.renderer.headless
        {
            let curFocus = .wnd.view.getFocus()
            if !curFocus or !.wnd.isParentOf(curFocus) do
                .wnd.view.setFocus()
            .wnd.view.sendStateEvent(.Show)
            return
        }

        ShowWindow(.hWnd, SW_SHOW)
        .applyNativeDwmStyle()

        let curFocus = .wnd.view.getFocus()
        if !curFocus or !.wnd.isParentOf(curFocus) do
            .wnd.view.setFocus()
        SetActiveWindow(.hWnd)
        SetFocus(.hWnd)

        .wnd.view.sendStateEvent(.Show)
    }

    // Hide the surface
    mtd hide()
    {
        if .isHidden do
            return
        .isHidden = true

        if .app.renderer.headless
        {
            .wnd.view.sendStateEvent(.Hide)
            return
        }

        ShowWindow(.hWnd, SW_HIDE)
        .wnd.view.sendStateEvent(.Hide)
    }

    // Show the surface as maximized
    mtd showMaximized()
    {
        if .isMaximized do
            return
        .isMaximized          = true
        .isMinimized          = false
        .positionNotMaximized = .position
        if .app.renderer.headless
        {
            .invalidate()
            return
        }

        .applyNativeDwmStyle()
        ShowWindow(.hWnd, SW_SHOWMAXIMIZED)
    }

    // Show the surface in its default state
    mtd showNormal()
    {
        if !.isMaximized and !.isMinimized do
            return
        .isMaximized = false
        .isMinimized = false
        if .app.renderer.headless
        {
            .setPosition(.positionNotMaximized)
            .invalidate()
            return
        }

        .applyNativeDwmStyle()
        ShowWindow(.hWnd, SW_RESTORE)
    }

    // Show the surface as minimized
    mtd showMinimized()
    {
        if .isMinimized do
            return
        .isMinimized = true
        if .app.renderer.headless
        {
            .invalidate()
            return
        }

        ShowWindow(.hWnd, SW_SHOWMINIMIZED)
    }

    // Transform a point in screen space relative to the surface
    mtd screenToSurface(pt: *Math.Point)
    {
        if .app.renderer.headless
        {
            pt.x -= .position.x
            pt.y -= .position.y
            return
        }

        var wpt = POINT{cast(s32) pt.x, cast(s32) pt.y}
        ScreenToClient(.hWnd, &wpt)
        pt.x = wpt.x
        pt.y = wpt.y
    }

    // Transform a point relative to the surface in screen space
    mtd surfaceToScreen(pt: *Math.Point)
    {
        if .app.renderer.headless
        {
            pt.x += .position.x
            pt.y += .position.y
            return
        }

        var wpt = POINT{cast(s32) pt.x, cast(s32) pt.y}
        ClientToScreen(.hWnd, &wpt)
        pt.x = wpt.x
        pt.y = wpt.y
    }
}
