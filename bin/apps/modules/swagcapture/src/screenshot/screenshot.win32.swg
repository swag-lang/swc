#global if #os == Swag.TargetOs.Windows

using Core, Win32, Gdi32

// DWM removes these owned floating controls from desktop captures while leaving them visible
// to the person recording. The affinity is tied to the HWND and disappears with it.
#[Foreign("user32", callconv: Swag.CallConv.C), Discardable]
func SetWindowDisplayAffinity(hWnd: HWND, dwAffinity: DWORD)->BOOL

#[Foreign("user32", callconv: Swag.CallConv.C), Discardable]
func GetWindowDisplayAffinity(hWnd: HWND, pdwAffinity: *DWORD)->BOOL

func excludeCaptureChrome(surface: *Surface)
{
    if surface.win32Handle() do
        discard SetWindowDisplayAffinity(surface.win32Handle(), 0x11'u32) // WDA_EXCLUDEFROMCAPTURE
}

// Windows hides owned recording controls from BitBlt through display affinity.
func captureRecordingFrame(drawCursor: bool, _: Math.Rectangle, _: *Surface?, x, y, w, h: s32)->Image fail
    => try getScreenRectImage(drawCursor, x, y, w, h)

// Restores the caller's DPI-awareness context when a capture operation ends.
#[Swag.NoCopy]
struct CapturePlatformScope
{
    previous: DPI_AWARENESS_CONTEXT
}

impl CapturePlatformScope
{
    mtd close()
    {
        discard SetThreadDpiAwarenessContext(.previous)
    }
}

// Enters the native coordinate context required by the Windows capture backend.
func beginCapturePlatformScope()->CapturePlatformScope => CapturePlatformScope{SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE)}

internal
{
    var g_HitTest: POINT
    var g_Hit:     HWND
    var g_Ignore:  HWND

    #[Swag.CallingConvention(.C)]
    func enumProc(hWnd: HWND, _: LPARAM)->BOOL
    {
        if not IsWindowVisible(hWnd) do
            return TRUE

        if hWnd == g_Ignore do
            return TRUE

        var r: RECT
        GetWindowRect(hWnd, &r)
        if g_HitTest.x >= r.left and
           g_HitTest.x < r.right and
           g_HitTest.y >= r.top and
           g_HitTest.y < r.bottom
        {
            var className: [256] CHAR
            let n   = GetClassNameA(hWnd, &className[0], 256)
            let str = String.from(Swag.makeString(&className[0], n))

            let systemClasses = [
                "Windows.UI.Core.CoreWindow",     // UWP system windows
                "ApplicationFrameWindow"]         // UWP app frames

            for s in systemClasses
            {
                if str == s do
                    return TRUE
            }

            g_Hit = hWnd
            return FALSE
        }

        return TRUE
    }
}

// Reads the stable, top-level identity of a window. Access to another process can be
// refused; the title and class still make the capture searchable in that case.
func captureWindowInfo(hWnd: HWND)->CaptureWindowInfo
{
    var result: #returntype
    if not hWnd do
        return result

    var window = hWnd
    let root   = GetAncestor(window, GA_ROOT)
    if root do
        window = root
    result.nativeWindow = cast(u64, window)

    var title: [1024] u16
    let titleLength = GetWindowTextW(window, &title[0], cast(s32, title.count))
    if titleLength > 0 do
        result.title = Utf8.fromUtf16(Swag.makeSlice(&title[0], cast(u64, titleLength)))

    var className: [256] u16
    let classLength = GetClassNameW(window, &className[0], cast(s32, className.count))
    if classLength > 0 do
        result.className = Utf8.fromUtf16(Swag.makeSlice(&className[0], cast(u64, classLength)))

    var processId: u32
    discard GetWindowThreadProcessId(window, &processId)
    if not processId do
        return result

    let process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, processId)
    if not process do
        return result
    defer CloseHandle(process)

    var path: Array'u16
    path.resize(32768)
    var pathLength = cast(u32, path.count)
    if not QueryFullProcessImageNameW(process, 0, (path.toSlice()).buffer, &pathLength) do
        return result

    result.executable  = Utf8.fromUtf16(Swag.makeSlice((path.toSlice()).buffer, cast(u64, pathLength)))
    result.application = Path.fileNameWithoutExtension(result.executable) orelse ""
    return result
}

// Reads a live window frame and show state in physical screen pixels.
func getCaptureWindowBounds(id: u64)->{rect: Math.Rectangle, visible: bool, exists: bool}
{
    var result: #returntype
    if not id do
        return result
    let window = cast(HWND, id)
    var frame: RECT
    var placement: WINDOWPLACEMENT
    placement.length = #sizeof(WINDOWPLACEMENT)
    if not GetWindowRect(window, &frame) or not GetWindowPlacement(window, &placement) do
        return result
    result.rect = {frame.left, frame.top, frame.right - frame.left, frame.bottom - frame.top}
    result.visible = IsWindowVisible(window) and placement.showCmd != SW_SHOWMINIMIZED and
                     placement.showCmd != SW_SHOWMINNOACTIVE and placement.showCmd != SW_MINIMIZE
    result.exists = not result.rect.isEmpty()
    return result
}

// Returns the top-level window under the physical point `x, y`, ignoring the overlay `srf`;
// null when there is none.
func findWndAtPos(srf: *Surface, x, y: f32)->HWND
{
    let awareness = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE)
    defer discard SetThreadDpiAwarenessContext(awareness)

    g_HitTest.x = cast(x)
    g_HitTest.y = cast(y)

    g_Hit    = null
    g_Ignore = srf.win32Handle()
    EnumWindows(cast(&enumProc), 0)
    if not g_Hit do
        return null

    for
    {
        var pt1: POINT
        pt1.x = g_HitTest.x
        pt1.y = g_HitTest.y
        ScreenToClient(g_Hit, &pt1)
        let child = ChildWindowFromPointEx(g_Hit, pt1, CWP_SKIPINVISIBLE | CWP_SKIPDISABLED | CWP_SKIPTRANSPARENT)
        if not child or child == g_Hit do
            break
        g_Hit = child
    }

    if not g_Hit do
        return null

    return g_Hit
}

func getCaptureWindowAtPos(srf: *Surface, x, y: f32)->{ rect: Math.Rectangle, info: CaptureWindowInfo }
{
    var result: #returntype
    let hit = findWndAtPos(srf, x, y)
    if not hit do
        return result

    var r: RECT
    GetWindowRect(hit, &r)
    result.rect = Math.Rectangle{r.left, r.top, r.right - r.left, r.bottom - r.top}
    result.info = captureWindowInfo(hit)
    return result
}

// A hand-drawn area belongs to an application only when the whole selection lies inside
// that application's top-level window. A rectangle spanning windows stays unclassified.
func getCaptureWindowForRect(srf: *Surface, captureRect: Math.Rectangle)->CaptureWindowInfo
{
    let hit = findWndAtPos(srf, captureRect.horzCenter(), captureRect.vertCenter())
    if not hit do
        return {}

    var window = GetAncestor(hit, GA_ROOT)
    if not window do
        window = hit

    var r: RECT
    GetWindowRect(window, &r)
    if captureRect.x < r.left or
       captureRect.y < r.top or
       captureRect.right() > r.right or
       captureRect.bottom() > r.bottom do
        return {}

    return captureWindowInfo(window)
}

// Returns the screen rectangle and the description of the foreground window; empty when there
// is none.
func getBackgroundWindow()->{ rect: Math.Rectangle, info: CaptureWindowInfo }
{
    var result: #returntype
    let hit = GetForegroundWindow()
    if not hit do
        return result

    let awareness = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE)
    defer discard SetThreadDpiAwarenessContext(awareness)

    var r: RECT
    GetWindowRect(hit, &r)
    result.rect = Math.Rectangle{r.left, r.top, r.right - r.left, r.bottom - r.top}
    result.info = captureWindowInfo(hit)
    return result
}

// Draw the current mouse cursor into the device context, accounting for the
// cursor hotspot and the offset of the captured rect on the virtual desktop.
func drawCursorInto(memDC: HDC, offsetX, offsetY: s32)
{
    var ci: CURSORINFO
    ci.cbSize = #sizeof(CURSORINFO)
    if not GetCursorInfo(&ci) do
        return
    if not (ci.flags & CURSOR_SHOWING) or not ci.hCursor do
        return

    let hIcon = cast(HICON, ci.hCursor)

    var ii: ICONINFO
    catch GetIconInfo(hIcon, &ii)
    defer
    {
        if ii.hbmMask do
            catch DeleteObject(cast(ii.hbmMask))
        if ii.hbmColor do
            catch DeleteObject(cast(ii.hbmColor))
    }

    let x = ci.ptScreenPos.x - offsetX - cast(s32, ii.xHotspot)
    let y = ci.ptScreenPos.y - offsetY - cast(s32, ii.yHotspot)
    DrawIconEx(memDC, x, y, hIcon, 0, 0, 0, null, DI_NORMAL)
}

func getDesktopImage(drawCursor: bool)->Image fail
{
    let x = Env.getSystemMetric(.DesktopX)
    let y = Env.getSystemMetric(.DesktopY)
    let w = Env.getSystemMetric(.DesktopWidth)
    let h = Env.getSystemMetric(.DesktopHeight)
    return try getScreenRectImage(drawCursor, x, y, w, h)
}

// Grab only the requested rectangle (absolute virtual-desktop coordinates). The
// BitBlt cost is proportional to the copied area, so a small or single-monitor
// capture must not pay for the whole multi-monitor desktop.
func getScreenRectImage(drawCursor: bool, x, y, w, h: s32)->Image fail
{
    var result: Image
    try getScreenRectImageInto(&result, drawCursor, x, y, w, h)
    return result
}

// Keeps the caller's pixel allocation when consecutive grabs have the same dimensions.
func getScreenRectImageInto(target: *Image, drawCursor: bool, x, y, w, h: s32) fail
{
    #static if #command == Swag.CompilerCommand.Test
    {
        if target.width != w or target.height != h or target.pixelFormat != .BGRA8 do
            target[] = Image.create(Math.max(w, 1), Math.max(h, 1), .BGRA8)
        return
    }

    let awareness = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE)
    defer discard SetThreadDpiAwarenessContext(awareness)

    let hDesktopWnd = GetDesktopWindow()
    let hDesktopDC  = GetDC(hDesktopWnd)
    defer discard ReleaseDC(hDesktopWnd, hDesktopDC)

    let memDC = try CreateCompatibleDC(hDesktopDC)
    defer catch DeleteDC(memDC)

    // Capture straight into a 32-bit DIB section so the BitBlt lands directly in a
    // CPU-readable buffer. This avoids the extra GetDIBits read-back of a
    // device-dependent bitmap, which is the dominant per-pixel cost when grabbing
    // large areas or the whole multi-monitor virtual desktop.
    // biHeight stays positive (bottom-up) to match the orientation Image expects.
    var bi: BITMAPINFO
    bi.bmiHeader.biSize        = #sizeof(BITMAPINFOHEADER)
    bi.bmiHeader.biWidth       = w
    bi.bmiHeader.biHeight      = h
    bi.bmiHeader.biPlanes      = 1
    bi.bmiHeader.biBitCount    = 32
    bi.bmiHeader.biCompression = BI_RGB

    var bits: *u8?
    let memBMP = try CreateDIBSection(hDesktopDC, &bi, cast(DIB_RGB_COLORS), &bits, null, 0)
    if not memBMP or not bits do
        try failWinError(GetLastError())
    defer catch DeleteObject(cast(memBMP))

    // Keep the DC's original bitmap so we can re-select it before deleting memBMP:
    // GDI refuses to delete an object that is still selected into a DC. The defer
    // below runs (LIFO) before the DeleteObject/DeleteDC defers, restoring the DC
    // first so DeleteObject actually succeeds instead of silently leaking the DIB.
    let oldBMP = SelectObject(memDC, cast(memBMP))
    defer discard SelectObject(memDC, oldBMP)

    try BitBlt(memDC, 0, 0, w, h, hDesktopDC, x, y, SRCCOPY | CAPTUREBLT)

    if drawCursor do
        drawCursorInto(memDC, x, y)

    // Flush the GDI command batch so the DIB memory is fully written before we read it.
    GdiFlush()

    if target.width != w or target.height != h or target.pixelFormat != .BGRA8 do
        target[] = Image.create(w, h, .BGRA8)
    Memory.copy(target.pixels.storage(), unwrap bits, target.byteCount)
}
