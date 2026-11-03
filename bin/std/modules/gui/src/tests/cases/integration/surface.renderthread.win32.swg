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
}

#[Swag.CallingConvention(.C)]
func observePlacement(hWnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM, _: UINT_PTR, data: DWORD_PTR)->LRESULT
{
    let observation = cast(*PlacementObservation, data)
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

// The window's rendering context must stay on its owner thread. Delegating synchronous WGL
// calls to another thread lets drawable reallocation overlap USER32's geometry transaction;
// the driver can then stall for seconds even when the surface contains no controls.
#[Swag.TestTag("integration.host.windows")]
#test
{
    var app: Application
    let surface = expect app.createSurface(40, 40, 320, 180, surfaceId: "gui-render-owner-test")
    let context = Ogl.wglGetCurrentContext()
    Swag.require(context != null, "the window owner must own the default OpenGL context")

    var processId: u32
    let owner = GetWindowThreadProcessId(surface.win32Handle(), &processId)
    Swag.require(owner == GetCurrentThreadId())

    for step in 4
    {
        surface.setPosition(Math.Rectangle{40, 40, cast(f32, (320 + step * 2)), 180})
        surface.paint()
        Swag.require(Ogl.wglGetCurrentContext() == context)
        Swag.require(surface.rt.colorBuffer.isValid())
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
    Swag.require(GetClientRect(surface.win32Handle(), &client))
    Swag.require(surface.isMaximized)
    Swag.require(surface.rc.width == client.right and surface.rc.height == client.bottom)
    Swag.require(surface.rt.colorBuffer.width >= surface.rc.width and surface.rt.colorBuffer.height >= surface.rc.height)
    Swag.require(not surface.preparedFrame and not surface.isDirty)

    surface.showNormal()
    Swag.require(GetClientRect(surface.win32Handle(), &client))
    Swag.require(not surface.isMaximized)
    Swag.require(surface.position == normal)
    Swag.require(surface.rc.width == client.right and surface.rc.height == client.bottom)
    Swag.require(not surface.preparedFrame and not surface.isDirty)
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
        Swag.require(not surface.preparedFrame and not surface.isDirty)
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
