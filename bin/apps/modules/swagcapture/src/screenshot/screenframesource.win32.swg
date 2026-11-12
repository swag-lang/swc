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
    accelerated: *Screen.Source?
    triedAccelerated: bool
    acceleratedX: s32
    acceleratedY: s32
    fresh:        bool
    dcMicroseconds:    u64
    blitMicroseconds:  u64
    flushMicroseconds: u64
    copyMicroseconds:  u64
    cursorMicroseconds: u64
    cursorBackup: Array'u8
    cursorTarget, cursorStorage: u64
    cursorLeft, cursorTop, cursorRight, cursorBottom: s32
    cursorRendered: Array'u8
    cursorRenderedLeft, cursorRenderedTop, cursorRenderedRight, cursorRenderedBottom: s32
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
        if .accelerated
        {
            Memory.delete(.accelerated)
            .accelerated = null
        }
        .triedAccelerated = false
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
        .cursorBackup.clear()
        .cursorRendered.clear()
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
    mtd grabInto(target: *Image, copyUnchanged: bool = true) fail
    {
        .fresh = true
        #static if #command == Swag.CompilerCommand.Test
        {
            if not Env.hasArgument("swag.capture.native-screen=true")
            {
                try getScreenRectImageInto(target, .drawCursor, .x, .y, .width, .height)
                return
            }
        }

        if .accelerated and (.x != .acceleratedX or .y != .acceleratedY)
        {
            Memory.delete(.accelerated)
            .accelerated = null
            .triedAccelerated = false
        }
        if not .triedAccelerated
        {
            .triedAccelerated = true
            catch
            {
                .accelerated = Memory.new'Screen.Source()
                .accelerated[] = try Screen.Source.open({.x, .y, .width, .height, false})
                .acceleratedX = .x
                .acceleratedY = .y
            }
            {
                if .accelerated
                {
                    Memory.delete(.accelerated)
                    .accelerated = null
                }
            }
        }
        if .accelerated
        {
            catch
            {
                if .drawCursor do
                    .restoreCursorPixels(target)
                .fresh = try .accelerated.grabInto(target,
                                                   copyUnchanged: copyUnchanged,
                                                   updateChangedOnly: not copyUnchanged)
                if .drawCursor
                {
                    let cursorStart = Time.monotonicMicroseconds()
                    let cursorChanged = .drawCursorOnImage(target)
                    .cursorMicroseconds += Time.monotonicMicroseconds() - cursorStart
                    .fresh = .fresh or cursorChanged
                }
                return
            }
            {
                // A desktop switch can invalidate duplication. This frame uses GDI;
                // the next one retries after the source is reopened.
                discard catch .accelerated.reopen()
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
        let dcStart = Time.monotonicMicroseconds()
        let desktopWnd = GetDesktopWindow()
        let desktopDC  = GetDC(desktopWnd)
        .dcMicroseconds += Time.monotonicMicroseconds() - dcStart
        if not desktopDC
        {
            .closeNative()
            try getScreenRectImageInto(target, .drawCursor, .x, .y, .width, .height)
            return
        }
        defer discard ReleaseDC(desktopWnd, desktopDC)
        let blitStart = Time.monotonicMicroseconds()
        catch BitBlt(.memoryDC, 0, 0, .width, .height, desktopDC, .x, .y, SRCCOPY | CAPTUREBLT)
        {
            .closeNative()
            try getScreenRectImageInto(target, .drawCursor, .x, .y, .width, .height)
            return
        }
        .blitMicroseconds += Time.monotonicMicroseconds() - blitStart
        if .drawCursor do
            drawCursorInto(.memoryDC, .x, .y)
        let flushStart = Time.monotonicMicroseconds()
        if not GdiFlush()
        {
            .closeNative()
            try getScreenRectImageInto(target, .drawCursor, .x, .y, .width, .height)
            return
        }
        .flushMicroseconds += Time.monotonicMicroseconds() - flushStart
        if target.width != .width or target.height != .height or target.pixelFormat != .BGRA8 do
            target[] = Image.create(.width, .height, .BGRA8)
        let copyStart = Time.monotonicMicroseconds()
        Memory.copy(target.pixels.storage(), unwrap .pixels, target.byteCount)
        .copyMicroseconds += Time.monotonicMicroseconds() - copyStart
    }

    // Saves and restores only the pixels under the pointer so DXGI can keep mirroring changed
    // desktop regions into the same caller image without leaving a cursor trail.
    internal mtd saveCursorPixels(target: *Image, left, top, right, bottom: s32)
    {
        let rowBytes = cast(u64, right - left) * 4
        .cursorBackup.resize(rowBytes * cast(u64, bottom - top))
        .cursorTarget  = cast(u64, target)
        .cursorStorage = cast(u64, target.pixels.storage())
        .cursorLeft   = left
        .cursorTop    = top
        .cursorRight  = right
        .cursorBottom = bottom
        for row in cast(u64, bottom - top)
        {
            let offset = cast(u64, .height - 1 - top - cast(s32, row)) * cast(u64, target.rowStride) +
                         cast(u64, left) * 4
            Memory.copy(.cursorBackup.storage() + row * rowBytes,
                        target.pixels.storage() + offset, rowBytes)
        }
    }

    internal mtd restoreCursorPixels(target: *Image)
    {
        if .cursorBackup.isEmpty() do
            return
        if cast(u64, target) == .cursorTarget and
           cast(u64, target.pixels.storage()) == .cursorStorage and
           target.width == .width and target.height == .height
        {
            let rowBytes = cast(u64, .cursorRight - .cursorLeft) * 4
            for row in cast(u64, .cursorBottom - .cursorTop)
            {
                let offset = cast(u64, .height - 1 - .cursorTop - cast(s32, row)) * cast(u64, target.rowStride) +
                             cast(u64, .cursorLeft) * 4
                Memory.copy(target.pixels.storage() + offset,
                            .cursorBackup.storage() + row * rowBytes, rowBytes)
            }
        }
        .cursorBackup.clear()
    }

    // A stationary pointer over unchanged desktop pixels is the same encoded picture.
    internal mtd cursorPixelsChanged(target: *Image, left, top, right, bottom: s32)->bool
    {
        let rowBytes = cast(u64, right - left) * 4
        let rows = cast(u64, bottom - top)
        let bytes = rowBytes * rows
        var changed = .cursorRendered.count != bytes or
                      .cursorRenderedLeft != left or .cursorRenderedTop != top or
                      .cursorRenderedRight != right or .cursorRenderedBottom != bottom
        if not changed
        {
            for row in rows
            {
                let offset = cast(u64, .height - 1 - top - cast(s32, row)) * cast(u64, target.rowStride) +
                             cast(u64, left) * 4
                if Memory.compare(target.pixels.storage() + offset,
                                  .cursorRendered.storage() + row * rowBytes, rowBytes) != 0
                {
                    changed = true
                    break
                }
            }
        }
        .cursorRendered.resize(bytes)
        .cursorRenderedLeft   = left
        .cursorRenderedTop    = top
        .cursorRenderedRight  = right
        .cursorRenderedBottom = bottom
        for row in rows
        {
            let offset = cast(u64, .height - 1 - top - cast(s32, row)) * cast(u64, target.rowStride) +
                         cast(u64, left) * 4
            Memory.copy(.cursorRendered.storage() + row * rowBytes,
                        target.pixels.storage() + offset, rowBytes)
        }
        return changed
    }

    private mtd clearCursorRendered()->bool
    {
        let changed = not .cursorRendered.isEmpty()
        .cursorRendered.clear()
        return changed
    }

    // The pointer is drawn onto the DXGI readback without a desktop BitBlt.
    private mtd drawCursorOnImage(target: *Image)->bool
    {
        var cursor: CURSORINFO
        cursor.cbSize = #sizeof(CURSORINFO)
        if not GetCursorInfo(&cursor) or not (cursor.flags & CURSOR_SHOWING) or not cursor.hCursor do
            return .clearCursorRendered()
        let icon = cast(HICON, cursor.hCursor)
        var info: ICONINFO
        catch GetIconInfo(icon, &info) { return .clearCursorRendered(); }
        defer
        {
            if info.hbmMask do
                catch DeleteObject(cast(info.hbmMask))
            if info.hbmColor do
                catch DeleteObject(cast(info.hbmColor))
        }
        var bitmap: BITMAP
        let iconBitmap = info.hbmColor ? info.hbmColor : info.hbmMask
        catch GetObjectW(cast(HANDLE, iconBitmap), #sizeof(BITMAP), cast(*void, &bitmap)) { return .clearCursorRendered(); }
        let iconHeight = info.hbmColor ? bitmap.bmHeight : bitmap.bmHeight / 2
        let left = Math.max(0's32, cursor.ptScreenPos.x - .x - cast(s32, info.xHotspot))
        let top = Math.max(0's32, cursor.ptScreenPos.y - .y - cast(s32, info.yHotspot))
        let right = Math.min(.width, cursor.ptScreenPos.x - .x - cast(s32, info.xHotspot) + bitmap.bmWidth)
        let bottom = Math.min(.height, cursor.ptScreenPos.y - .y - cast(s32, info.yHotspot) + iconHeight)
        if right <= left or bottom <= top do
            return .clearCursorRendered()
        if not .memoryDC and not .openNative() do
            return .clearCursorRendered()
        let source = target.pixels.storage()
        let overlay = assume cast([*] u8, .pixels)
        let rowBytes = cast(u64, .width) * 4
        let copyBytes = cast(u64, right - left) * 4
        .saveCursorPixels(target, left, top, right, bottom)
        for row in cast(u64, bottom - top)
        {
            let y = top + cast(s32, row)
            let offset = (cast(u64, .height - 1 - y) * rowBytes) + cast(u64, left) * 4
            Memory.copy(overlay + offset, source + offset, copyBytes)
        }
        let iconX = cursor.ptScreenPos.x - .x - cast(s32, info.xHotspot)
        let iconY = cursor.ptScreenPos.y - .y - cast(s32, info.yHotspot)
        DrawIconEx(.memoryDC, iconX, iconY, icon, 0, 0, 0, null, DI_NORMAL)
        if GdiFlush()
        {
            for row in cast(u64, bottom - top)
            {
                let y = top + cast(s32, row)
                let offset = (cast(u64, .height - 1 - y) * rowBytes) + cast(u64, left) * 4
                Memory.copy(source + offset, overlay + offset, copyBytes)
            }
            return .cursorPixelsChanged(target, left, top, right, bottom)
        }
        .cursorBackup.clear()
        return .clearCursorRendered()
    }

    // A display change invalidates the cached GDI objects; the next grab recreates them.
    mtd reopen() fail
    {
        .closeNative()
        .triedAccelerated = false
    }
}
