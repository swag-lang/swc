#global if #os == Swag.TargetOs.Linux

using Core, Pixel, Gui

// X11 coordinates are physical pixels and need no thread-local DPI conversion.
struct CapturePlatformScope {}

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
    result.title     = native.title
    result.className = native.className
    if not native.processId do
        return result
    let path  = Format.toString("/proc/%/exe", native.processId)
    var buffer: [32768] u8
    let count = Linux.readlinkat(Linux.AT_FDCWD, path.buffer, &buffer[0], buffer.count)
    if count <= 0 or count >= cast(s64, buffer.count) do
        return result
    let value = buffer[until cast(u64, count)]
    if not Utf8.isValid(value) do
        return result
    result.executable  = cast(string, value)
    result.application = Path.fileNameWithoutExtension(result.executable) orelse ""
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
