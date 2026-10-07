#global if #os == Swag.TargetOs.Windows
#global if #command == Swag.CompilerCommand.Test
#global private

using Core, Win32, Ogl

struct PlacementObservation
{
    hides: u32
}

#[Swag.CallingConvention(.C)]
func observePlacement(hWnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM, subclassId: UINT_PTR, data: DWORD_PTR)->LRESULT
{
    let observation = cast(*PlacementObservation, data)
    if msg == WM_WINDOWPOSCHANGING
    {
        let next = cast(*WINDOWPOS, cast #bit (u64, lParam))
        if next.flags & SWP_HIDEWINDOW do
            observation.hides += 1
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
    Swag.assert(SetWindowSubclass(surface.win32Handle(), &observePlacement, 1, cast(u64, &observation)))
    defer discard RemoveWindowSubclass(surface.win32Handle(), &observePlacement, 1)

    var normal: WINDOWPLACEMENT
    normal.length = #sizeof(normal)
    Swag.assert(GetWindowPlacement(surface.win32Handle(), &normal))
    let bounds = surface.position
    surface.showMaximized()
    var maximized: WINDOWPLACEMENT
    maximized.length = #sizeof(maximized)
    Swag.assert(GetWindowPlacement(surface.win32Handle(), &maximized))
    Swag.assert(maximized.showCmd == SW_SHOWMAXIMIZED)
    Swag.assert(maximized.rcNormalPosition.left == normal.rcNormalPosition.left)
    Swag.assert(maximized.rcNormalPosition.top == normal.rcNormalPosition.top)
    Swag.assert(maximized.rcNormalPosition.right == normal.rcNormalPosition.right)
    Swag.assert(maximized.rcNormalPosition.bottom == normal.rcNormalPosition.bottom)
    surface.showNormal()
    surface.showNormalAt(Env.monitorForRectangle(bounds).physicalBounds)
    surface.showNormalAt(bounds)
    Swag.assert(observation.hides == 0, "placement must preserve native visibility throughout the transaction")
    Swag.assert(surface.position == bounds)
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
        surface.setPosition({40, 40, cast(f32, (320 + step * 2)), 180})
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
        let style = cast(u32, GetWindowLongPtrW(surface.win32Handle(), GWL_STYLE))
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
    let maximizedStyle = cast(u32, GetWindowLongPtrW(surface.win32Handle(), GWL_STYLE))
    Swag.assert(not surface.isMinimized and surface.isMaximized)
    Swag.assert(maximizedStyle & WS_MAXIMIZE and not (maximizedStyle & WS_MINIMIZE))
    Swag.assert(IsWindowVisible(surface.win32Handle()))
    Swag.assert(surface.position == maximized)

    surface.showNormal()
    discard SendMessageW(surface.win32Handle(), WM_SYSCOMMAND, SC_MINIMIZE, 0)
    app.runFrame()
    discard SendMessageW(surface.win32Handle(), WM_SYSCOMMAND, SC_RESTORE, 0)
    app.runFrame()
    let normalStyle = cast(u32, GetWindowLongPtrW(surface.win32Handle(), GWL_STYLE))
    Swag.assert(not surface.isMinimized and not surface.isMaximized)
    Swag.assert(not (normalStyle & WS_MINIMIZE) and not (normalStyle & WS_MAXIMIZE))
    Swag.assert(IsWindowVisible(surface.win32Handle()))
    Swag.assert(surface.position == normal)

    surface.showMaximized()
    discard SendMessageW(surface.win32Handle(), WM_SYSCOMMAND, SC_MINIMIZE, 0)
    app.runFrame()
    surface.showNormal()
    let restoredStyle = cast(u32, GetWindowLongPtrW(surface.win32Handle(), GWL_STYLE))
    Swag.assert(not surface.isMinimized and not surface.isMaximized)
    Swag.assert(not (restoredStyle & WS_MINIMIZE) and not (restoredStyle & WS_MAXIMIZE))
    Swag.assert(IsWindowVisible(surface.win32Handle()))
    Swag.assert(surface.position == normal)
}
