#global #if #os == Swag.TargetOs.Windows
using Core, Win32, Gdi32

internal
{
    var g_HitTest: POINT
    var g_Hit:     HWND
    var g_Ignore:  HWND

    func enumProc(hWnd: HWND, _lParam: LPARAM)->BOOL
    {
        if !IsWindowVisible(hWnd) do
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
            let n          = GetClassNameA(hWnd, &className[0], 256)
            let str        = String.from(@mkstring(&className[0], n))

            let systemClasses = [
                "Windows.UI.Core.CoreWindow", // UWP system windows
                "ApplicationFrameWindow"] // UWP app frames

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

func getWndRectAtPos(srf: *Surface, x, y: f32)->Math.Rectangle
{
    let awareness = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE)
    defer discard SetThreadDpiAwarenessContext(awareness)

    g_HitTest.x = cast() x
    g_HitTest.y = cast() y

    g_Hit    = null
    g_Ignore = srf.hWnd
    EnumWindows(cast() &enumProc, 0)
    if !g_Hit do
        return {}

    for
    {
        var pt1: POINT
        pt1.x = g_HitTest.x
        pt1.y = g_HitTest.y
        ScreenToClient(g_Hit, &pt1)
        let child = ChildWindowFromPointEx(g_Hit, pt1, CWP_SKIPINVISIBLE | CWP_SKIPDISABLED | CWP_SKIPTRANSPARENT)
        if !child or child == g_Hit do
            break
        g_Hit = child
    }

    if !g_Hit do
        return {}

    var r: RECT
    GetWindowRect(g_Hit, &r)
    return Math.Rectangle{r.left, r.top, r.right - r.left, r.bottom - r.top}
}

func getBackgroundWndRect()->Math.Rectangle
{
    let hit = GetForegroundWindow()
    if !hit do
        return {}

    let awareness = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE)
    defer discard SetThreadDpiAwarenessContext(awareness)

    var r: RECT
    GetWindowRect(hit, &r)
    return Math.Rectangle{r.left, r.top, r.right - r.left, r.bottom - r.top}
}

// Draw the current mouse cursor into the device context, accounting for the
// cursor hotspot and the offset of the captured rect on the virtual desktop.
func drawCursorInto(memDC: HDC, offsetX, offsetY: s32)
{
    var ci: CURSORINFO
    ci.cbSize = #sizeof(CURSORINFO)
    if !GetCursorInfo(&ci) do
        return
    if !(ci.flags & CURSOR_SHOWING) or !ci.hCursor do
        return

    let hIcon = cast(HICON) ci.hCursor

    var ii: ICONINFO
    catch GetIconInfo(hIcon, &ii)
    defer
    {
        if ii.hbmMask do
            catch DeleteObject(cast() ii.hbmMask)
        if ii.hbmColor do
            catch DeleteObject(cast() ii.hbmColor)
    }

    let x = ci.ptScreenPos.x - offsetX - cast(s32) ii.xHotspot
    let y = ci.ptScreenPos.y - offsetY - cast(s32) ii.yHotspot
    DrawIconEx(memDC, x, y, hIcon, 0, 0, 0, null, DI_NORMAL)
}

func getDesktopImage(drawCursor: bool)->Image throw
{
    let x = Env.getMetric(.DesktopX)
    let y = Env.getMetric(.DesktopY)
    let w = Env.getMetric(.DesktopWidth)
    let h = Env.getMetric(.DesktopHeight)
    return getScreenRectImage(drawCursor, x, y, w, h)
}

// Grab only the requested rectangle (absolute virtual-desktop coordinates). The
// BitBlt cost is proportional to the copied area, so a small or single-monitor
// capture must not pay for the whole multi-monitor desktop.
func getScreenRectImage(drawCursor: bool, x, y, w, h: s32)->Image throw
{
    #if #command == Swag.CompilerCommand.Test
    {
        return Image.create(Math.max(w, 1), Math.max(h, 1), .BGRA8)
    }

    let awareness = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE)
    defer discard SetThreadDpiAwarenessContext(awareness)

    let hDesktopWnd = GetDesktopWindow()
    let hDesktopDC  = GetDC(hDesktopWnd)
    defer discard ReleaseDC(hDesktopWnd, hDesktopDC)

    let memDC = CreateCompatibleDC(hDesktopDC)
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

    var bits: *u8 = undefined
    let memBMP = CreateDIBSection(hDesktopDC, &bi, cast() DIB_RGB_COLORS, &bits, null, 0)
    if !memBMP or !bits do
        throw Swag.SystemError{"CreateDIBSection failed"}
    defer catch DeleteObject(cast() memBMP)

    // Keep the DC's original bitmap so we can re-select it before deleting memBMP:
    // GDI refuses to delete an object that is still selected into a DC. The defer
    // below runs (LIFO) before the DeleteObject/DeleteDC defers, restoring the DC
    // first so DeleteObject actually succeeds instead of silently leaking the DIB.
    let oldBMP = SelectObject(memDC, cast() memBMP)
    defer discard SelectObject(memDC, oldBMP)

    BitBlt(memDC, 0, 0, w, h, hDesktopDC, x, y, SRCCOPY | CAPTUREBLT)

    if drawCursor do
        drawCursorInto(memDC, x, y)

    // Flush the GDI command batch so the DIB memory is fully written before we read it.
    GdiFlush()

    var result = Image.create(w, h, PixelFormat.BGRA8)
    Memory.copy(result.pixels.buffer, bits, result.size)
    return result
}
