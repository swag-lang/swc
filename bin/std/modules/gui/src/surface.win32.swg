#global public
#global if #os == Swag.TargetOs.Windows

#foreignlib("dwmapi")
using Core, Win32

private #[Swag.Foreign("dwmapi")]
{
    // Performs the dwm set window attribute operation.
    func DwmSetWindowAttribute(hWnd: HWND, dwAttribute: DWORD, pvAttribute: LPCVOID, cbAttribute: DWORD)->s32
}

// Defines dwmwa window corner preference.
private const DWMWA_WINDOW_CORNER_PREFERENCE = 33'u32

// Defines dwmwa border color.
private const DWMWA_BORDER_COLOR = 34'u32

// Defines dwmwa color none.
private const DWMWA_COLOR_NONE = 0xFFFFFFFE'u32

// Defines dwmwcp donotround.
private const DWMWCP_DONOTROUND = 1'u32

// Defines dwmwcp round.
private const DWMWCP_ROUND = 2'u32

// Defines htclient.
private const HTCLIENT = 1

// Defines htcaption.
private const HTCAPTION = 2

// Defines htleft.
private const HTLEFT = 10

// Defines htright.
private const HTRIGHT = 11

// Defines httop.
private const HTTOP = 12

// Defines httopleft.
private const HTTOPLEFT = 13

// Defines httopright.
private const HTTOPRIGHT = 14

// Defines htbottom.
private const HTBOTTOM = 15

// Defines htbottomleft.
private const HTBOTTOMLEFT = 16

// Defines htbottomright.
private const HTBOTTOMRIGHT = 17

// Dependency-visible Windows storage embedded by `Surface`.
#[Swag.Opaque, Swag.NoDoc]
#[Swag.NoCopy]
struct NativeSurface
{
    hWnd:         HWND       // H wnd associated with this value.
    lastDeadChar: WPARAM     // Last dead char associated with this value.
    topMost:      bool       // Top most associated with this value.
    trayIcon:     HICON      // Tray icon associated with this value.
}

// Fixed notification-area icon id. A surface owns at most one tray icon.
private const TrayIconID = 1

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
        let lpcs = cast(*CREATESTRUCTW) cast #bit (u64) lParam
        SetWindowLongPtrW(hWnd, GWLP_USERDATA, cast #bit (LONG_PTR) cast(u64) lpcs.lpCreateParams)
    }

    // Get 'Surface' pointer
    let surface = cast(#null *Surface) cast #bit (u64) GetWindowLongPtrW(hWnd, GWLP_USERDATA)
    if surface
    {
        if msg >= WM_USER
        {
            var evt = SysUserEvent{}
            evt.message = msg
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
            SetWindowLongPtrW(hWnd, GWLP_USERDATA, 0)
            break

        case WM_SYSKEYDOWN, WM_SYSKEYUP, WM_SYSCHAR:
            return 0

        case WM_KEYDOWN, WM_KEYUP:
            return 0

        case WM_DEADCHAR:
            if wParam == 27 do
                return 1
            if surface.lastDeadChar != wParam
            {
                surface.lastDeadChar = wParam
                break
            }

            fallthrough

        case WM_CHAR:
            if wParam == 27 do
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
                case Left | Top:     return HTTOPLEFT
                case Right | Top:    return HTTOPRIGHT
                case Left | Bottom:  return HTBOTTOMLEFT
                case Right | Bottom: return HTBOTTOMRIGHT
                case .Left:          return HTLEFT
                case .Right:         return HTRIGHT
                case .Top:           return HTTOP
                case .Bottom:        return HTBOTTOM
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
            let mm = cast(*MINMAXINFO) cast #bit (u64) lParam

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
    func createNative(app: *Application, result: *Surface, x, y, width, height: s32, flags: SurfaceFlags) fail
    {
        // Create class
        #[Swag.Global]
        var doneClass: bool
        let className16   = Utf16.toZeroTerminated("Swag.Gui.Surface")
        let surfaceName16 = Utf16.toZeroTerminated(result.surfaceId)
        let className     = @dataof(className16)
        let surfaceName   = @dataof(surfaceName16)
        if !doneClass
        {
            doneClass = true

            var hIcon: HICON
            if app.appIcon.isValid() do
                hIcon = app.appIcon.toHicon()

            var wc: WNDCLASSW
            wc.hInstance     = GetModuleHandleW(null)
            wc.cbWndExtra    = #sizeof(#null *void)
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
        if flags & .ToolWindow do
            winFlagsEx |= WS_EX_TOOLWINDOW
        if flags & .TopMost
        {
            result.topMost = true
            winFlagsEx     |= WS_EX_TOPMOST
        }

        // Create window
        result.hWnd = cast(#null const *void) CreateWindowExW(winFlagsEx, className, surfaceName, winFlags, x, y, width, height, null, null, GetModuleHandleW(null), result)
        if !result.hWnd do
            failWinError(GetLastError())

        result.applyNativeDwmStyle()
    }

    mtd destroyNative()
    {
        .destroyRendering()
        if !.hWnd do
            return

        .removeTrayIcon()
        catch DestroyWindow(.hWnd)
        .hWnd = null
    }
}

impl Surface
{
    internal mtd const nativeRenderHandle()->#null const *void => cast(#null const *void) .hWnd

    // Returns the Win32 window handle owned by this surface.
    mtd const win32Handle()->HWND => .hWnd

    private mtd applyNativeDwmStyle()
    {
        var cornerPreference = .cornerRadius() > 0 ? DWMWCP_ROUND : DWMWCP_DONOTROUND
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
    mtd setTrayIcon(icon: Pixel.Image, tip: #null string = null)
    {
        if !.app.renderer.needsNativeWindow() do
            return

        var img     = icon
        let newIcon = catch img.toHicon()
        if !newIcon do
            return

        .removeTrayIcon()
        .trayIcon = newIcon

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

    // Removes the notification-area icon owned by this surface, if any.
    mtd removeTrayIcon()
    {
        if !.trayIcon do
            return

        if .app.renderer.needsNativeWindow()
        {
            var tnid: NOTIFYICONDATAA
            tnid.cbSize = #sizeof(NOTIFYICONDATAA)
            tnid.hWnd   = .hWnd
            tnid.uID    = TrayIconID
            catch Shell_NotifyIconA(NIM_DELETE, &tnid)
        }

        catch DestroyIcon(.trayIcon)
        .trayIcon = null
    }

    // Requests a close through the regular system-command event path.
    mtd requestClose()
    {
        if !.app.renderer.needsNativeWindow()
        {
            postSurfaceSysCommand(me, .Close)
            return
        }

        catch PostMessageW(.hWnd, WM_CLOSE, 0, 0)
    }

    // Requests minimization through the regular system-command event path.
    mtd requestMinimize()
    {
        if !.app.renderer.needsNativeWindow()
        {
            postSurfaceSysCommand(me, .Minimize)
            return
        }

        catch PostMessageW(.hWnd, WM_SYSCOMMAND, SC_MINIMIZE, 0)
    }

    // Requests maximization through the regular system-command event path.
    mtd requestMaximize()
    {
        if !.app.renderer.needsNativeWindow()
        {
            postSurfaceSysCommand(me, .Maximize)
            return
        }

        catch PostMessageW(.hWnd, WM_SYSCOMMAND, SC_MAXIMIZE, 0)
    }

    // Requests restoration through the regular system-command event path.
    mtd requestRestore()
    {
        if !.app.renderer.needsNativeWindow()
        {
            postSurfaceSysCommand(me, .Restore)
            return
        }

        catch PostMessageW(.hWnd, WM_SYSCOMMAND, SC_RESTORE, 0)
    }

    internal mtd applyNativeSurfaceFlags()
    {
        let shouldBeTopMost = .flags.has(.TopMost)
        .topMost = shouldBeTopMost

        if !.app.renderer.needsNativeWindow() or !.hWnd do
            return

        var exStyle = cast #bit (u64) GetWindowLongPtrA(.hWnd, GWL_EXSTYLE)
        if .flags & .ToolWindow do
            exStyle |= WS_EX_TOOLWINDOW
        else do
            exStyle &= ~WS_EX_TOOLWINDOW
        if .flags & .TopMost do
            exStyle |= WS_EX_TOPMOST
        else do
            exStyle &= ~WS_EX_TOPMOST
        SetWindowLongPtrA(.hWnd, GWL_EXSTYLE, cast #bit (LONG_PTR) exStyle)
        catch SetWindowPos(.hWnd, shouldBeTopMost ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)
        .applyNativeDwmStyle()
    }

    // Send a custom message to the surface application with name 'surfaceId'
    func sendCustomMessage(surfaceId: string, id: u32, param: u64)->bool
    {
        let hwnd = Win32.FindWindowA(@dataof("Swag.Gui.Surface"), @dataof(surfaceId))
        if !hwnd do
            return false
        discard SendMessageA(hwnd, WM_USER + id, 0, param)
        return true
    }

    // Sets the surface bounds in screen coordinates, clamped to [[Gui.Surface.minSize]] and [[Gui.Surface.maxSize]].
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
        if !.app.renderer.needsNativeWindow()
        {
            .sendResizeEvent(clampPos.width, clampPos.height)
            return
        }

        catch SetWindowPos(.hWnd, null, cast(s32) clampPos.x, cast(s32) clampPos.y, cast(s32) clampPos.width, cast(s32) clampPos.height, SWP_NOCOPYBITS | SWP_DEFERERASE | SWP_NOREDRAW | SWP_NOSENDCHANGING)
    }

    // Enables or disables placement above all non-topmost windows.
    mtd setTopMost(enabled = true)
    {
        if enabled do
            .flags.add(.TopMost)
        else do
            .flags.remove(.TopMost)
        .applyNativeSurfaceFlags()
    }

    // Returns whether the surface belongs to the topmost Z-order group.
    mtd const isTopMost()->bool
    {
        return .topMost
    }

    // Brings the surface to the front of its current Z-order group.
    mtd bringToFront()
    {
        if !.app.renderer.needsNativeWindow() do
            return

        BringWindowToTop(.hWnd)
    }

    // Enables input for the surface.
    mtd enable()
    {
        if !.isDisabled do
            return
        .isDisabled = false
        if !.app.renderer.needsNativeWindow()
        {
            .invalidate()
            return
        }

        EnableWindow(.hWnd, TRUE)
    }

    // Disables input for the surface.
    mtd disable()
    {
        if .isDisabled do
            return
        .isDisabled = true
        if !.app.renderer.needsNativeWindow()
        {
            .invalidate()
            return
        }

        EnableWindow(.hWnd, FALSE)
    }

    // Shows the surface and emits its one-time initialization event when needed.
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

        if !.app.renderer.needsNativeWindow()
        {
            let curFocus = .wnd.view.focusedWindow()
            if !curFocus or !.wnd.isAncestorOf(curFocus) do
                .wnd.view.setFocus()
            .wnd.view.sendStateEvent(.Show)
            return
        }

        ShowWindow(.hWnd, SW_SHOW)
        .applyNativeDwmStyle()

        let curFocus = .wnd.view.focusedWindow()
        if !curFocus or !.wnd.isAncestorOf(curFocus) do
            .wnd.view.setFocus()
        SetActiveWindow(.hWnd)
        SetFocus(.hWnd)

        .wnd.view.sendStateEvent(.Show)
    }

    // Hides the surface without destroying it.
    mtd hide()
    {
        if .isHidden do
            return
        .isHidden = true

        if !.app.renderer.needsNativeWindow()
        {
            .wnd.view.sendStateEvent(.Hide)
            return
        }

        ShowWindow(.hWnd, SW_HIDE)
        .wnd.view.sendStateEvent(.Hide)
    }

    // Shows the surface maximized and preserves its previous bounds for restoration.
    mtd showMaximized()
    {
        if .isMaximized do
            return
        .isMaximized      = true
        .isMinimized      = false
        .restoredPosition = .position
        if !.app.renderer.needsNativeWindow()
        {
            .invalidate()
            return
        }

        .applyNativeDwmStyle()
        ShowWindow(.hWnd, SW_SHOWMAXIMIZED)
    }

    // Restores a minimized or maximized surface to its normal bounds.
    mtd showNormal()
    {
        if !.isMaximized and !.isMinimized do
            return
        .isMaximized = false
        .isMinimized = false
        if !.app.renderer.needsNativeWindow()
        {
            .setPosition(.restoredPosition)
            .invalidate()
            return
        }

        .applyNativeDwmStyle()
        ShowWindow(.hWnd, SW_RESTORE)
    }

    // Shows the surface minimized.
    mtd showMinimized()
    {
        if .isMinimized do
            return
        .isMinimized = true
        if !.app.renderer.needsNativeWindow()
        {
            .invalidate()
            return
        }

        ShowWindow(.hWnd, SW_SHOWMINIMIZED)
    }

    // Converts `pt` in place from screen coordinates to surface coordinates.
    mtd screenToSurface(pt: *Math.Point)
    {
        if !.app.renderer.needsNativeWindow()
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

    // Converts `pt` in place from surface coordinates to screen coordinates.
    mtd surfaceToScreen(pt: *Math.Point)
    {
        if !.app.renderer.needsNativeWindow()
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
