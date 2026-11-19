#global public
#global if #os == Swag.TargetOs.Windows

using Core, Win32, Win32.Gdi32, Ogl

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

// WM_SIZE state emitted when a native window has no drawable client area.
private const SizeMinimized = 1'u64

// Native timer that keeps the application clock running inside the desktop's move and size loop.
private const DesktopLoopTimerId = 1'u64

// Period of that timer. USER32 raises anything shorter to its own minimum of ten milliseconds.
private const DesktopLoopTimerPeriod = 10'u32

// Windows storage embedded by `Surface`.
#[Swag.Opaque]
#[Swag.NoCopy]
internal struct NativeSurface
{
    public
    {
        hWnd:         HWND       // Native window handle, or `null` before creation and after destruction.
        lastDeadChar: WPARAM     // Dead key waiting to combine with the next character, or zero.
        topMost:      bool       // Whether the native window is in the topmost Z-order group.
        trayIcon:     HICON      // Notification-area icon owned by the surface, or `null`.

        // Whether an application-initiated SetWindowPos is in flight. A programmatic
        // placement is already expressed in the target monitor's physical pixels, so the
        // WM_DPICHANGED it triggers when crossing a DPI boundary must update the scale
        // without adopting the OS-suggested rectangle (which assumes an old-DPI size).
        inAppPlacement: bool

        dropTarget:       SurfaceDropTarget     // OLE drop target of this window, owned by it.
        dropTargetActive: bool     // Whether that target is registered with OLE.
    }

    // Whether the desktop loop timer is armed for this window.
    inDesktopLoop:    bool
    trayIconVersion4: bool     // The Shell callback layout selected for this icon.
    trayImage:        Pixel.Image
    trayTip:          String

    // First-show setup can restore several placements before its content is ready to paint.
    initializing: bool

    // The desktop can deliver several sizes before the next application clock frame.
    clientResizePending: bool
    clientLayoutScale:   f32

    inDiscretePlacement:  bool
    presentingPlacement:  bool
    placementOrigin:      POINT

    presentationDC:     HDC
    presentationBitmap: HBITMAP
    presentationPixels: *u8?
    presentationWidth:  s32
    presentationHeight: s32
    presentedTinted:    bool
}

// Fixed notification-area icon id. A surface owns at most one tray icon.
private const TrayIconID       = 1
private const TrayIconVersion4 = 4
private const NIN_KEYSELECT    = WM_USER + 1
private var g_TaskbarCreated: u32

// Decodes the callback layout chosen with NIM_SETVERSION. The modern Shell reports the icon id
// in the high word of lParam and uses WM_CONTEXTMENU for keyboard context-menu requests.
internal impl Surface
{
    mtd trayActionForNotification(wParam: WPARAM, lParam: LPARAM)->SysUserEvent.TrayAction
    {
        var message = cast(u32, lParam)
        if .native.trayIconVersion4
        {
            if message >> 16 != TrayIconID do
                return .None
            message &= 0xFFFF
            switch message
            {
            case WM_CONTEXTMENU: return .ContextMenu
            case WM_LBUTTONDBLCLK, NIN_KEYSELECT: return .Activate
            }
        }
        elif wParam == TrayIconID
        {
            switch message
            {
            case WM_RBUTTONUP:     return .ContextMenu
            case WM_LBUTTONDBLCLK: return .Activate
            }
        }

        return .None
    }
}

private impl Surface
{
    // Keeps the application clock running while the desktop owns the message loop.
    //
    // Moving or sizing the window by its frame runs USER32's own loop until the button is
    // released, and the application loop waits behind it. That loop still dispatches timer
    // messages, so a native timer is what reaches the application in the meantime.
    mtd enterDesktopLoop()
    {
        .inDesktopLoop = true
        discard SetTimer(.hWnd, DesktopLoopTimerId, DesktopLoopTimerPeriod, null)
    }

    mtd exitDesktopLoop()
    {
        if not .inDesktopLoop do
            return
        .inDesktopLoop = false
        discard KillTimer(.hWnd, DesktopLoopTimerId)
    }
}

private func postSurfaceSysCommand(surface: *Surface, kind: SysCommandEvent.Kind)
{
    if surface.wnd.isPendingDestroy do
        return

    let evt = Event.create'SysCommandEvent()
    evt.kind = kind
    surface.wnd.view.postEvent(evt)
}

#[Swag.CallingConvention(.C)]
private func winProc(hWnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM)->LRESULT
{
    // Associate pointer to surface with 'hWnd'
    if msg == WM_CREATE
    {
        let lpcs = cast(*CREATESTRUCTW, cast #bit (u64, lParam))
        SetWindowLongPtrW(hWnd, GWLP_USERDATA, cast #bit (LONG_PTR, cast(u64, lpcs.lpCreateParams)))
    }

    // Get 'Surface' pointer
    let surface = cast(*Surface?, cast #bit (u64, GetWindowLongPtrW(hWnd, GWLP_USERDATA)))
    if surface
    {
        if g_TaskbarCreated != 0 and msg == g_TaskbarCreated
        {
            if surface.trayIcon
            {
                // Replacement writes these fields; own snapshots before borrowing them
                // as call arguments during a Shell restart.
                let icon = surface.native.trayImage
                let tip  = surface.native.trayTip
                surface.setTrayIcon(icon, tip)
            }

            return TRUE
        }

        if msg == WM_USER
        {
            let action = surface.trayActionForNotification(wParam, lParam)
            if action != .None
            {
                let evt = Event.create'SysUserEvent()
                evt.kind       = .TrayIcon
                evt.trayAction = action

                // The Shell must finish its input and foreground transitions before the
                // application shows a panel or editor window in response.
                surface.wnd.view.postEvent(evt)
            }

            return TRUE
        }

        if msg >= WM_APP
        {
            var evt = SysUserEvent{}
            evt.kind      = .CustomMessage
            evt.messageId = msg - WM_APP
            evt.param     = lParam
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
            discard RemovePropW(hWnd, Surface.identityProperty(surface.surfaceId).buffer)
            break

        case WM_SYSKEYDOWN, WM_SYSKEYUP:
            return 0

        case WM_SYSCHAR:
            let scanCode  = cast(UINT, (lParam & 0xFF0000)) >> 16
            let x         = MapVirtualKeyW(scanCode, MAPVK_VSC_TO_VK_EX)
            let key       = Input.Keyboard.virtualKeyToKey(x)
            let modifiers = surface.app.keyboard.pressedModifiers() | Input.KeyModifiers.Alt
            surface.app.sendRuneEvent(key, cast(rune, wParam), modifiers)
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

            let scanCode = cast(UINT, (lParam & 0xFF0000)) >> 16
            let x        = MapVirtualKeyW(scanCode, MAPVK_VSC_TO_VK_EX)
            let y        = Input.Keyboard.virtualKeyToKey(x)

            surface.app.sendRuneEvent(y, cast(rune, wParam))
            return 0

        case WM_MOUSEWHEEL:
            let z = GET_WHEEL_DELTA_WPARAM(wParam) / WHEEL_DELTA
            surface.app.sendMouseWheelEvent(surface, Math.Point{GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam)}, z)
            return 0

        case WM_SETCURSOR:
            return 0

        case WM_ACTIVATEAPP:
            surface.app.setActivated(wParam ? true : false)
            return 0

        case WM_KILLFOCUS:
            if not surface.app.nativeFocusTransition do
                surface.loseKeyboardFocus()
            return 0

        case WM_SETFOCUS:
            if not surface.app.nativeFocusTransition do
                discard surface.restoreFocus()
            return 0

        case WM_SETTINGCHANGE:
            surface.app.refreshSystemMotionPreference()
            surface.app.refreshSystemAppearance()
            return 0

        case WM_INPUTLANGCHANGE:
            surface.app.notifyKeyboardLayoutChanged(surface.wnd)
            break

        case WM_ERASEBKGND:
            return 0

        case WM_NCPAINT:
            return 0

        case WM_NCCALCSIZE:
            if wParam and surface.inDiscretePlacement
            {
                let params = cast(const *NCCALCSIZE_PARAMS, cast #bit (u64, lParam))
                surface.presentDiscretePlacement(params.rgrc[0])
            }
            return 0

        case WM_NCHITTEST:
            var pt = Math.Point{GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam)}
            surface.screenToSurface(&pt)

            if surface.wnd.hitTestCaptionButton(pt) do
                return HTCLIENT

            if not surface.isMaximized
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
            if not surface.initializing and not surface.inDiscretePlacement do
                surface.invalidatePhysicalRect(Math.Rectangle{cast(f32, ps.rcPaint.left), cast(f32, ps.rcPaint.top), cast(f32, (ps.rcPaint.right - ps.rcPaint.left)), cast(f32, (ps.rcPaint.bottom - ps.rcPaint.top))})
            EndPaint(hWnd, &ps)

            // Publish from the application clock, including its timer inside USER32's
            // sizing loop. Several native size messages can share one paint and transfer.
            return 0

        case WM_NCRBUTTONDOWN:
            surface.app.notifyPressedElsewhere()
            break

        case WM_NCLBUTTONDOWN:

            // The system takes this press for itself, so no window hears it as a click.
            surface.app.notifyPressedElsewhere()

            // A press on the caption or a border runs USER32's move or size loop inside
            // DefWindowProc. The window does not hear of it until the pointer has actually
            // moved, so the clock is armed from the press and runs until the loop returns.
            surface.enterDesktopLoop()
            let result = DefWindowProcW(hWnd, msg, wParam, lParam)
            surface.exitDesktopLoop()
            return result

        case WM_TIMER:
            if wParam != DesktopLoopTimerId do
                break
            if surface.inDesktopLoop do
                surface.app.runClockFrame()
            return 0

        case WM_ENTERSIZEMOVE:
            surface.enterDesktopLoop()
            return 0

        case WM_EXITSIZEMOVE:
            surface.exitDesktopLoop()

            // The next ordinary frame applies the last size and any deferred control reflow.
            if surface.isSizing
            {
                surface.setSizing(false)
                surface.invalidate()
            }

            return 0

        case WM_WINDOWPOSCHANGING:

            // Placement restoration may maximize or restore the HWND inside Init. Keep the
            // final geometry and native show state, but expose it only after show paints it.
            if surface.initializing
            {
                let next = cast(*WINDOWPOS, cast #bit (u64, lParam))
                next.flags &= ~SWP_SHOWWINDOW
            }

            return 0

        case WM_GETMINMAXINFO:
            let mm = cast(*MINMAXINFO, cast #bit (u64, lParam))

            // Enforce the surface min/max size during interactive (border-drag) resizing,
            // which is handled by the OS sizing loop and only honours the track sizes.
            // Track sizes are physical pixels; the surface limits are logical.
            if surface.minSize.x > 0 do
                mm.ptMinTrackSize.x = cast(s32, (surface.minSize.x * surface.dpiScale))
            if surface.minSize.y > 0 do
                mm.ptMinTrackSize.y = cast(s32, (surface.minSize.y * surface.dpiScale))
            if surface.maxSize.x > 0 do
                mm.ptMaxTrackSize.x = cast(s32, (surface.maxSize.x * surface.dpiScale))
            if surface.maxSize.y > 0 do
                mm.ptMaxTrackSize.y = cast(s32, (surface.maxSize.y * surface.dpiScale))

            var pt: POINT
            pt.x = cast(s32, surface.position.x)
            pt.y = cast(s32, surface.position.y)
            let hm = MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST)
            if hm != null
            {
                var info: MONITORINFO
                catch GetMonitorInfoA(hm, &info)
                let sdw = cast(s32, (surface.shadowMargin() * surface.dpiScale))

                mm.ptMaxPosition.x = (info.rcWork.left - info.rcMonitor.left) - sdw
                mm.ptMaxPosition.y = (info.rcWork.top - info.rcMonitor.top) - sdw
                mm.ptMaxSize.x     = (info.rcWork.right - info.rcWork.left) + 2 * sdw
                mm.ptMaxSize.y     = (info.rcWork.bottom - info.rcWork.top) + 2 * sdw
            }

            return 0

        case WM_DPICHANGED:

            // The window reached a monitor with another scale, or the user changed
            // the display scale.
            surface.setDpiScaleRaw(cast(f32, LOWORD(wParam)) / cast(f32, USER_DEFAULT_SCREEN_DPI))

            // An application-initiated placement is already sized in the target
            // monitor's physical pixels: adopting the OS suggestion (which scales
            // the rectangle by newDpi/oldDpi, assuming an old-DPI size) would
            // double-scale it. Keep the requested rectangle and relayout at the new scale.
            surface.clientResizePending = true
            if surface.inAppPlacement or surface.inDiscretePlacement do
                return 0

            // An interactive move adopts the suggested physical rectangle. The next
            // resize or frame lays out the tree at that committed size and scale.
            let suggested = cast(const *RECT, cast #bit (u64, lParam))
            catch SetWindowPos(hWnd, null, suggested.left, suggested.top, suggested.right - suggested.left, suggested.bottom - suggested.top, SWP_NOZORDER | SWP_NOACTIVATE)
            return 0

        case WM_MOVE:

            // Windows moves a minimized HWND to its icon position. Keep the last window bounds
            // for restoration and for choosing the monitor when it is maximized again.
            if surface.isMinimized do
                return 0

            // lParam holds the client origin in screen space as *signed* 16-bit coordinates.
            // A maximized window is positioned slightly off the work area (negative origin
            // because of the surface shadow), so a raw LOWORD/HIWORD would wrap to a huge
            // positive value and corrupt every screenToSurface() mouse mapping.
            surface.position.x = GET_X_LPARAM(lParam)
            surface.position.y = GET_Y_LPARAM(lParam)

        case WM_SIZE:

            // Keep the last arranged tree while the native client has no drawable.
            if wParam == SizeMinimized
            {
                surface.clientResizePending = false
                surface.presentedFrame      = false
                return 0
            }

            surface.clientResizePending = true
            if surface.inDiscretePlacement do
                return 0
            if surface.inDesktopLoop
            {
                let width  = cast(s32, LOWORD(lParam))
                let height = cast(s32, HIWORD(lParam))
                if width != surface.rc.width or height != surface.rc.height do
                    surface.setSizing(true)
            }
            else do
                surface.applyPendingNativeResize()

            return 0

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
    internal mtd setFocus()
    {
        SetFocus(.hWnd)
    }

    // Creates the hidden native window of a surface.
    //
    // `width` and `height` are logical units; the created window is sized in the
    // physical pixels of the monitor it appears on.
    func createNative(app: *Application, result: *Surface, x, y, width, height: s32, flags: SurfaceFlags) fail
    {
        // The first native window of the process decides its DPI awareness, so opt
        // in before any window class or window exists.
        Env.enableDpiAwareness()

        // Create class
        global var doneClass: bool
        let className16   = Utf16.toZeroTerminated("Swag.Gui.Surface")
        let surfaceName16 = Utf16.toZeroTerminated(result.surfaceId)
        let className     = className16.buffer
        let surfaceName   = surfaceName16.buffer
        if not doneClass
        {
            doneClass = true

            var hIcon: HICON
            if app.appIcon.isValid() do
                hIcon = try app.appIcon.toHicon()

            var wc: WNDCLASSW
            wc.hInstance     = GetModuleHandleW(null)
            wc.cbWndExtra    = #sizeof(*void?)
            wc.style         = CS_DBLCLKS
            wc.lpfnWndProc   = cast(&winProc)
            wc.hCursor       = LoadCursorA(null, MAKEINTRESOURCEA(IDC_ARROW))
            wc.hIcon         = hIcon
            wc.lpszClassName = className
            try RegisterClassW(wc)
        }

        var winFlags = 0'u32
        winFlags |= WS_POPUP | WS_CLIPCHILDREN

        // A layered window receives premultiplied pixels from a fixed offscreen OpenGL
        // drawable. Resizing the HWND then leaves the driver's drawable allocations alone.
        var winFlagsEx = WS_EX_LAYERED
        if flags & .ToolWindow do
            winFlagsEx |= WS_EX_TOOLWINDOW
        if flags & .TopMost
        {
            result.topMost = true
            winFlagsEx     |= WS_EX_TOPMOST
        }

        // Create window
        result.hWnd = cast(const *void?, CreateWindowExW(winFlagsEx, className, surfaceName, winFlags, x, y, width, height, null, null, GetModuleHandleW(null), result))
        if not result.hWnd do
            try failWinError(GetLastError())

        // The identity lives on a property, so the native title is free to follow the title.
        discard SetPropW(result.hWnd, identityProperty(result.surfaceId).buffer, cast(HANDLE, result.hWnd))

        // The window now knows its monitor: resolve the scale and resize the still
        // hidden window from logical units to physical pixels.
        result.dpiScale = cast(f32, GetDpiForWindow(result.hWnd)) / cast(f32, USER_DEFAULT_SCREEN_DPI)
        if result.dpiScale != 1
        {
            let physWidth  = cast(s32, Math.round(width * result.dpiScale))
            let physHeight = cast(s32, Math.round(height * result.dpiScale))
            result.inAppPlacement = true
            defer result.inAppPlacement = false
            catch SetWindowPos(result.hWnd, null, 0, 0, physWidth, physHeight, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOSENDCHANGING)
        }

        result.applyNativeDwmStyle()
        result.registerDropTarget()
    }

    internal mtd destroyNative()
    {
        .destroyRendering()
        .releasePresentationBitmap()
        if not .hWnd do
            return

        .revokeDropTarget()
        .removeTrayIcon()
        catch DestroyWindow(.hWnd)
        .hWnd = null
    }
}

impl Surface
{
    private mtd const canPresentPlacement()->bool =>
        not .isHidden and not .initializing and not .isMinimized and not .wnd.isPendingDestroy and not .inDesktopLoop

    private mtd presentDiscretePlacement(bounds: RECT)
    {
        // A layered update can reenter WM_NCCALCSIZE. The enclosing placement owns the frame.
        if .presentingPlacement or not .canPresentPlacement() do
            return

        let width  = bounds.right - bounds.left
        let height = bounds.bottom - bounds.top
        if width <= 0 or height <= 0 do
            return

        let destination = Math.Rectangle{cast(f32, bounds.left), cast(f32, bounds.top), cast(f32, width), cast(f32, height)}
        let scale       = Env.monitorForRectangle(destination).scaleFactor
        if .presentedFrame and not .isDirty and destination == .position and scale == .clientLayoutScale do
            return

        .placementOrigin     = {bounds.left, bounds.top}
        .presentingPlacement = true
        defer .presentingPlacement = false
        .position.x = destination.x
        .position.y = destination.y
        if scale != .dpiScale do
            .setDpiScaleRaw(scale)
        .clientLayoutScale = .dpiScale
        .presentedFrame    = false
        .sendResizeEvent(destination.width, destination.height)

        // Render at the proposed size before USER32 exposes it. The layered call
        // publishes the destination rectangle and its pixels together.
        .paintWnd(.wnd)
    }

    private mtd finishDiscretePlacement()
    {
        .inDiscretePlacement = false

        // Reconcile the committed client even if native placement produced no size message.
        .clientResizePending = true
        if .inDesktopLoop do
            return
        .applyPendingNativeResize()
        if .canPresentPlacement()
        {
            .paintWnd(.wnd)
            discard ValidateRect(.hWnd, null)
        }
    }

    private mtd applyPendingNativeResize()
    {
        if not .clientResizePending or .isMinimized do
            return
        .clientResizePending = false

        // Query the committed drawable once, even if several WM_SIZE messages arrived.
        var client: RECT
        if not GetClientRect(.hWnd, &client) or client.right <= 0 or client.bottom <= 0 do
            return
        if .clientLayoutScale == .dpiScale and .rc.width == client.right and .rc.height == client.bottom do
            return
        .clientLayoutScale = .dpiScale
        .presentedFrame    = false
        .sendResizeEvent(cast(f32, client.right), cast(f32, client.bottom))
    }

    // WINDOWPLACEMENT uses workspace coordinates for ordinary top-level windows, whereas
    // Surface positions are physical screen coordinates. Tool windows use screen coordinates.
    private mtd nativePlacement(pos: Math.Rectangle, showCmd: UINT)->WINDOWPLACEMENT
    {
        var result: #returntype
        result.length = #sizeof(result)
        discard GetWindowPlacement(.hWnd, &result)
        result.flags   = 0
        result.showCmd = showCmd
        result.rcNormalPosition = RECT{cast(s32, pos.x), cast(s32, pos.y), cast(s32, pos.right()), cast(s32, pos.bottom())}
        if not .flags.has(.ToolWindow)
        {
            let point   = POINT{cast(s32, pos.x), cast(s32, pos.y)}
            let monitor = MonitorFromPoint(point, MONITOR_DEFAULTTONEAREST)
            var info: MONITORINFO
            catch GetMonitorInfoA(monitor, &info)
            let dx = info.rcWork.left - info.rcMonitor.left
            let dy = info.rcWork.top - info.rcMonitor.top
            result.rcNormalPosition.left   -= dx
            result.rcNormalPosition.right  -= dx
            result.rcNormalPosition.top    -= dy
            result.rcNormalPosition.bottom -= dy
        }

        return result
    }

    internal mtd const nativeRenderHandle()->const *void? => cast(const *void?, .hWnd)

    // Returns the Win32 window handle owned by this surface.
    mtd const win32Handle()->HWND => .hWnd

    private mtd releasePresentationBitmap()
    {
        if .presentationDC do
            catch DeleteDC(.presentationDC)
        if .presentationBitmap do
            catch DeleteObject(cast(HGDIOBJ, .presentationBitmap))
        .presentationDC     = null
        .presentationBitmap = null
        .presentationPixels = null
    }

    private mtd createPresentationBitmap() fail
    {
        // Use the same high-water bounds as the retained OpenGL target. Dragging within
        // those bounds reuses both allocations, even when the client shrinks and grows.
        let width = .rt.colorBuffer.width
        let height = .rt.colorBuffer.height
        let dc = try CreateCompatibleDC(null)
        defer #fail catch DeleteDC(dc)

        var info: BITMAPINFO
        info.bmiHeader.biSize        = #sizeof(BITMAPINFOHEADER)
        info.bmiHeader.biWidth       = width
        info.bmiHeader.biHeight      = height
        info.bmiHeader.biPlanes      = 1
        info.bmiHeader.biBitCount    = 32
        info.bmiHeader.biCompression = BI_RGB
        var pixels: *u8?
        let bitmap = try CreateDIBSection(null, &info, cast(DIB_RGB_COLORS), &pixels, null, 0)
        if not SelectObject(dc, cast(HGDIOBJ, bitmap))
        {
            let error = GetLastError()
            catch DeleteObject(cast(HGDIOBJ, bitmap))
            try failWinError(error)
        }

        .releasePresentationBitmap()
        .presentationDC     = dc
        .presentationBitmap = bitmap
        .presentationPixels = pixels
        .presentationWidth  = width
        .presentationHeight = height
    }

    internal mtd presentNativeTarget(target: const *Pixel.RenderTarget, paintedRect: Math.Rectangle, tinted: bool)->bool fail
    {
        let size   = SIZE{.rc.width, .rc.height}
        let bounds = Math.Rectangle{0, 0, cast(f32, size.cx), cast(f32, size.cy)}
        var rect   = Math.Rectangle.intersect(paintedRect, bounds)
        if not .presentationBitmap or .presentationWidth < size.cx or .presentationHeight < size.cy
        {
            try .createPresentationBitmap()
            rect = bounds
        }
        // Tints can change the complete frame while the controls repaint only part of it.
        if not .presentedFrame or tinted or .presentedTinted do
            rect = bounds
        if rect.isEmpty() do
            return true

        let dirty = RECT{cast(s32, rect.x), cast(s32, rect.y), cast(s32, rect.right()), cast(s32, rect.bottom())}
        if not .readPresentationPixels(target, dirty) do
            return false

        let source = POINT{}
        let blend = BLENDFUNCTION{AC_SRC_OVER, 0, 255, AC_SRC_ALPHA}
        var update = UPDATELAYEREDWINDOWINFO{cbSize: cast(u32, #sizeof(UPDATELAYEREDWINDOWINFO)),
                                            psize: &size, hdcSrc: .presentationDC, pptSrc: &source,
                                            pblend: &blend, dwFlags: ULW_ALPHA | ULW_EX_NORESIZE, prcDirty: &dirty}
        if .presentingPlacement
        {
            update.pptDst  = &.placementOrigin
            update.dwFlags = ULW_ALPHA
        }
        if not UpdateLayeredWindowIndirect(.hWnd, &update) do
            return false
        .presentedTinted = tinted
        return true
    }

    private mtd readPresentationPixels(target: const *Pixel.RenderTarget, dirty: RECT)->bool
    {
        var framebuffer, buffer, alignment, rowLength, skipRows, skipPixels: GLint
        glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &framebuffer)
        glGetIntegerv(GL_PIXEL_PACK_BUFFER_BINDING, &buffer)
        glGetIntegerv(GL_PACK_ALIGNMENT, &alignment)
        glGetIntegerv(GL_PACK_ROW_LENGTH, &rowLength)
        glGetIntegerv(GL_PACK_SKIP_ROWS, &skipRows)
        glGetIntegerv(GL_PACK_SKIP_PIXELS, &skipPixels)
        defer
        {
            glBindFramebuffer(GL_READ_FRAMEBUFFER, cast(GLuint, framebuffer))
            glBindBuffer(GL_PIXEL_PACK_BUFFER, cast(GLuint, buffer))
            glPixelStorei(GL_PACK_ALIGNMENT, alignment)
            glPixelStorei(GL_PACK_ROW_LENGTH, rowLength)
            glPixelStorei(GL_PACK_SKIP_ROWS, skipRows)
            glPixelStorei(GL_PACK_SKIP_PIXELS, skipPixels)
        }

        glBindFramebuffer(GL_READ_FRAMEBUFFER, cast(GLuint, target.handle))
        glReadBuffer(GL_COLOR_ATTACHMENT0)
        glBindBuffer(GL_PIXEL_PACK_BUFFER, 0)
        glPixelStorei(GL_PACK_ALIGNMENT, 4)
        glPixelStorei(GL_PACK_ROW_LENGTH, .presentationWidth)
        glPixelStorei(GL_PACK_SKIP_ROWS, 0)
        glPixelStorei(GL_PACK_SKIP_PIXELS, 0)

        // Both the FBO and the DIB count rows from the bottom. Their visible client starts
        // at the top of the allocation, and each may have a different amount of spare space.
        let offset = (cast(u64, .presentationHeight - dirty.bottom) * cast(u64, .presentationWidth) + cast(u64, dirty.left)) * 4
        let pixels = cast([*] u8, unwrap .presentationPixels) + offset
        glReadPixels(dirty.left, target.colorBuffer.height - dirty.bottom,
                     dirty.right - dirty.left, dirty.bottom - dirty.top, GL_BGRA, GL_UNSIGNED_BYTE, pixels)
        return glGetError() == GL_NO_ERROR
    }

    internal mtd frameOpacity()->f32 => .opacity

    private mtd applyNativeDwmStyle()
    {
        // DWM placement transitions stretch the previous-size framebuffer while the surface is
        // already laying out and painting its new geometry. The result is a visible clipped or
        // displaced frame during maximize and restore; an immediate placement keeps every frame
        // internally consistent.
        var transitionsForcedDisabled = TRUE
        discard DwmSetWindowAttribute(.hWnd, DWMWA_TRANSITIONS_FORCEDISABLED, cast(LPCVOID, &transitionsForcedDisabled), #sizeof(transitionsForcedDisabled))

        // The corner belongs to the theme, which stamps it into the alpha channel the compositor
        // reads. Letting the platform round the window rectangle on top of that cut the corner
        // twice: the transparent margin the drop shadow is cast into is part of that rectangle,
        // so the system arc sliced through the shadow instead of following the body.
        var cornerPreference = DWMWCP_DONOTROUND
        discard DwmSetWindowAttribute(.hWnd, DWMWA_WINDOW_CORNER_PREFERENCE, cast(LPCVOID, &cornerPreference), #sizeof(cornerPreference))

        var borderColor = DWMWA_COLOR_NONE
        discard DwmSetWindowAttribute(.hWnd, DWMWA_BORDER_COLOR, cast(LPCVOID, &borderColor), #sizeof(borderColor))
    }

    // Shows `icon` for this surface in the notification area, with an optional tooltip.
    //
    // Interactions reach the surface view as a [[Gui.SysUserEvent]] whose
    // [[Gui.SysUserEvent.TrayAction]] reports icon activation and context-menu requests. A
    // second call replaces the icon, and the icon is removed automatically when the surface is
    // destroyed. Nothing is shown without a native window or when `icon` cannot be converted.
    //
    // NIM_SETVERSION selects the Shell's current callback format. If it is unavailable, the
    // window procedure continues to recognize the version 0 mouse notifications.
    mtd setTrayIcon(icon: Pixel.Image, tip: string? = null)
    {
        if not .app.renderer.needsNativeWindow() do
            return

        var img     = icon
        let tipText = String.from(tip orelse "")
        let newIcon = catch img.toHicon()
        if not newIcon do
            return

        .removeTrayIcon()
        .trayIcon         = newIcon
        .native.trayImage = img
        .native.trayTip   = tipText
        if g_TaskbarCreated == 0
        {
            let message = Utf16.toZeroTerminated("TaskbarCreated")
            g_TaskbarCreated = RegisterWindowMessageW(message.buffer)
        }

        var tnid: NOTIFYICONDATAA
        tnid.cbSize = #sizeof(NOTIFYICONDATAA)
        tnid.hWnd   = .hWnd
        tnid.uID    = TrayIconID
        tnid.uFlags = NIF_ICON | NIF_MESSAGE | NIF_SHOWTIP
        tnid.uCallbackMessage = WM_USER
        tnid.hIcon  = .trayIcon

        if tipText.count
        {
            tnid.uFlags |= NIF_TIP
            let count = Math.min(tipText.count, #sizeof(tnid.szTip) - 1)
            Memory.copy(&tnid.szTip[0], unwrap tipText.buffer, count)
        }

        catch Shell_NotifyIconA(NIM_ADD, &tnid)
        {
            catch DestroyIcon(.trayIcon)
            .trayIcon = null
            return
        }

        tnid.uVersion = TrayIconVersion4
        catch Shell_NotifyIconA(NIM_SETVERSION, &tnid) do
            return
        .native.trayIconVersion4 = true
    }

    // Shows a short notification from the notification-area icon of this surface.
    //
    // `title` leads the notification and `message` says the rest; the system keeps at most 63
    // UTF-16 units of the first and 255 of the second. The notification is silent, carries the
    // icon set by [[Gui.Surface.setTrayIcon]], and leaves on its own: it asks no answer, and the
    // system may hold it back while the reader asked not to be disturbed. Nothing is shown
    // without a notification-area icon.
    mtd showTrayMessage(title, message: string)
    {
        if not .trayIcon or not .app.renderer.needsNativeWindow() do
            return

        var tnid: NOTIFYICONDATAW
        tnid.cbSize      = #sizeof(NOTIFYICONDATAW)
        tnid.hWnd        = .hWnd
        tnid.uID         = TrayIconID
        tnid.uFlags      = NIF_INFO
        tnid.dwInfoFlags = NIIF_USER | NIIF_NOSOUND | NIIF_RESPECT_QUIET_TIME

        // Writes `text` into a zeroed field of `fieldBytes` bytes, keeping its terminator.
        func fill(field: [*] u16, fieldBytes: u64, text: string)
        {
            let wide  = Utf16.fromUtf8(text)
            let units = Math.min(wide.count, fieldBytes / #sizeof(u16) - 1)
            for index in units do
                field[index] = wide[index]
        }

        fill(&tnid.szInfoTitle[0], #sizeof(tnid.szInfoTitle), title)
        fill(&tnid.szInfo[0], #sizeof(tnid.szInfo), message)
        catch Shell_NotifyIconW(NIM_MODIFY, &tnid)
    }

    // Returns the visible Shell icon bounds for desktop input tests.
    internal mtd trayIconScreenRect(rect: *RECT)->bool
    {
        if not .trayIcon do
            return false
        var identifier = NOTIFYICONIDENTIFIER{cbSize: cast(DWORD, #sizeof(NOTIFYICONIDENTIFIER)),
                                              hWnd: .hWnd,
                                              uID: TrayIconID}
        return Shell_NotifyIconGetRect(&identifier, rect) == S_OK
    }

    // Reports whether the native notification-area registration succeeded.
    //
    // The icon can still be placed in the system's overflow area.
    mtd hasTrayIcon()->bool => .trayIcon != null

    // Removes the notification-area icon owned by this surface, if any.
    mtd removeTrayIcon()
    {
        if not .trayIcon do
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
        .native.trayIconVersion4 = false
    }

    // Requests a close through the regular system-command event path.
    mtd requestClose()
    {
        if not .app.renderer.needsNativeWindow()
        {
            postSurfaceSysCommand(me, .Close)
            return
        }

        catch PostMessageW(.hWnd, WM_CLOSE, 0, 0)
    }

    // Requests minimization through the regular system-command event path.
    mtd requestMinimize()
    {
        if not .app.renderer.needsNativeWindow()
        {
            postSurfaceSysCommand(me, .Minimize)
            return
        }

        catch PostMessageW(.hWnd, WM_SYSCOMMAND, SC_MINIMIZE, 0)
    }

    // Requests maximization through the regular system-command event path.
    mtd requestMaximize()
    {
        if not .app.renderer.needsNativeWindow()
        {
            postSurfaceSysCommand(me, .Maximize)
            return
        }

        catch PostMessageW(.hWnd, WM_SYSCOMMAND, SC_MAXIMIZE, 0)
    }

    // Requests restoration through the regular system-command event path.
    mtd requestRestore()
    {
        if not .app.renderer.needsNativeWindow()
        {
            postSurfaceSysCommand(me, .Restore)
            return
        }

        catch PostMessageW(.hWnd, WM_SYSCOMMAND, SC_RESTORE, 0)
    }

    internal mtd applyNativeSurfaceFlags()
    {
        let shouldBeTopMost = .flags.has(.TopMost)
        let topMostChanged  = .topMost != shouldBeTopMost
        .topMost = shouldBeTopMost

        if not .app.renderer.needsNativeWindow() or not .hWnd do
            return

        var exStyle = cast #bit (u64, GetWindowLongPtrA(.hWnd, GWL_EXSTYLE))
        if .flags & .ToolWindow do
            exStyle |= WS_EX_TOOLWINDOW
        else do
            exStyle &= ~WS_EX_TOOLWINDOW
        if .flags & .TopMost do
            exStyle |= WS_EX_TOPMOST
        else do
            exStyle &= ~WS_EX_TOPMOST
        SetWindowLongPtrA(.hWnd, GWL_EXSTYLE, cast #bit (LONG_PTR, exStyle))
        if topMostChanged do
            catch SetWindowPos(.hWnd, shouldBeTopMost ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE)
        .applyNativeDwmStyle()
    }

    // Sends a custom message to the surface created with `surfaceId`, possibly in another process, and returns whether it was found.
    //
    // The target surface view receives a [[Gui.SysUserEvent]] of kind `CustomMessage` carrying
    // `id` and `param`. The call waits until the message has been handled.
    func sendCustomMessage(surfaceId: string, id: u32, param: u64)->bool
    {
        let className = Utf16.toZeroTerminated("Swag.Gui.Surface")
        let property  = identityProperty(surfaceId)
        var hwnd: HWND
        for
        {
            hwnd = FindWindowExW(null, hwnd, className.buffer, null)
            if not hwnd do
                return false
            if GetPropW(hwnd, property.buffer) != null do
                break
        }

        discard SendMessageA(hwnd, WM_APP + id, 0, param)
        return true
    }

    // Returns the name of the window property that carries `surfaceId`, zero-terminated in UTF-16.
    //
    // A surface is found by its identity, not by its native title: the title is what the task bar
    // and the window switcher show, and follows [[Gui.Surface.setTitle]].
    internal func identityProperty(surfaceId: string)->Array'u16 => Utf16.toZeroTerminated(Format.toString("Swag.Gui.Surface:%", surfaceId))

    // Gives the native window the title of the surface, or its identity while it has none.
    internal mtd applyNativeTitle()
    {
        if not .hWnd do
            return
        let title = .wnd.name.text.isEmpty() ? Utf16.toZeroTerminated(.surfaceId) : Utf16.toZeroTerminated(.wnd.name.text)
        discard SetWindowTextW(.hWnd, title.buffer)
    }

    // Returns `pos` with its extent brought inside the surface size limits.
    //
    // The limits are logical and a placement rectangle is physical, so the comparison happens
    // through the surface scale.
    private mtd const clampToSizeLimits(pos: Math.Rectangle)->Math.Rectangle
    {
        var result = pos

        if .minSize.x > 0 do
            result.width = Math.max(result.width, .minSize.x * .dpiScale)
        if .minSize.y > 0 do
            result.height = Math.max(result.height, .minSize.y * .dpiScale)
        if .maxSize.x > 0 do
            result.width = Math.min(result.width, .maxSize.x * .dpiScale)
        if .maxSize.y > 0 do
            result.height = Math.min(result.height, .maxSize.y * .dpiScale)

        return result
    }

    // Sets the surface bounds in physical screen pixels, clamped to [[Gui.Surface.minSize]] and [[Gui.Surface.maxSize]].
    mtd setPosition(pos: Math.Rectangle)
    {
        let clampPos = .clampToSizeLimits(pos)
        .position = clampPos
        if not .app.renderer.needsNativeWindow()
        {
            .sendResizeEvent(clampPos.width, clampPos.height)
            return
        }

        // The rectangle is physical for its target monitor already; flag the move so
        // a DPI-boundary WM_DPICHANGED does not rescale it (see the handler).
        .inAppPlacement = true
        defer .inAppPlacement = false

        // Discard the previous client pixels, but let Windows invalidate the new
        // client area. Suppressing redraw here left the compositor presenting an
        // empty or stale framebuffer until another input message happened to paint.
        catch SetWindowPos(.hWnd, null, cast(s32, clampPos.x), cast(s32, clampPos.y), cast(s32, clampPos.width), cast(s32, clampPos.height), SWP_NOCOPYBITS | SWP_NOSENDCHANGING)
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
    mtd const isTopMost()->bool => .topMost

    // Brings the surface to the front of its current Z-order group.
    mtd bringToFront()
    {
        if not .app.renderer.needsNativeWindow() do
            return

        BringWindowToTop(.hWnd)
    }

    // Enables input for the surface.
    mtd enable()
    {
        if not .isDisabled do
            return
        .isDisabled = false

        .invalidate()
        if not .app.renderer.needsNativeWindow()
        {
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
        .invalidate()
        if not .app.renderer.needsNativeWindow()
        {
            return
        }

        EnableWindow(.hWnd, FALSE)
    }

    // Changes the opacity used to present the whole surface.
    mtd setOpacity(opacity: f32)
    {
        let value = Math.saturate(opacity)
        if .opacity == value do
            return
        .opacity = value
        if not .isHidden do
            .invalidate()
    }

    // Shows the surface and emits its one-time initialization event when needed.
    //
    // A [[Gui.SurfaceFlags.Sheet]] arrives the way a floating surface does inside a window: it
    // fades in over its owner, without travel, unless motion is reduced.
    mtd show()
    {
        if not .isHidden do
            return

        .isHidden = false
        if .flags.has(.Sheet) and not .app.isReducedMotion()
        {
            .opacity = 0
            var options: AnimationOptions
            options.duration = Time.Duration.fromSeconds(.wnd.themeMetrics().motion_PageSeconds)
            options.easing   = .EaseOut
            discard .app.animator.animateF32(.wnd,
                                             AnimationChannel.from("Gui.Surface.Opacity"),
                                             0,
                                             1,
                                             func(wnd, value) { wnd.surface?.setOpacity(value) },
                                             options,
                                             func|srf = me|(_) { srf.setOpacity(1) })
        }

        // First-show initialization stage. Runs while the window is still hidden,
        // so the application can perform slow setup (restoring state, loading
        // content, resizing the surface, ...). The window is only made visible
        // afterwards, once a first frame has been rendered.
        if not .isInitialized
        {
            .isInitialized = true
            .initializing  = true
            .wnd.view.sendStateEvent(.Init)
            .initializing = false
        }

        .invalidate()
        .wnd.applyLayout(.size())

        // Publish the first complete bitmap while the window is hidden. First paint can
        // initialize fonts and glyphs, so keep that work outside the visible transition.
        .paint()

        if not .app.renderer.needsNativeWindow()
        {
            let curFocus = .wnd.view.focusedWindow()
            if not curFocus or not .wnd.isAncestorOf(curFocus) do
                discard .restoreFocus()
            .wnd.view.sendStateEvent(.Show)
            return
        }

        ShowWindow(.hWnd, SW_SHOW)
        .applyNativeDwmStyle()

        let curFocus = .wnd.view.focusedWindow()
        if not curFocus or not .wnd.isAncestorOf(curFocus) do
            discard .restoreFocus()
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

        if not .app.renderer.needsNativeWindow()
        {
            .wnd.view.sendStateEvent(.Hide)
            return
        }

        ShowWindow(.hWnd, SW_HIDE)
        .wnd.view.sendStateEvent(.Hide)
    }

    // Shows the surface maximized and preserves its current bounds for restoration.
    mtd showMaximized()
    {
        // The window messages the call dispatches move `.position`; restore to what it is now.
        .showMaximized(#copy .position)
    }

    // Shows the surface maximized, with `restoreTo` as the bounds a later restore returns to.
    //
    // A surface standing somewhere temporary cannot let its current rectangle become that: a
    // window leaving full screen for the maximized state it came from would otherwise remember
    // the whole monitor as the size to restore to.
    mtd showMaximized(restoreTo: Math.Rectangle)
    {
        if .isMaximized and not .isMinimized do
            return
        if .isMaximized
        {
            .isMinimized = false
            if not .app.renderer.needsNativeWindow()
            {
                .invalidate()
                return
            }

            .applyNativeDwmStyle()
            .inDiscretePlacement = true
            defer .finishDiscretePlacement()
            .invalidate()
            ShowWindow(.hWnd, SW_SHOWMAXIMIZED)
            return
        }

        .isMaximized      = true
        .isMinimized      = false
        .restoredPosition = restoreTo
        if not .app.renderer.needsNativeWindow()
        {
            .invalidate()
            return
        }

        .applyNativeDwmStyle()
        .inDiscretePlacement = true
        defer .finishDiscretePlacement()
        .invalidate()
        // Maximize the current window first. Changing its normal rectangle while it is
        // still normal would move it there before USER32 applies the maximized state.
        ShowWindow(.hWnd, SW_SHOWMAXIMIZED)
        var placement = .nativePlacement(.restoredPosition, SW_SHOWMAXIMIZED)
        catch SetWindowPlacement(.hWnd, &placement)
    }

    // Leaves a maximized or minimized state and places the surface, in one native transaction.
    //
    // Restoring first and placing afterwards publishes two geometry transactions, and the
    // compositor shows the window at its restored bounds in between. Entering full screen from a
    // maximized window is the case that exists, and that intermediate picture is what it looked
    // like. `pos` is in physical screen pixels and becomes the bounds a later restore uses.
    mtd showNormalAt(pos: Math.Rectangle)
    {
        let clampPos = .clampToSizeLimits(pos)
        .isMaximized = false
        .isMinimized = false
        .position    = clampPos

        if not .app.renderer.needsNativeWindow()
        {
            .sendResizeEvent(clampPos.width, clampPos.height)
            return
        }

        .applyNativeDwmStyle()

        // The rectangle is physical for its target monitor already; flag the move so
        // a DPI-boundary WM_DPICHANGED does not rescale it (see the handler).
        .inAppPlacement = true
        defer .inAppPlacement = false
        .inDiscretePlacement = true
        defer .finishDiscretePlacement()
        .invalidate()
        var placement = .nativePlacement(clampPos, SW_SHOWNORMAL)
        catch SetWindowPlacement(.hWnd, &placement)
    }

    // Restores a minimized or maximized surface to its normal bounds.
    mtd showNormal()
    {
        if not .isMaximized and not .isMinimized do
            return

        // SW_RESTORE returns a minimized maximized HWND to maximized state. Explicit normal
        // placement is needed when the caller asks to leave both states at once.
        .showNormalAt(.restoredPosition)
    }

    // Shows the surface minimized.
    mtd showMinimized()
    {
        if .isMinimized do
            return
        if not .isMaximized do
            .restoredPosition = .position
        .isMinimized = true
        if not .app.renderer.needsNativeWindow()
        {
            .invalidate()
            return
        }

        ShowWindow(.hWnd, SW_SHOWMINIMIZED)
    }

    // Converts `pt` in place from physical screen pixels to logical surface coordinates.
    mtd screenToSurface(pt: *Math.Point)
    {
        if not .app.renderer.needsNativeWindow()
        {
            pt.x = (pt.x - .position.x) / .dpiScale
            pt.y = (pt.y - .position.y) / .dpiScale
            return
        }

        var wpt = POINT{cast(s32, pt.x), cast(s32, pt.y)}
        ScreenToClient(.hWnd, &wpt)
        pt.x = wpt.x / .dpiScale
        pt.y = wpt.y / .dpiScale
    }

    // Converts `pt` in place from logical surface coordinates to physical screen pixels.
    mtd surfaceToScreen(pt: *Math.Point)
    {
        if not .app.renderer.needsNativeWindow()
        {
            pt.x = pt.x * .dpiScale + .position.x
            pt.y = pt.y * .dpiScale + .position.y
            return
        }

        var wpt = POINT{cast(s32, (pt.x * .dpiScale)), cast(s32, (pt.y * .dpiScale))}
        ClientToScreen(.hWnd, &wpt)
        pt.x = wpt.x
        pt.y = wpt.y
    }
}
