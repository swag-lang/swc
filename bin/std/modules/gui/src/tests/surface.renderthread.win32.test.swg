#global if #os == Swag.TargetOs.Windows
#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Win32, Ogl

struct PlacementObservation
{
    surface:           *Surface
    hides:             u32
    prematureOverlays: u32
    consumedFrames:    u32
}

// Observe the native transaction itself: checking visibility after it returns misses a hide/show.
#[Swag.CallingConvention(.C)]
func observePlacementVisibility(hWnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM, subclassId: UINT_PTR, data: DWORD_PTR)->LRESULT
{
    let observation = cast(*PlacementObservation) data
    if msg == WM_WINDOWPOSCHANGING
    {
        let next = cast(*WINDOWPOS) cast #bit (u64) lParam
        if next.flags & SWP_HIDEWINDOW do
            observation.hides += 1
        if (next.flags & SWP_NOSIZE) == 0
        {
            let overlay = FindWindowA("Swag.Gui.PlacementOverlay".buffer, null)
            if overlay and IsWindowVisible(overlay)
            {
                var current, preview: RECT
                let hasCurrent = GetWindowRect(hWnd, &current)
                let hasPreview = GetWindowRect(overlay, &preview)
                if not hasCurrent or not hasPreview or current.left != preview.left or current.top != preview.top or current.right != preview.right or current.bottom != preview.bottom do
                    observation.prematureOverlays += 1
            }
        }
    }

    let prepared = msg == WM_SIZE and observation.surface.inDiscretePlacement and observation.surface.preparedFrame
    let result   = DefSubclassProc(hWnd, msg, wParam, lParam)
    if prepared and not observation.surface.preparedFrame do
        observation.consumedFrames += 1
    return result
}

// Full-screen placement and maximize/restore preserve native visibility and the previous image
// until the final frame is ready, including when another transition immediately follows.
#[Swag.TestTag("integration.host.windows")]
#test
{
    var app: Application
    let surface = expect app.createSurface(40, 40, 640, 400, surfaceId: "gui-placement-visibility-test")!
    surface.show()
    let normal      = surface.position
    let monitor     = Env.monitorForRectangle(normal).physicalBounds
    var observation = PlacementObservation{surface: surface}
    let hooked      = SetWindowSubclass(surface.win32Handle(), &observePlacementVisibility, 1, cast(u64) &observation)
    Swag.assert(hooked)
    defer discard RemoveWindowSubclass(surface.win32Handle(), &observePlacementVisibility, 1)

    for fromMaximized in [false, true]
    {
        if fromMaximized do
            surface.showMaximized()
        surface.showNormalAt(monitor)
        if fromMaximized do
            surface.showMaximized(normal)
        else do
            surface.showNormalAt(normal)
        surface.showMaximized()
        surface.showNormal()
        Swag.assert(IsWindowVisible(surface.win32Handle()))
        Swag.assert(surface.position == normal)
        Swag.assert(not surface.placementOverlay)
        var cloaked: DWORD
        let queried = DwmGetWindowAttribute(surface.win32Handle(), DWMWA_CLOAKED, &cloaked, #sizeof(cloaked))
        Swag.assert(queried == 0 and cloaked == 0)
    }

    Swag.assert(observation.hides == 0, "placement must not hide the native window during a transition")
    Swag.assert(observation.prematureOverlays == 0, "the final image must not appear before the native window changes bounds")
    Swag.assert(observation.consumedFrames == 0, "a prepared frame must survive until the native placement transaction returns")
}

// The window's rendering context must stay on its owner thread. Delegating synchronous WGL
// calls to another thread lets drawable reallocation overlap USER32's geometry transaction;
// the driver can then stall for seconds even when the surface contains no controls.
#[Swag.TestTag("integration.host.windows")]
#test
{
    var app: Application
    let surface = expect app.createSurface(40, 40, 320, 180, surfaceId: "gui-render-owner-test")
    let context = Ogl.wglGetCurrentContext()
    Swag.assert(context != null, "the window owner must own the default OpenGL context")

    var processId: u32
    let owner = GetWindowThreadProcessId(surface.win32Handle(), &processId)
    Swag.assert(owner == GetCurrentThreadId())

    for step in 4
    {
        surface.setPosition({40, 40, cast(f32) (320 + step * 2), 180})
        surface.paint()
        Swag.assert(Ogl.wglGetCurrentContext() == context)
        Swag.assert(surface.rt.colorBuffer.isValid())
    }
}

// Discrete placements finish with a target and client rectangle of the same size. In particular,
// preparing the large maximized frame before USER32 changes the window must not leave the surface
// dirty or publish the normal-sized target through the maximized drawable.
#[Swag.TestTag("integration.host.windows")]
#test
{
    var app: Application
    let surface = expect app.createSurface(40, 40, 640, 400, surfaceId: "gui-discrete-placement-test")
    surface.show()

    let normal = surface.position
    surface.showMaximized()

    var client: RECT
    Swag.assert(GetClientRect(surface.win32Handle(), &client))
    Swag.assert(surface.isMaximized)
    Swag.assert(surface.rc.width == client.right and surface.rc.height == client.bottom)
    Swag.assert(surface.rt.colorBuffer.width >= surface.rc.width and surface.rt.colorBuffer.height >= surface.rc.height)
    Swag.assert(not surface.preparedFrame and not surface.isDirty)

    surface.showNormal()
    Swag.assert(GetClientRect(surface.win32Handle(), &client))
    Swag.assert(not surface.isMaximized)
    Swag.assert(surface.position == normal)
    Swag.assert(surface.rc.width == client.right and surface.rc.height == client.bottom)
    Swag.assert(not surface.preparedFrame and not surface.isDirty)
}

// Placing a window at explicit bounds is a discrete placement too, from a regular window and from
// a maximized one, and it leaves the window visible at exactly those bounds.
#[Swag.TestTag("integration.host.windows")]
#test
{
    var app: Application
    let surface = expect app.createSurface(40, 40, 640, 400, surfaceId: "gui-normal-at-placement-test")
    surface.show()

    for fromMaximized in [false, true]
    {
        if fromMaximized do
            surface.showMaximized()
        let target = Math.Rectangle{60, 50, 700, 460}
        surface.showNormalAt(target)

        var client: RECT
        Swag.assert(GetClientRect(surface.win32Handle(), &client))
        let style = cast(u32) GetWindowLongPtrW(surface.win32Handle(), GWL_STYLE)
        Swag.assert(not surface.isMaximized and not (style & WS_MAXIMIZE))
        Swag.assert(IsWindowVisible(surface.win32Handle()))
        Swag.assert(surface.position == target)
        Swag.assert(surface.rc.width == client.right and surface.rc.height == client.bottom)
        Swag.assert(not surface.preparedFrame and not surface.isDirty)
    }
}

// A taskbar restore must return a minimized maximized window to its maximized bounds.
// Restoring a minimized normal window must still return it to its normal bounds.
#[Swag.TestTag("integration.host.windows")]
#test
{
    var app: Application
    let surface = expect app.createSurface(40, 40, 640, 400, surfaceId: "gui-minimized-restore-test")
    surface.show()

    let normal = surface.position
    surface.showMaximized()
    let maximized = surface.position

    discard SendMessageW(surface.win32Handle(), WM_SYSCOMMAND, SC_MINIMIZE, 0)
    app.runFrame()
    Swag.assert(surface.isMinimized and surface.isMaximized)
    Swag.assert(surface.position == maximized)

    discard SendMessageW(surface.win32Handle(), WM_SYSCOMMAND, SC_RESTORE, 0)
    app.runFrame()
    let maximizedStyle = cast(u32) GetWindowLongPtrW(surface.win32Handle(), GWL_STYLE)
    Swag.assert(not surface.isMinimized and surface.isMaximized)
    Swag.assert(maximizedStyle & WS_MAXIMIZE and not (maximizedStyle & WS_MINIMIZE))
    Swag.assert(IsWindowVisible(surface.win32Handle()))
    Swag.assert(surface.position == maximized)

    surface.showNormal()
    discard SendMessageW(surface.win32Handle(), WM_SYSCOMMAND, SC_MINIMIZE, 0)
    app.runFrame()
    discard SendMessageW(surface.win32Handle(), WM_SYSCOMMAND, SC_RESTORE, 0)
    app.runFrame()
    let normalStyle = cast(u32) GetWindowLongPtrW(surface.win32Handle(), GWL_STYLE)
    Swag.assert(not surface.isMinimized and not surface.isMaximized)
    Swag.assert(not (normalStyle & WS_MINIMIZE) and not (normalStyle & WS_MAXIMIZE))
    Swag.assert(IsWindowVisible(surface.win32Handle()))
    Swag.assert(surface.position == normal)

    surface.showMaximized()
    discard SendMessageW(surface.win32Handle(), WM_SYSCOMMAND, SC_MINIMIZE, 0)
    app.runFrame()
    surface.showNormal()
    let restoredStyle = cast(u32) GetWindowLongPtrW(surface.win32Handle(), GWL_STYLE)
    Swag.assert(not surface.isMinimized and not surface.isMaximized)
    Swag.assert(not (restoredStyle & WS_MINIMIZE) and not (restoredStyle & WS_MAXIMIZE))
    Swag.assert(IsWindowVisible(surface.win32Handle()))
    Swag.assert(surface.position == normal)
}
