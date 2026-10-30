#global public
#global if #os == Swag.TargetOs.Windows

using Core, Win32, Gdi32, Ogl

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
    inDesktopLoop: bool

    // First-show setup can restore several placements before its content is ready to paint.
    initializing: bool

    // A discrete placement prepares its expensive frame before USER32 exposes the new size.
    inDiscretePlacement:                   bool
    preparingFrame:                        bool
    preparedFrame:                         bool
    presentedFrame:                        bool
    preparedWidth:                         s32
    preparedHeight:                        s32
    presentationTarget:                    Pixel.RenderTarget
    presentationDC:                        HDC
    presentationBitmap:                    Gdi32.HBITMAP
    presentationPixels:                    *u8?
    presentationWidth, presentationHeight: s32
    readback:                              Pixel.RenderOglReadback
    asynchronousPresentationFailed:        bool
    presentationDirtyRect:                 Math.Rectangle
}

// Fixed notification-area icon id. A surface owns at most one tray icon.
private const TrayIconID = 1

private impl Surface
{
    // Reports whether a frame may be recorded and presented for this window right now.
    //
    // A window is sized before it is shown and again while it is being taken down, and neither
    // of those transactions has a frame to publish: the first has no content yet, the second no
    // rendering context left.
    mtd const canPresentNow()->bool => not .isHidden and not .initializing and not .isMinimized and not .wnd.isPendingDestroy

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
        if msg == WM_USER
        {
            var evt = SysUserEvent{}
            evt.kind = .TrayIcon
            switch lParam
            {
            case WM_LBUTTONDBLCLK: evt.trayAction = .Activate
            case WM_RBUTTONDOWN:   evt.trayAction = .ContextMenu
            }

            surface.wnd.view.sendEvent(&evt)
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

        case WM_ERASEBKGND:
            return 0

        case WM_NCPAINT:
            return 0

        case WM_NCCALCSIZE:

            // UpdateLayeredWindow publishes bounds and pixels in one native operation before
            // USER32 exposes the new client area. Mark it first because publication reenters us.
            if surface.inDiscretePlacement and surface.preparedFrame and not surface.presentedFrame
            {
                surface.presentedFrame = true
                surface.preparingFrame = true
                surface.presentPreparedFrame()
                surface.preparingFrame = false
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

            // A prepared frame belongs to the upcoming placement. Do not replace it with an
            // ordinary repaint while preparing or publishing that placement.
            if surface.initializing or surface.preparingFrame or surface.preparedFrame
            {
                EndPaint(hWnd, &ps)
                return 0
            }

            surface.invalidatePhysicalRect(Math.Rectangle{cast(f32, ps.rcPaint.left), cast(f32, ps.rcPaint.top), cast(f32, (ps.rcPaint.right - ps.rcPaint.left)), cast(f32, (ps.rcPaint.bottom - ps.rcPaint.top))})

            // The application loop is suspended during a native border drag. Paint on this
            // window-owning thread before EndPaint validates the native update region.
            surface.paint()

            EndPaint(hWnd, &ps)
            return 0

        case WM_NCLBUTTONDOWN:

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
            surface.setSizing(true)
            surface.enterDesktopLoop()
            return 0

        case WM_EXITSIZEMOVE:
            surface.setSizing(false)
            surface.exitDesktopLoop()

            // The gesture is over, so content that held a reflow back for its duration runs it
            // now, and the exact final geometry reaches the screen before the application loop
            // resumes.
            if surface.canPresentNow()
            {
                surface.invalidate()
                surface.paint()
                discard ValidateRect(hWnd, null)
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

            if surface.inDiscretePlacement and not surface.preparingFrame and surface.canPresentNow()
            {
                let next = cast(*WINDOWPOS, cast #bit (u64, lParam))
                if (next.flags & SWP_NOSIZE) == 0 and next.cx > 0 and next.cy > 0
                {
                    if surface.preparedFrame and
                       surface.preparedWidth == next.cx and
                       surface.preparedHeight == next.cy and
                       not surface.isDirty do
                        return 0

                    surface.preparedFrame  = false
                    surface.presentedFrame = false
                    surface.preparingFrame = true
                    if (next.flags & SWP_NOMOVE) == 0
                    {
                        surface.position.x = cast(f32, next.x)
                        surface.position.y = cast(f32, next.y)
                    }

                    surface.sendResizeEvent(cast(f32, next.cx), cast(f32, next.cy))
                    surface.preparedFrame  = surface.prepareResizeFrame(surface.wnd)
                    surface.preparingFrame = false
                    if surface.preparedFrame
                    {
                        surface.preparedWidth  = next.cx
                        surface.preparedHeight = next.cy
                    }
                }
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
            // double-scale it. Keep the requested rectangle; its WM_SIZE relayouts
            // the tree with the new scale.
            if surface.inAppPlacement
            {
                surface.invalidate()
                return 0
            }

            // An interactive move: adopt the suggested physical rectangle, whose
            // WM_SIZE recomputes the logical size and relayouts the tree with the
            // new scale; per-draw font resolution follows on the next paint.
            let suggested = cast(const *RECT, cast #bit (u64, lParam))
            catch SetWindowPos(hWnd, null, suggested.left, suggested.top, suggested.right - suggested.left, suggested.bottom - suggested.top, SWP_NOZORDER | SWP_NOACTIVATE)
            surface.invalidate()
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

            // A minimized client has no drawable geometry. Keeping the last arranged tree avoids
            // a useless collapse to zero followed by a full expansion on restore.
            if wParam == SizeMinimized
            {
                surface.preparedFrame = false
                return 0
            }

            let width    = cast(s32, LOWORD(lParam))
            let height   = cast(s32, HIWORD(lParam))
            let prepared = surface.preparedFrame and
                           surface.preparedWidth == width and
                           surface.preparedHeight == height and
                           not surface.isDirty
            surface.preparedFrame = prepared
            if not prepared do
                surface.sendResizeEvent(cast(f32, width), cast(f32, height))
            if surface.inDiscretePlacement do
                return 0
            surface.preparedFrame = false

            // Interactive resizing paints on the window thread while the application loop
            // is suspended in USER32's sizing loop.
            if surface.canPresentNow()
            {
                if prepared do
                    surface.presentPreparedFrame()
                else do
                    surface.paint()
                discard ValidateRect(hWnd, null)
            }

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
            wc.style         = CS_DBLCLKS | CS_HREDRAW | CS_VREDRAW
            wc.lpfnWndProc   = cast(&winProc)
            wc.hCursor       = LoadCursorA(null, MAKEINTRESOURCEA(IDC_ARROW))
            wc.hIcon         = hIcon
            wc.lpszClassName = className
            try RegisterClassW(wc)
        }

        var winFlags = 0'u32
        winFlags |= WS_POPUP | WS_CLIPCHILDREN

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
        if .rc.data
        {
            .app.renderer.setCurrentContext(.rc)
            .readback.release()
            .app.renderer.deleteRenderTarget(&.presentationTarget)
        }

        .destroyNativePresentation()
        .destroyRendering()
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
    private mtd finishDiscretePlacement()
    {
        .preparingFrame = true
        defer .preparingFrame = false
        defer .inDiscretePlacement = false
        defer .preparedFrame = false
        defer .presentedFrame = false

        // An unchanged size can still change the chrome. Present once if no size transaction
        // published the frame, or repaint if the placement invalidated its prepared contents.
        if .canPresentNow()
        {
            if .preparedFrame and not .isDirty
            {
                if not .presentedFrame do
                    .presentPreparedFrame()
            }
            else
            {
                .paint()
            }

            discard ValidateRect(.hWnd, null)
        }
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

    private mtd destroyNativePresentation()
    {
        if .presentationDC do
            catch DeleteDC(.presentationDC)
        if .presentationBitmap do
            catch DeleteObject(cast(Gdi32.HGDIOBJ, .presentationBitmap))
        .presentationDC     = null
        .presentationBitmap = null
        .presentationPixels = null
        .presentationWidth  = 0
        .presentationHeight = 0
    }

    internal mtd bindNativePresentationTarget()
    {
        if .presentationTarget.colorBuffer.width != .rc.width or .presentationTarget.colorBuffer.height != .rc.height
        {
            .app.renderer.deleteRenderTarget(&.presentationTarget)
            .presentationTarget = .app.renderer.createRenderTarget(.rc.width, .rc.height)
        }

        .app.renderer.bindRenderTarget(&.presentationTarget)
    }

    internal mtd canQueueNativePresentation()->bool =>
        not .asynchronousPresentationFailed and
        not .app.frameTrace.synchronousPresentation and
        not .preparingFrame and
        not .inDiscretePlacement and
        not .inDesktopLoop and
        .presentationWidth == .rc.width and
        .presentationHeight == .rc.height and
        .app.renderer is Pixel.RenderOgl

    internal mtd cancelNativePresentation()
    {
        .app.renderer.setCurrentContext(.rc)
        if .readback.isPending() do
            .invalidate()
        .readback.cancel()
    }

    internal mtd queueNativePresentation(target: const *Pixel.RenderTarget)->bool
    {
        .presentationDirtyRect = .paintPhysicalRect
        if .presentationDirtyRect.isEmpty() or (.isDisabled and .app.fadeDisabledSurface) do
            .presentationDirtyRect = Math.Rectangle{0, 0, cast(f32, .rc.width), cast(f32, .rc.height)}
        let rect = .presentationDirtyRect
        if .readback.submit(target, cast(s32, rect.x), cast(s32, rect.y), cast(s32, rect.width), cast(s32, rect.height)) do
            return true
        .asynchronousPresentationFailed = true
        .readback.release()
        return false
    }

    // A busy GPU holds one snapshot, never a queue of obsolete interaction states. Poll before
    // recording another frame so dirty content stays coalesced while input continues to dispatch.
    internal mtd advanceNativePresentation()->bool
    {
        if not .readback.isPending() do
            return true
        .app.renderer.setCurrentContext(.rc)
        if not .canQueueNativePresentation()
        {
            .readback.cancel()
            .invalidate()
            return true
        }

        var watch: Time.Stopwatch
        if .app.frameTrace.enabled do
            watch.start()
        let rect   = .presentationDirtyRect
        let stride = cast(u64, .presentationWidth) * 4
        let offset = cast(u64, (cast(f32, .presentationHeight) - rect.bottom())) * stride + cast(u64, rect.x) * 4
        let pixels = Swag.makeSlice(cast([*] u8, unwrap .presentationPixels) + offset,
                                    stride * cast(u64, .presentationHeight) - offset)
        if .readback.tryCopyTo(pixels, stride)
        {
            .publishNativePresentation()
        }
        elif .readback.hasFailed()
        {
            .asynchronousPresentationFailed = true
            .readback.release()
            .invalidate()
        }

        if .app.frameTrace.enabled do
            .app.frameTrace.presentUs += watch.elapsedMicroseconds()
        return not .readback.isPending()
    }

    internal mtd prepareNativePresentation(target: const *Pixel.RenderTarget)
    {
        // A persistent layered HWND lets USER32 publish geometry and pixels together. Its
        // bitmap is CPU-backed; keep it across repaints and copy the complete premultiplied
        // BGRA frame, including the transparent shadow margin.
        if .presentationWidth != .rc.width or .presentationHeight != .rc.height
        {
            .destroyNativePresentation()
            .presentationDC = expect CreateCompatibleDC(null)
            var info: BITMAPINFO
            info.bmiHeader.biSize        = #sizeof(BITMAPINFOHEADER)
            info.bmiHeader.biWidth       = .rc.width
            info.bmiHeader.biHeight      = .rc.height
            info.bmiHeader.biPlanes      = 1
            info.bmiHeader.biBitCount    = 32
            info.bmiHeader.biCompression = BI_RGB
            .presentationBitmap          = expect CreateDIBSection(null, &info, cast(DIB_RGB_COLORS), &.presentationPixels, null, 0)
            SelectObject(.presentationDC, cast(Gdi32.HGDIOBJ, .presentationBitmap))
            .presentationWidth  = .rc.width
            .presentationHeight = .rc.height
        }

        let image = .app.renderer.readRenderTarget(target, 0, 0, .rc.width, .rc.height)
        Memory.copy(unwrap .presentationPixels, image.pixels.storage(), image.byteCount)
        .presentationDirtyRect = Math.Rectangle{0, 0, cast(f32, .rc.width), cast(f32, .rc.height)}
    }

    internal mtd publishNativePresentation()
    {
        let destination = POINT{cast(s32, .position.x), cast(s32, .position.y)}
        let size        = SIZE{.presentationWidth, .presentationHeight}
        let source      = POINT{}
        let blend       = BLENDFUNCTION{AC_SRC_OVER, 0, cast(u8, Math.round(Math.saturate(.opacity) * 255)), AC_SRC_ALPHA}
        let dirty       = RECT{cast(s32, .presentationDirtyRect.x), cast(s32, .presentationDirtyRect.y),
                               cast(s32, .presentationDirtyRect.right()), cast(s32, .presentationDirtyRect.bottom())}
        with var info: UPDATELAYEREDWINDOWINFO
        {
            .cbSize = #sizeof(UPDATELAYEREDWINDOWINFO)

            // Every frame names its position and size. Without them the call still succeeds,
            // but the compositor keeps showing the previous image.
            .pptDst   = &destination
            .psize    = &size
            .hdcSrc   = me.presentationDC
            .pptSrc   = &source
            .pblend   = &blend
            .dwFlags  = ULW_ALPHA
            .prcDirty = &dirty
        }

        if not UpdateLayeredWindowIndirect(.hWnd, &info) do
            expect failWinError(GetLastError())
    }

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
    // This uses the legacy (version 0) NOTIFYICON behavior on purpose: the callback carries
    // the mouse message directly in `lParam`, which is what the window procedure translates.
    // NIM_SETVERSION/NOTIFYICON_VERSION_4 would change that layout.
    mtd setTrayIcon(icon: Pixel.Image, tip: string? = null)
    {
        if not .app.renderer.needsNativeWindow() do
            return

        var img     = icon
        let newIcon = catch img.toHicon()
        if not newIcon do
            return

        .removeTrayIcon()
        .trayIcon = newIcon

        var tnid: NOTIFYICONDATAA
        tnid.cbSize = #sizeof(NOTIFYICONDATAA)
        tnid.hWnd   = .hWnd
        tnid.uID    = TrayIconID
        tnid.uFlags = NIF_ICON | NIF_MESSAGE
        tnid.uCallbackMessage = WM_USER
        tnid.hIcon  = .trayIcon

        if tip
        {
            tnid.uFlags |= NIF_TIP
            let count = Math.min(tip.count, #sizeof(tnid.szTip) - 1)
            Memory.copy(&tnid.szTip[0], tip.buffer, count)
        }

        catch Shell_NotifyIconA(NIM_ADD, &tnid)
    }

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
        let title = .wnd.name.raw.isEmpty() ? Utf16.toZeroTerminated(.surfaceId) : Utf16.toZeroTerminated(.wnd.name.raw)
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

        // The presented bitmap was tinted across the whole surface. A local repaint cannot
        // restore the untouched pixels when native presentation resumes copying dirty regions.
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

    // Changes the opacity the desktop composites the whole surface at, without painting it again.
    mtd setOpacity(opacity: f32)
    {
        let value = Math.saturate(opacity)
        if .opacity == value do
            return
        .opacity = value
        if not .isHidden and .presentationPixels and .app.renderer.needsNativeWindow() do
            .publishNativePresentation()
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

        // Render the first complete frame into the back buffer *before* the window
        // becomes visible. Otherwise ShowWindow composites the still-empty (black)
        // GL surface, and the user sees a black flash until the first runFrame()
        // paint completes (which is slow on the first frame because of the lazy
        // font/glyph generation it triggers). Painting while still hidden means the
        // window appears already showing correct content.
        .preparingFrame = true
        .paint()
        .preparingFrame = false

        if not .app.renderer.needsNativeWindow()
        {
            let curFocus = .wnd.view.focusedWindow()
            if not curFocus or not .wnd.isAncestorOf(curFocus) do
                .wnd.view.setFocus()
            .wnd.view.sendStateEvent(.Show)
            return
        }

        ShowWindow(.hWnd, SW_SHOW)
        .applyNativeDwmStyle()

        let curFocus = .wnd.view.focusedWindow()
        if not curFocus or not .wnd.isAncestorOf(curFocus) do
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
    //
    // Windows owns the show state and restore placement. The frame is prepared before the
    // geometry changes, then published with the destination bounds by UpdateLayeredWindow.
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
