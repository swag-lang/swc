#global if #os == Swag.TargetOs.Linux

// X11 root captures include application windows. The controls are kept outside the crop.
func excludeCaptureChrome(_: *Surface) {}

// X11 has no display-affinity contract. If the pill cannot fit outside the crop, unmap its
// native window for the root read and map it immediately afterwards. The checked requests
// order both operations with the separate capture connection, without changing GUI state.
func captureRecordingFrame(drawCursor: bool, area: Math.Rectangle, chrome: *Surface?, x, y, w, h: s32)->Image fail
{
    if not chrome or not chrome.position.intersects(area) do
        return try getScreenRectImage(drawCursor, x, y, w, h)

    let drawable = catch chrome.xcbDrawable()
    {
        return try getScreenRectImage(drawCursor, x, y, w, h)
    }
    return try captureRecordingFrameWithWindow(drawCursor, drawable, x, y, w, h)
}

// The native part is also exercised with a real test window over another window.
func captureRecordingFrameWithWindow(drawCursor: bool, drawable: Env.XcbDrawable, x, y, w, h: s32)->Image fail
{
    let library = Linux.dlopen("libxcb.so.1".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
    if not library do
        return try getScreenRectImage(drawCursor, x, y, w, h)
    defer discard Linux.dlclose(unwrap library)

    let unmap = try X11Capture.symbol'Linux.xcb_unmap_window_checked_fn(library, "xcb_unmap_window_checked")
    let map = try X11Capture.symbol'Linux.xcb_map_window_checked_fn(library, "xcb_map_window_checked")
    let check = try X11Capture.symbol'Linux.xcb_request_check_fn(library, "xcb_request_check")
    let connection = unwrap drawable.connection
    let hiddenError = check(connection, unmap(connection, drawable.window))
    if hiddenError
    {
        Linux.free(hiddenError)
        return try getScreenRectImage(drawCursor, x, y, w, h)
    }
    defer
    {
        let shownError = check(connection, map(connection, drawable.window))
        if shownError do
            Linux.free(shownError)
    }

    return try getScreenRectImage(drawCursor, x, y, w, h)
}

using Core, Pixel, Gui

// X11 coordinates are physical pixels and need no thread-local DPI conversion.
struct CapturePlatformScope {}

impl CapturePlatformScope
{
    mtd close() {}
}

func beginCapturePlatformScope()->CapturePlatformScope => {}

func getDesktopImage(drawCursor: bool)->Image fail
{
    var capture = try X11Capture.create()
    return try capture.image(drawCursor, 0, 0, capture.screen.width_in_pixels, capture.screen.height_in_pixels)
}

func getScreenRectImage(drawCursor: bool, x, y, w, h: s32)->Image fail
{
    var capture = try X11Capture.create()
    return try capture.image(drawCursor, x, y, w, h)
}

// Process identity is best-effort: X11 clients need not publish a PID, and procfs may deny access.
func captureWindowInfo(capture: *X11Capture, window: u32)->CaptureWindowInfo
{
    var result: #returntype
    let native = capture.windowInfo(window)
    result.nativeWindow = window
    result.title     = native.title
    result.className = native.className
    if not native.processId do
        return result
    let path  = Format.toString("/proc/%/exe", native.processId)
    var buffer: [32768] u8
    let count = Linux.readlinkat(Linux.AT_FDCWD, path.storage(), &buffer[0], buffer.count)
    if count <= 0 or count >= cast(s64, buffer.count) do
        return result
    let value = buffer[until cast(u64, count)]
    if not Utf8.isValid(value) do
        return result
    result.executable  = cast(string, value)
    result.application = Path.fileNameWithoutExtension(result.executable) orelse ""
    return result
}

// Reads a live X11 window frame and whether it remains mapped to the desktop.
func getCaptureWindowBounds(id: u64)->{rect: Math.Rectangle, visible: bool, exists: bool}
{
    var result: #returntype
    if not id do
        return result
    var capture = catch X11Capture.create() { return result }
    let window = cast(u32, id)
    result.rect = capture.windowRect(window)
    result.exists = not result.rect.isEmpty()
    result.visible = result.exists and capture.windowIsViewable(window)
    return result
}

func getCaptureWindowAtPos(surface: *Surface, x, y: f32)->{ rect: Math.Rectangle, info: CaptureWindowInfo }
{
    var result: #returntype
    var capture = catch X11Capture.create() { return result }
    let overlay = catch surface.xcbDrawable() { return result }
    let window  = capture.windowAt(overlay.window, x, y)
    if window
    {
        result.rect = capture.windowRect(window)
        result.info = captureWindowInfo(&capture, window)
    }

    return result
}

func getCaptureWindowForRect(surface: *Surface, rect: Math.Rectangle)->CaptureWindowInfo
{
    var capture = catch X11Capture.create() { return {} }
    let overlay = catch surface.xcbDrawable() { return {} }
    let window  = capture.windowAt(overlay.window, rect.horzCenter(), rect.vertCenter())
    if not window do
        return {}
    let bounds = capture.windowRect(window)
    if rect.x < bounds.x or
       rect.y < bounds.y or
       rect.right() > bounds.right() or
       rect.bottom() > bounds.bottom() do
        return {}
    return captureWindowInfo(&capture, window)
}

func getBackgroundWindow()->{ rect: Math.Rectangle, info: CaptureWindowInfo }
{
    var result: #returntype
    var capture = catch X11Capture.create() { return result }
    let window  = capture.activeWindow()
    if window
    {
        result.rect = capture.windowRect(window)
        result.info = captureWindowInfo(&capture, window)
    }

    return result
}
