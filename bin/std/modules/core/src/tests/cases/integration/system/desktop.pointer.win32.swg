#global if #command == Swag.CompilerCommand.Test
#global if WINDOWS
#global private

using Win32

var g_WinPointerNotices: Array'Env.WindowPointerEvent
var g_WinPointerOwner:   *Env.Window?

func recordWinPointer(owner: *Env.Window, event: Env.WindowPointerEvent)
{
    g_WinPointerOwner = owner
    g_WinPointerNotices.add(event)
}

func pointerCoordinates(x, y: s32)->LPARAM
{
    let low  = cast(u32, cast #bit (u16, cast(s16, x)))
    let high = cast(u32, cast #bit (u16, cast(s16, y)))
    return cast(LPARAM, low | (high << 16))
}

#[Swag.TestTag("integration.desktop")]
#test
{
    var window = expect Env.createWindow({identifier: "swag-pointer", title: "Pointer", width: 80, height: 60})
    let handle = cast(HWND, window.nativeRenderHandle())
    window.callbacks.onPointer = &recordWinPointer
    g_WinPointerNotices.clear()
    defer g_WinPointerNotices.clear()
    var moved = #move window
    discard SendMessageA(handle, WM_MOUSEMOVE, 0, pointerCoordinates(-32768, 32767))
    Swag.require(g_WinPointerOwner == &moved and g_WinPointerNotices.count == 1)
    Swag.require(g_WinPointerNotices[0].kind == .Move)
    Swag.require(g_WinPointerNotices[0].x == -32768 and g_WinPointerNotices[0].y == 32767)

    let downMessages: [5]UINT = [WM_LBUTTONDOWN, WM_MBUTTONDOWN, WM_RBUTTONDOWN, WM_XBUTTONDOWN, WM_XBUTTONDOWN]
    let upMessages:   [5]UINT = [WM_LBUTTONUP, WM_MBUTTONUP, WM_RBUTTONUP, WM_XBUTTONUP, WM_XBUTTONUP]
    let buttons:      [5]Input.MouseButton = [.Left, .Middle, .Right, .XButton1, .XButton2]
    for button, index in buttons
    {
        let parameter: WPARAM = index < 3 ? 0 : cast(u64, index - 2) << 16
        let downResult        = SendMessageA(handle, downMessages[index], parameter, pointerCoordinates(-11, 23))
        let upResult          = SendMessageA(handle, upMessages[index], parameter, pointerCoordinates(17, -31))
        Swag.require(downResult == (index < 3 ? 0 : 1) and upResult == downResult)
        let down = g_WinPointerNotices[1 + index * 2]
        let up   = g_WinPointerNotices[2 + index * 2]
        Swag.require(down.kind == .ButtonDown and up.kind == .ButtonUp)
        Swag.require(down.button == button and up.button == button)
        Swag.require(down.x == -11 and down.y == 23 and up.x == 17 and up.y == -31)
        Swag.require(down.wheelX == 0 and down.wheelY == 0 and up.wheelX == 0 and up.wheelY == 0)
    }

    var position: POINT = {-5, 7}
    let converted       = ClientToScreen(handle, &position)
    Swag.require(converted != 0)
    let coordinates = pointerCoordinates(position.x, position.y)
    let positive    = cast(WPARAM, 60) << 16
    let negative    = cast(WPARAM, cast #bit (u16, -60's16)) << 16
    discard SendMessageA(handle, WM_MOUSEWHEEL, positive, coordinates)
    discard SendMessageA(handle, WM_MOUSEWHEEL, negative, coordinates)
    discard SendMessageA(handle, WM_MOUSEHWHEEL, positive, coordinates)
    discard SendMessageA(handle, WM_MOUSEHWHEEL, negative, coordinates)
    Swag.require(g_WinPointerNotices.count == 15)
    let wheelX: [4]f32 = [0, 0, 0.5, -0.5]
    let wheelY: [4]f32 = [0.5, -0.5, 0, 0]
    for index in 0 until 4
    {
        let event = g_WinPointerNotices[11 + index]
        Swag.require(event.kind == .Wheel and event.x == -5 and event.y == 7)
        Swag.require(event.wheelX == wheelX[index] and event.wheelY == wheelY[index])
    }
}

func closeWinPointer(owner: *Env.Window, _: Env.WindowPointerEvent)
{
    expect owner.close()
}

#[Swag.TestTag("integration.desktop")]
#test
{
    var window = expect Env.createWindow({identifier: "swag-pointer-close", title: "Close", width: 80, height: 60})
    window.callbacks.onPointer = &closeWinPointer
    let handle = cast(HWND, window.nativeRenderHandle())
    discard SendMessageA(handle, WM_LBUTTONDOWN, 0, pointerCoordinates(2, 3))
    Swag.require(not window.isOpen())
}
