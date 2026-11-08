using Core, Pixel

// What a screenshot covers.
enum CaptureMode
{
    Area             // Interactive rectangle, drawn by the user over the frozen desktop.
    LastArea         // The rectangle of the previous area capture.
    FullScreen       // The whole virtual desktop, every monitor at once.
    Monitor          // One monitor, named by its index in `MainWnd.monitors`.
    ActiveWindow     // The window that was in the foreground before the capture.
}

// Best-effort identity of the window represented by a capture rectangle.
struct CaptureWindowInfo
{
    application: String
    executable:  String
    title:       String
    className:   String
}

var g_StartGrabX:     f32
var g_StartGrabY:     f32
var g_EndGrabX:       f32
var g_EndGrabY:       f32
var g_DesktopX:       s32
var g_DesktopY:       s32
var g_ScreenWidth:    s32
var g_ScreenHeight:   s32
var g_Exit:           bool
var g_GrabDone:       bool
var g_DesktopTexture: Texture
var g_CaptureWindow:  CaptureWindowInfo

// The cursor as it stood when the desktop was grabbed: a patch of the desktop with the cursor
// drawn in, laid over the grabbed picture when the capture keeps the cursor, and the same pixels
// without it, which take it out again. The overlay shows it or not as the option changes.
const CursorPatchSide = 192's32     // Side of the patch, in physical pixels.
const CursorPatchLead = 64's32      // Part of the patch above and left of the pointer.

var g_CursorPatch:     Image
var g_CursorPatchRect: Math.Rectangle     // In physical virtual-desktop pixels.
var g_CursorBare:      Image     // The desktop under the patch, without the cursor.
var g_CursorBareRect:  Math.Rectangle     // The part of the patch inside the desktop.
var g_CursorTexture:   Texture

// What the next capture keeps of the aimed area: the command that opens the overlay chooses it,
// and `Tab` changes it before the capture is taken.
var g_CaptureMedia: CaptureMedia

func getGrabRect()->Math.Rectangle
{
    var result: #returntype
    result.x      = Math.min(g_StartGrabX, g_EndGrabX)
    result.y      = Math.min(g_StartGrabY, g_EndGrabY)
    result.width  = Math.max(g_StartGrabX, g_EndGrabX) - result.x
    result.height = Math.max(g_StartGrabY, g_EndGrabY) - result.y
    return result
}

// Returns `rect`, in physical pixels relative to the virtual desktop, in absolute screen pixels.
func desktopToScreenRect(rect: Math.Rectangle)->Math.Rectangle => {g_DesktopX + rect.x, g_DesktopY + rect.y, rect.width, rect.height}

func screenToDesktopRect(rect: Math.Rectangle)->Math.Rectangle
{
    var result = rect
    result.x -= g_DesktopX
    result.y -= g_DesktopY
    return result
}

// Grabs the cursor patch around the pointer over `desktop`, the grab of the whole virtual desktop
// without the cursor; no patch when it cannot be read.
func grabCursorPatch(desktop: Image)
{
    clearCursorPatch()
    let pos = Input.mousePosition()
    let x   = cast(s32, pos.x) - CursorPatchLead
    let y   = cast(s32, pos.y) - CursorPatchLead
    g_CursorPatch = catch getScreenRectImage(true, x, y, CursorPatchSide, CursorPatchSide)
    {
        g_CursorPatch = {}
        return
    }

    g_CursorPatchRect = {cast(f32, x - g_DesktopX), cast(f32, y - g_DesktopY), cast(f32, CursorPatchSide), cast(f32, CursorPatchSide)}

    var bare = Math.Rectangle.intersect(g_CursorPatchRect, {0, 0, cast(f32, desktop.width), cast(f32, desktop.height)})
    if bare.isEmpty()
    {
        clearCursorPatch()
        return
    }

    g_CursorBareRect = bare
    g_CursorBare     = desktop.cropped(bare)
}

// Forgets the cursor patch.
func clearCursorPatch()
{
    g_CursorPatch     = {}
    g_CursorPatchRect = {}
    g_CursorBare      = {}
    g_CursorBareRect  = {}
}

// Puts the cursor in `img`, a grab of the whole virtual desktop, or takes it out again.
func setCursorIn(img: *Image, shown: bool)
{
    if not g_CursorPatch.width or not g_CursorBare.width do
        return

    // An image counts its rows from the bottom.
    if shown
    {
        let x = cast(s32, g_CursorPatchRect.x)
        let y = img.height - cast(s32, g_CursorPatchRect.y) - g_CursorPatch.height
        img.mix(g_CursorPatch, x, y, .Copy)
    }
    else
    {
        let x = cast(s32, g_CursorBareRect.x)
        let y = img.height - cast(s32, g_CursorBareRect.y) - g_CursorBare.height
        img.mix(g_CursorBare, x, y, .Copy)
    }
}

func waitForCapture()->bool
{
    g_Exit     = false
    g_GrabDone = false
    while not g_Exit do
        g_App.runFrame()
    return g_GrabDone
}

// Grabs the desktop and covers it with the overlay where the reader picks the area to capture.
// Returns the grabbed image and the overlay, or a null overlay when the reader cancels.
func performScreenCapture(main: *MainWnd)->{ img: Image, sf: *Surface? } fail
{
    g_App.setGlobalHotKeysEnabled(false)
    defer g_App.setGlobalHotKeysEnabled()

    g_CaptureWindow = {}

    var result: #returntype

    // The desktop is grabbed without the cursor, and the cursor apart, so the overlay can still
    // put it in or leave it out.
    result.img = try getDesktopImage(false)
    grabCursorPatch(result.img)
    g_DesktopTexture = g_App.renderer.addImage(result.img)
    defer g_App.renderer.removeTexture(&g_DesktopTexture)
    if g_CursorPatch.width do
        g_CursorTexture = g_App.renderer.addImage(g_CursorPatch)
    defer
    {
        if g_CursorTexture.isValid() do
            g_App.renderer.removeTexture(&g_CursorTexture)
    }

    // The overlay must cover the virtual desktop in *physical* pixels, and the
    // desktop metrics are physical. Creation sizes are logical, so create small and
    // place the surface through setPosition, which works in physical screen pixels.
    result.sf = try g_App.createSurface(g_DesktopX, g_DesktopY, 16, 16, .ToolWindow | .TopMost | .NoShadow)
    let sf = result.sf
    sf.setPosition(Math.Rectangle{cast(f32, g_DesktopX), cast(f32, g_DesktopY), cast(f32, g_ScreenWidth), cast(f32, g_ScreenHeight)})

    with let captureWnd = Wnd.create'CaptureRectWnd(sf.wnd)
    {
        .main        = main
        .cursor      = Cursor.from(CursorShape.Cross)
        .focusPolicy = .Click
        .setPosition(0, 0, sf.size().x, sf.size().y)
    }

    sf.setView(captureWnd)
    captureWnd.setFocus()
    sf.show()
    sf.bringToFront()
    captureWnd.captureMouse()

    if not waitForCapture()
    {
        sf.destroy()
        result.sf = null
    }

    return result
}

// Builds an in-place editor for the grabbed area, or crops it immediately when that mode is off.
func performInPlaceEdit(img: Image, surface: *Surface, main: *MainWnd)->*Capture? fail
{
    let grabRect = getGrabRect()

    with let capture = Memory.new'Capture()
    {
        .width          = cast(s32, grabRect.width)
        .height         = cast(s32, grabRect.height)
        .backImg        = img
        .backImagePos.x = -grabRect.x
        .backImagePos.y = -grabRect.y
        .inPlaceEdit    = true
        .setScreenSource(g_CaptureWindow.application, g_CaptureWindow.executable, g_CaptureWindow.title, g_CaptureWindow.className)
    }

    if main.captureOptions.captureCursor do
        setCursorIn(&capture.backImg, true)

    // A picture can leave at once; a recording always waits on the zone to be started.
    if not main.captureOptions.inPlaceEdit and g_CaptureMedia == .Picture
    {
        capture.cropToGrab()
        surface.destroy()
        return capture
    }

    let inPlaceWnd = InPlaceEditWnd.create(capture, main, surface.wnd)
    surface.setView(inPlaceWnd)

    inPlaceWnd.newMain.fileDlgState = main.fileDlgStateInPlace
    defer main.fileDlgStateInPlace = inPlaceWnd.newMain.fileDlgState

    if not waitForCapture()
    {
        surface.destroy()
        return null
    }

    inPlaceWnd.editWnd.editView.capture = null
    surface.destroy()
    if g_CaptureMedia == .Animation do
        return try recordZone(main, capture)
    return capture
}

// Records the zone `zone` was taken from, where it now stands, and returns the new animation
// capture, or null when nothing was kept. What was drawn on the zone annotates the whole
// recording. `zone` is freed.
func recordZone(main: *MainWnd, zone: *Capture)->*Capture? fail
{
    defer Memory.delete(zone)

    let area   = Math.Rectangle{-zone.backImagePos.x, -zone.backImagePos.y, cast(f32, zone.width), cast(f32, zone.height)}
    let result = try Recorder.record(main, desktopToScreenRect(area))
    if not result do
        return null

    zone.selection.clear()
    zone.gizmo.sigHasChanged = null
    result.forms             = #move zone.forms
    result.nextStepIndex     = zone.nextStepIndex
    result.nextGroupId       = zone.nextGroupId
    for form in result.forms do
        form.capture = result
    return result
}

func captureRect(main: *MainWnd)->*Capture? fail
{
    defer clearCursorPatch()
    let {img, sf} = try performScreenCapture(main)
    if not sf do
        return null
    return try performInPlaceEdit(img, sf, main)
}

// Sets the grab rectangle for a non-interactive capture mode.
//
// Returns false when the mode has no fixed rectangle, or when `monitorIndex` names no
// connected monitor: the caller then falls back to the interactive selector.
func setGrabBounds(main: *MainWnd, captureMode: CaptureMode, monitorIndex: u64)->bool
{
    switch captureMode
    {
    case .FullScreen:
        g_StartGrabX, g_StartGrabY = 0
        g_EndGrabX = g_ScreenWidth
        g_EndGrabY = g_ScreenHeight

    case .ActiveWindow:
        let window = getBackgroundWindow()
        let r      = screenToDesktopRect(window.rect)
        if r.isEmpty() do
            return false
        g_CaptureWindow = window.info
        g_StartGrabX    = r.x
        g_StartGrabY    = r.y
        g_EndGrabX      = r.right()
        g_EndGrabY      = r.bottom()

    case .Monitor:
        if monitorIndex >= main.monitors.count do
            return false
        let rect = screenToDesktopRect(main.monitors[monitorIndex].physicalBounds)
        g_StartGrabX = rect.x
        g_StartGrabY = rect.y
        g_EndGrabX   = rect.x + rect.width
        g_EndGrabY   = rect.y + rect.height

    case .LastArea:
        if g_EndGrabX == g_StartGrabX or g_EndGrabY == g_StartGrabY do
            return false
        let rect       = getGrabRect()
        let screenRect = Math.Rectangle{g_DesktopX + rect.x, g_DesktopY + rect.y, rect.width, rect.height}
        g_CaptureWindow = getCaptureWindowForRect(unwrap main.surface, screenRect)

    case .Area:
        return false
    }

    return true
}

// Runs one capture in `captureMode`, `monitorIndex` naming the monitor of `.Monitor`.
func screenShot(main: *MainWnd, captureMode: CaptureMode, monitorIndex: u64 = 0) fail
{
    var platformScope = beginCapturePlatformScope()
    defer platformScope.close()

    // Keep the editor out of the desktop pixels unless the option says otherwise.
    let surface   = unwrap main.surface
    let wasHidden = surface.isHidden
    if main.captureOptions.hideEditorBefore and not surface.isHidden and not surface.isMinimized do
        surface.hide()

    // A grab that fails gives the editor back instead of leaving it hidden for good.
    defer #fail
    {
        if not wasHidden do
            surface.show()
    }

    // Let the configured capture delay elapse before reading the desktop.
    if main.captureOptions.delay do
        Threading.Thread.sleep(Time.Duration.fromSeconds(main.captureOptions.delay))

    g_DesktopX      = Env.getSystemMetric(.DesktopX)
    g_DesktopY      = Env.getSystemMetric(.DesktopY)
    g_ScreenWidth   = Env.getSystemMetric(.DesktopWidth)
    g_ScreenHeight  = Env.getSystemMetric(.DesktopHeight)
    g_CaptureWindow = {}

    var capture: *Capture?
    if not setGrabBounds(main, captureMode, monitorIndex)
    {
        capture = try captureRect(main)
    }
    else
    {
        let grabRect = getGrabRect()
        let wGrab    = Math.max(grabRect.width, 8)
        let hGrab    = Math.max(grabRect.height, 8)

        if g_CaptureMedia == .Animation
        {
            capture = try Recorder.record(main, desktopToScreenRect({grabRect.x, grabRect.y, wGrab, hGrab}))
        }
        else
        {
            // Grab bounds are desktop-relative; blit only that rectangle instead of
            // capturing the whole virtual desktop and cropping.
            var image = try getScreenRectImage(main.captureOptions.captureCursor,
                                               g_DesktopX + cast(s32, grabRect.x),
                                               g_DesktopY + cast(s32, grabRect.y),
                                               cast(s32, wGrab),
                                               cast(s32, hGrab))

            with capture = Memory.new'Capture()
            {
                .width, .widthOrg   = image.width
                .height, .heightOrg = image.height
                .backImg = image
                .setScreenSource(g_CaptureWindow.application, g_CaptureWindow.executable, g_CaptureWindow.title, g_CaptureWindow.className)
            }

            if main.captureOptions.sendToClipboard do
                Clipboard.addImage(capture.backImg)
            if not main.captureOptions.sendToEditor
            {
                Memory.delete(capture)
                capture = null
            }
        }
    }

    if capture or not wasHidden
    {
        if surface.isMinimized do
            surface.showNormal()
        else do
            surface.show()
    }

    if capture do
        main.newCapture(capture.backImg, "", capture)
}
