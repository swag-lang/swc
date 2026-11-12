#global public
#global namespace Testing
#global if #os == Swag.TargetOs.Windows

using Core, Win32

// Win32 INPUT is a 40-byte tagged union on 64-bit Windows. Key packets use x for
// the virtual key and y for flags; pointer packets use flags for the button edge.
private struct DesktopInputPacket
{
    kind:      u32
    padding:   u32
    x, y:      s32
    data:      u32
    flags:     u32
    time:      u32
    padding2:  u32
    extraInfo: u64
}

#[Foreign("user32", callconv: Swag.CallConv.C)]
private func SendInput(count: u32, packets: const *DesktopInputPacket, size: s32)->u32

#[Foreign("user32", callconv: Swag.CallConv.C)]
private func AttachThreadInput(attachThread, otherThread: u32, attach: BOOL)->BOOL

// Reports whether the Shell currently shows this icon in its notification overflow flyout.
// It lets an interactive test open the chevron only when that flyout is closed.
func isTrayIconInOverflow(surface: *Surface)->bool
{
    var bounds: RECT
    if not surface.trayIconScreenRect(&bounds) do
        return false

    let point = POINT{(bounds.left + bounds.right) / 2, (bounds.top + bounds.bottom) / 2}
    let window = GetAncestor(WindowFromPoint(point), GA_ROOT)
    var className: [128] CHAR
    let length = GetClassNameA(window, &className[0], cast(s32, className.count))
    let name = String.from(Swag.makeString(&className[0], length))
    return name == "TopLevelWindowForOverflowXamlIsland" or name == "NotifyIconOverflowWindow"
}

// Clicks a notification-area icon through Windows input, restoring the pointer after the gesture.
// An icon in the closed overflow area first yields the chevron's bounds: click once to open the
// overflow, let it settle, then call again. Run only on an interactive desktop.
func clickTrayIcon(app: *Application, surface: *Surface, button: Input.MouseButton, count = 1'u32)
{
    Swag.require(count > 0 and (button == .Left or button == .Right))
    var bounds: RECT
    Swag.require(surface.trayIconScreenRect(&bounds), "the notification icon is not visible")
    let saved = Input.mousePosition()
    defer Input.setMousePosition(cast(s32, saved.x), cast(s32, saved.y))

    Input.setMousePosition((bounds.left + bounds.right) / 2, (bounds.top + bounds.bottom) / 2)
    app.runFrame()

    let down = button == .Right ? 0x0008'u32 : 0x0002'u32
    let up = button == .Right ? 0x0010'u32 : 0x0004'u32
    for count
    {
        var press = DesktopInputPacket{kind: 0, flags: down}
        Swag.require(SendInput(1, &press, #sizeof(DesktopInputPacket)) == 1,
                     "Windows could not press the notification icon")
        var held = true
        defer if held
        {
            var release = DesktopInputPacket{kind: 0, flags: up}
            discard SendInput(1, &release, #sizeof(DesktopInputPacket))
        }
        app.runFrame()
        var release = DesktopInputPacket{kind: 0, flags: up}
        Swag.require(SendInput(1, &release, #sizeof(DesktopInputPacket)) == 1,
                     "Windows could not release the notification icon")
        held = false
        app.runFrame()
    }
}

internal struct NativeDesktopInput
{
    priorForeground: HWND
    mousePressed: bool
    pressedKey: u32
    heldControl, heldShift, heldAlt: bool
}

impl DesktopInput
{
    internal mtd openNative()
    {
        .priorForeground = GetForegroundWindow()
        Swag.require(.priorForeground != null, "the desktop has no foreground window")
    }

    internal mtd closeNative()
    {
        if .pressedKey != 0 do
            .releaseRawKey(.pressedKey)
        if .heldAlt do
            .releaseRawKey(0x12)
        if .heldShift do
            .releaseRawKey(0x10)
        if .heldControl do
            .releaseRawKey(0x11)
        if .mousePressed
        {
            var mouseUp = DesktopInputPacket{kind: 0, flags: 0x0004}
            discard SendInput(1, &mouseUp, #sizeof(DesktopInputPacket))
        }
        discard SetForegroundWindow(.priorForeground)
    }

    internal mtd focusNative()
    {
        let foreground = GetForegroundWindow()
        var processId: DWORD
        let foregroundThread = GetWindowThreadProcessId(foreground, &processId)
        let currentThread = GetCurrentThreadId()
        if foregroundThread != currentThread
        {
            Swag.require(AttachThreadInput(currentThread, foregroundThread, TRUE),
                         "Windows could not attach the foreground input queue")
            defer discard AttachThreadInput(currentThread, foregroundThread, FALSE)
            Swag.require(SetForegroundWindow(.surface.win32Handle()),
                         "Windows did not activate the test window")
        }
        else do
            Swag.require(SetForegroundWindow(.surface.win32Handle()),
                         "Windows did not activate the test window")
    }

    internal mtd requireNativeFocus()
    {
        Swag.require(GetForegroundWindow() == .surface.win32Handle(),
                     "the test window lost desktop keyboard focus")
    }

    internal mtd requireNativePointerAt(screen: Math.Point)
    {
        let underPointer = WindowFromPoint(POINT{cast(s32, screen.x), cast(s32, screen.y)})
        Swag.require(underPointer != null and GetAncestor(underPointer, GA_ROOT) == .surface.win32Handle(),
                     "another desktop window covers the pointer target")
    }

    internal mtd sendNativeMotion(screen: Math.Point)
    {
        Input.setMousePosition(cast(s32, screen.x), cast(s32, screen.y))
    }

    internal mtd sendNativeButton(pressed: bool)
    {
        var packet = DesktopInputPacket{kind: 0, flags: pressed ? 0x0002 : 0x0004}
        Swag.require(SendInput(1, &packet, #sizeof(DesktopInputPacket)) == 1,
                     "Windows could not send the mouse button")
        .mousePressed = pressed
    }

    internal mtd sendNativeKey(key: Input.Key, pressed: bool)
    {
        let code = Input.Keyboard.keyToVirtualKey(key)
        Swag.require(code != 0, "the key has no Windows virtual key")
        .sendRawKey(code, pressed)
        .pressedKey = pressed ? code : 0
    }

    internal mtd sendNativeModifier(modifier: Input.KeyModifiers, pressed: bool)
    {
        var code: u32
        switch modifier
        {
        case .Control: code = 0x11
        case .Shift:   code = 0x10
        case .Alt:     code = 0x12
        default:       Swag.require(false, "desktop input does not support this modifier")
        }
        .sendRawKey(code, pressed)
        switch modifier
        {
        case .Control: .heldControl = pressed
        case .Shift:   .heldShift = pressed
        case .Alt:     .heldAlt = pressed
        }
    }

    private mtd sendRawKey(code: u32, pressed: bool)
    {
        var packet = DesktopInputPacket{kind: 1, x: cast(s32, code), y: pressed ? 0 : 0x0002}
        Swag.require(SendInput(1, &packet, #sizeof(DesktopInputPacket)) == 1,
                     "Windows could not send the keyboard key")
    }

    private mtd releaseRawKey(code: u32)
    {
        var packet = DesktopInputPacket{kind: 1, x: cast(s32, code), y: 0x0002}
        discard SendInput(1, &packet, #sizeof(DesktopInputPacket))
    }
}
