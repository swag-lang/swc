#global if #os == Swag.TargetOs.Windows

using Core, Core.Errors, Pixel, Win32, Gdi32

// Reads successive frames from one physical screen area into reusable BGRA8 storage.
// The GDI bitmap and memory DC remain selected until close or reopen.
#[Swag.NoCopy]
struct ScreenFrameSource
{
    x:          s32
    y:          s32
    width:      s32
    height:     s32
    drawCursor: bool
    memoryDC:   HDC
    bitmap:     HBITMAP
    oldBitmap:  HGDIOBJ
    pixels:     *void?
}

impl ScreenFrameSource
{
    func create(drawCursor: bool, x, y, width, height: s32)->ScreenFrameSource fail
    {
        if width <= 0 or height <= 0 or width > 0x7FFFFFFF's32 / 4 do
            fail BadParameterError{"screen frame source needs positive image dimensions"}
        var result: #returntype
        result.x          = x
        result.y          = y
        result.width      = width
        result.height     = height
        result.drawCursor = drawCursor
        return result
    }

    private mtd closeNative()
    {
        if .memoryDC and .oldBitmap do
            discard SelectObject(.memoryDC, .oldBitmap)
        if .bitmap do
            catch DeleteObject(cast(.bitmap))
        if .memoryDC do
            catch DeleteDC(.memoryDC)
        .memoryDC  = null
        .bitmap    = null
        .oldBitmap = null
        .pixels    = null
    }

    private mtd openNative()->bool
    {
        let desktopWnd = GetDesktopWindow()
        let desktopDC  = GetDC(desktopWnd)
        if not desktopDC do
            return false
        defer discard ReleaseDC(desktopWnd, desktopDC)
        var ready = false
        defer
        {
            if not ready do
                .closeNative()
        }

        .memoryDC = catch CreateCompatibleDC(desktopDC) { return false }
        // A positive height gives the bottom-up BGRA layout expected by Image.
        var info: BITMAPINFO
        info.bmiHeader.biSize        = #sizeof(BITMAPINFOHEADER)
        info.bmiHeader.biWidth       = .width
        info.bmiHeader.biHeight      = .height
        info.bmiHeader.biPlanes      = 1
        info.bmiHeader.biBitCount    = 32
        info.bmiHeader.biCompression = BI_RGB
        .bitmap = catch CreateDIBSection(desktopDC, &info, cast(DIB_RGB_COLORS), &.pixels, null, 0) { return false }
        if not .pixels do
            return false
        .oldBitmap = SelectObject(.memoryDC, cast(.bitmap))
        if not .oldBitmap do
            return false
        ready = true
        return true
    }

    mtd opDrop() => .closeNative()

    // Writes bottom-up BGRA8 into `target`, retaining both pixel and GDI storage.
    mtd grabInto(target: *Image) fail
    {
        #static if #command == Swag.CompilerCommand.Test
        {
            if not Env.hasArgument("swag.capture.native-screen=true")
            {
                try getScreenRectImageInto(target, .drawCursor, .x, .y, .width, .height)
                return
            }
        }

        let awareness = SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE)
        defer discard SetThreadDpiAwarenessContext(awareness)
        if not .memoryDC and not .openNative()
        {
            try getScreenRectImageInto(target, .drawCursor, .x, .y, .width, .height)
            return
        }

        // Refresh the desktop DC per grab: it belongs to this thread and can change
        // across a desktop switch, while the selected memory DC and DIB remain reusable.
        let desktopWnd = GetDesktopWindow()
        let desktopDC  = GetDC(desktopWnd)
        if not desktopDC
        {
            .closeNative()
            try getScreenRectImageInto(target, .drawCursor, .x, .y, .width, .height)
            return
        }
        defer discard ReleaseDC(desktopWnd, desktopDC)
        catch BitBlt(.memoryDC, 0, 0, .width, .height, desktopDC, .x, .y, SRCCOPY | CAPTUREBLT)
        {
            .closeNative()
            try getScreenRectImageInto(target, .drawCursor, .x, .y, .width, .height)
            return
        }
        if .drawCursor do
            drawCursorInto(.memoryDC, .x, .y)
        if not GdiFlush()
        {
            .closeNative()
            try getScreenRectImageInto(target, .drawCursor, .x, .y, .width, .height)
            return
        }
        if target.width != .width or target.height != .height or target.pixelFormat != .BGRA8 do
            target[] = Image.create(.width, .height, .BGRA8)
        Memory.copy(target.pixels.storage(), unwrap .pixels, target.byteCount)
    }

    // A display change invalidates the cached GDI objects; the next grab recreates them.
    mtd reopen() fail => .closeNative()
}
