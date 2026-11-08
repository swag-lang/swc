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
