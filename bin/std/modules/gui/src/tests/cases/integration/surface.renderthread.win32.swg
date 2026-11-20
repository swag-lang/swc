#global if #os == Swag.TargetOs.Windows
#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Win32, Ogl

// Repainting while minimized must not replace the native icon bounds with the full-size frame.
// Restoration retains the latest normal placement, including before the first maximize.
#[Swag.TestTag("integration.host.windows")]
#test
{
    var app: Application
    let surface = expect app.createSurface(40, 40, 320, 180, surfaceId: "gui-minimized-paint-test")
    surface.show()

    for maximize in [false, true]
    {
        let normal = Math.Rectangle{60, 50, 400, 240}
        surface.setPosition(normal)
        if maximize do
            surface.showMaximized()
        let bounds = surface.position
        surface.showMinimized()

        var minimized: RECT
        let readMinimized = GetWindowRect(surface.win32Handle(), &minimized)
        Swag.require(readMinimized)
        for 3
        {
            surface.invalidate()
            app.runFrame()
            var current: RECT
            let readCurrent = GetWindowRect(surface.win32Handle(), &current)
            Swag.require(readCurrent)
            Swag.require(current.left == minimized.left and current.top == minimized.top)
            Swag.require(current.right == minimized.right and current.bottom == minimized.bottom)
            Swag.require(surface.isMinimized and surface.isDirty)
            Swag.require(surface.position == bounds)
        }

        surface.requestRestore()
        app.runFrame()
        Swag.require(not surface.isMinimized and surface.isMaximized == maximize)
        Swag.require(surface.position == bounds)
        Swag.require(not surface.isDirty)
        surface.showNormal()
        Swag.require(surface.position == normal)
    }
}

struct PlacementObservation
{
    hides:              u32
    expected:           Math.Rectangle
    watchBounds:        bool
    intermediateBounds: u32
    surface:            *Surface?
    calculationDepth:   u32
    preparedFrames:     u32
}

#[Swag.CallingConvention(.C)]
func observePlacement(hWnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM, _: UINT_PTR, data: DWORD_PTR)->LRESULT
{
    let observation = cast(*PlacementObservation, data)
    if msg == WM_NCCALCSIZE and wParam and observation.surface
    {
        let params      = cast(const *NCCALCSIZE_PARAMS, cast #bit (u64, lParam))
        let bounds      = params.rgrc[0]
        let old         = params.rgrc[2]
        let width       = bounds.right - bounds.left
        let height      = bounds.bottom - bounds.top
        let outerResize = observation.calculationDepth == 0 and
                          (width != old.right - old.left or height != old.bottom - old.top)

        observation.calculationDepth += 1
        defer observation.calculationDepth -= 1
        let result = DefSubclassProc(hWnd, msg, wParam, lParam)
        if outerResize and
           observation.surface.presentedFrame and
           observation.surface.rc.width == width and
           observation.surface.rc.height == height do
            observation.preparedFrames += 1
        return result
    }

    if msg == WM_WINDOWPOSCHANGING
    {
        let next = cast(*WINDOWPOS, cast #bit (u64, lParam))
        if next.flags & SWP_HIDEWINDOW do
            observation.hides += 1
    }
    elif msg == WM_WINDOWPOSCHANGED and observation.watchBounds
    {
        var rect: RECT
        Swag.require(GetWindowRect(hWnd, &rect))
        if rect.left != cast(s32, observation.expected.x) or
           rect.top != cast(s32, observation.expected.y) or
           rect.right != cast(s32, observation.expected.right()) or
           rect.bottom != cast(s32, observation.expected.bottom()) do
            observation.intermediateBounds += 1
    }

    return DefSubclassProc(hWnd, msg, wParam, lParam)
}

// Native placement owns the restore rectangle, and changing state never hides the window.
#[Swag.TestTag("integration.host.windows")]
#test
{
    var app: Application
    let surface = expect app.createSurface(40, 40, 640, 400, surfaceId: "gui-placement-transaction-test")
    surface.show()
    var observation: PlacementObservation
    Swag.require(SetWindowSubclass(surface.win32Handle(), &observePlacement, 1, cast(u64, &observation)))
    defer discard RemoveWindowSubclass(surface.win32Handle(), &observePlacement, 1)

    var normal: WINDOWPLACEMENT
    normal.length = #sizeof(normal)
    Swag.require(GetWindowPlacement(surface.win32Handle(), &normal))
    let bounds = surface.position
    surface.showMaximized()
    let maximizedBounds = surface.position
    var maximized: WINDOWPLACEMENT
    maximized.length = #sizeof(maximized)
    Swag.require(GetWindowPlacement(surface.win32Handle(), &maximized))
    Swag.require(maximized.showCmd == SW_SHOWMAXIMIZED)
    Swag.require(maximized.rcNormalPosition.left == normal.rcNormalPosition.left)
    Swag.require(maximized.rcNormalPosition.top == normal.rcNormalPosition.top)
    Swag.require(maximized.rcNormalPosition.right == normal.rcNormalPosition.right)
    Swag.require(maximized.rcNormalPosition.bottom == normal.rcNormalPosition.bottom)
    surface.showNormal()
    surface.showNormalAt(Env.monitorForRectangle(bounds).physicalBounds)
    observation.expected    = maximizedBounds
    observation.watchBounds = true
    surface.showMaximized(bounds)
    observation.watchBounds = false
    Swag.require(observation.intermediateBounds == 0, "returning to maximized must not visit the normal restore bounds")
    surface.showNormalAt(bounds)
    Swag.require(observation.hides == 0, "placement must preserve native visibility throughout the transaction")
    Swag.require(surface.position == bounds)
}

// The owner thread keeps one fixed OpenGL drawable while the visible HWND resizes.
#[Swag.TestTag("integration.host.windows")]
#test
{
    var app: Application
    let surface  = expect app.createSurface(40, 40, 320, 180, surfaceId: "gui-render-owner-test")
    let context  = Ogl.wglGetCurrentContext()
    let drawable = Ogl.wglGetCurrentDC()
    Swag.require(context != null, "the window owner must own the default OpenGL context")
    let windowDC = GetDC(surface.win32Handle())
    defer ReleaseDC(surface.win32Handle(), windowDC)
    Swag.require(drawable and windowDC and drawable != windowDC)

    var processId: u32
    let owner = GetWindowThreadProcessId(surface.win32Handle(), &processId)
    Swag.require(owner == GetCurrentThreadId())

    for step in 4
    {
        surface.setPosition(Math.Rectangle{40, 40, cast(f32, (320 + step * 2)), 180})
        surface.paint()
        Swag.require(Ogl.wglGetCurrentContext() == context)
        Swag.require(Ogl.wglGetCurrentDC() == drawable)
        Swag.require(surface.rt.colorBuffer.isValid())
    }
}

// The layer already has the proposed frame when USER32 finishes calculating the client.
#[Swag.TestTag("integration.host.windows")]
#test
{
    var app: Application
    let surface = expect app.createSurface(40, 40, 640, 400, surfaceId: "gui-discrete-placement-test")
    surface.show()
    let window      = surface.win32Handle()
    var observation = PlacementObservation{surface: surface}
    Swag.require(SetWindowSubclass(window, &observePlacement, 1, cast(u64, &observation)))
    defer discard RemoveWindowSubclass(window, &observePlacement, 1)

    var paints = 0
    surface.wnd.view.hookOnEvent = func|&paints|(_, evt)->bool
    {
        if evt is PaintEvent do
            paints += 1
        return false
    }

    let normal = surface.position
    surface.showMaximized()

    var client: RECT
    Swag.require(GetClientRect(window, &client))
    Swag.require(surface.isMaximized)
    Swag.require(surface.rc.width == client.right and surface.rc.height == client.bottom)
    Swag.require(observation.preparedFrames == 1)
    Swag.require(paints == 1)
    Swag.require(expect Testing.verifyNativePresentation(surface))

    surface.showNormal()
    Swag.require(GetClientRect(window, &client))
    Swag.require(not surface.isMaximized)
    Swag.require(surface.position == normal)
    Swag.require(surface.rc.width == client.right and surface.rc.height == client.bottom)
    Swag.require(observation.preparedFrames == 2)
    Swag.require(paints == 2)
    Swag.require(expect Testing.verifyNativePresentation(surface))
}

// Multiple native drag sizes between clock frames produce one layout and one GPU frame.
#[Swag.TestTag("integration.host.windows")]
#test
{
    var app: Application
    let surface = expect app.createSurface(40, 40, 320, 180, surfaceId: "gui-live-sizing-test")
    let window  = surface.win32Handle()
    surface.show()
    app.runFrame()
    let previousWidth = surface.rc.width

    discard SendMessageW(window, WM_ENTERSIZEMOVE, 0, 0)
    for width in [641, 649, 653]
    {
        expect SetWindowPos(window, null, 0, 0, width, 403, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE)
        Swag.require(surface.rc.width == previousWidth)
    }

    Swag.require(surface.isSizing)
    app.runClockFrame()
    Swag.require(surface.rc.width == 653 and surface.rc.height == 403)
    Swag.require(expect Testing.verifyNativePresentation(surface))
    let bitmap = surface.presentationBitmap

    // A shrink during the same gesture reuses the larger allocation and publishes its own
    // top-left rectangle without moving or resizing the HWND a second time.
    expect SetWindowPos(window, null, 0, 0, 619, 389, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE)
    app.runClockFrame()
    Swag.require(surface.rc.width == 619 and surface.rc.height == 389)
    Swag.require(surface.presentationBitmap == bitmap)
    Swag.require(expect Testing.verifyNativePresentation(surface))

    expect SetWindowPos(window, null, 0, 0, 655, 401, SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE)
    discard SendMessageW(window, WM_EXITSIZEMOVE, 0, 0)
    Swag.require(not surface.isSizing and surface.rc.width == 619)
    app.runFrame()
    Swag.require(surface.rc.width == 655 and surface.rc.height == 401)
    Swag.require(surface.presentationBitmap == bitmap)
    Swag.require(expect Testing.verifyNativePresentation(surface))
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
        Swag.require(GetClientRect(surface.win32Handle(), &client))
        let style = cast(u32, GetWindowLongPtrW(surface.win32Handle(), GWL_STYLE))
        Swag.require(not surface.isMaximized and not (style & WS_MAXIMIZE))
        Swag.require(IsWindowVisible(surface.win32Handle()))
        Swag.require(surface.position == target)
        Swag.require(surface.rc.width == client.right and surface.rc.height == client.bottom)
        app.runFrame()
        Swag.require(not surface.isDirty)
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
    Swag.require(surface.isMinimized and surface.isMaximized)
    Swag.require(surface.position == maximized)

    discard SendMessageW(surface.win32Handle(), WM_SYSCOMMAND, SC_RESTORE, 0)
    app.runFrame()
    let maximizedStyle = cast(u32, GetWindowLongPtrW(surface.win32Handle(), GWL_STYLE))
    Swag.require(not surface.isMinimized and surface.isMaximized)
    Swag.require(maximizedStyle & WS_MAXIMIZE and not (maximizedStyle & WS_MINIMIZE))
    Swag.require(IsWindowVisible(surface.win32Handle()))
    Swag.require(surface.position == maximized)

    surface.showNormal()
    discard SendMessageW(surface.win32Handle(), WM_SYSCOMMAND, SC_MINIMIZE, 0)
    app.runFrame()
    discard SendMessageW(surface.win32Handle(), WM_SYSCOMMAND, SC_RESTORE, 0)
    app.runFrame()
    let normalStyle = cast(u32, GetWindowLongPtrW(surface.win32Handle(), GWL_STYLE))
    Swag.require(not surface.isMinimized and not surface.isMaximized)
    Swag.require(not (normalStyle & WS_MINIMIZE) and not (normalStyle & WS_MAXIMIZE))
    Swag.require(IsWindowVisible(surface.win32Handle()))
    Swag.require(surface.position == normal)

    surface.showMaximized()
    discard SendMessageW(surface.win32Handle(), WM_SYSCOMMAND, SC_MINIMIZE, 0)
    app.runFrame()
    surface.showNormal()
    let restoredStyle = cast(u32, GetWindowLongPtrW(surface.win32Handle(), GWL_STYLE))
    Swag.require(not surface.isMinimized and not surface.isMaximized)
    Swag.require(not (restoredStyle & WS_MINIMIZE) and not (restoredStyle & WS_MAXIMIZE))
    Swag.require(IsWindowVisible(surface.win32Handle()))
    Swag.require(surface.position == normal)
}
