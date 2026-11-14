#global public
#global namespace Testing
#global if #os == Swag.TargetOs.Linux

using Core

#[Swag.CallingConvention(.C)]
private alias XTestMotion = func(*void, s32, s32, s32, u64)->s32
#[Swag.CallingConvention(.C)]
private alias XTestButton = func(*void, u32, s32, u64)->s32
#[Swag.CallingConvention(.C)]
private alias XTestKey = func(*void, u32, s32, u64)->s32
#[Swag.CallingConvention(.C)]
private alias XKeysymToKeycode = func(*void, u64)->u8
#[Swag.CallingConvention(.C)]
private alias XSetInputFocus = func(*void, u64, s32, u64)->s32
#[Swag.CallingConvention(.C)]
private alias XGetInputFocus = func(*void, *u64, *s32)->s32
#[Swag.CallingConvention(.C)]
private alias XSync = func(*void, s32)->s32

internal struct NativeDesktopInput
{
    x11, xtst, display: *void?
    priorFocus: u64
    late motion: XTestMotion
    late button: XTestButton
    late key: XTestKey
    late keycode: XKeysymToKeycode
    late setFocus: XSetInputFocus
    late getFocus: XGetInputFocus
    late sync: XSync
    mousePressed: bool
    pressedKeyCode: u32
    heldControl, heldShift, heldAlt: bool
}

impl DesktopInput
{
    internal mtd openNative()
    {
        .x11 = Linux.dlopen("libX11.so.6".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
        Swag.require(.x11 != null, "desktop input needs libX11.so.6")
        .xtst = Linux.dlopen("libXtst.so.6".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
        Swag.require(.xtst != null, "desktop input needs libXtst.so.6")
        let x11 = .x11
        let xtst = .xtst
        let open = expect LinuxDesktop.symbol'Linux.XOpenDisplay_fn(x11, "XOpenDisplay")
        .display = open(null)
        Swag.require(.display != null, "desktop input needs an X11 display")
        .motion = expect LinuxDesktop.symbol'XTestMotion(xtst, "XTestFakeMotionEvent")
        .button = expect LinuxDesktop.symbol'XTestButton(xtst, "XTestFakeButtonEvent")
        .key = expect LinuxDesktop.symbol'XTestKey(xtst, "XTestFakeKeyEvent")
        .keycode = expect LinuxDesktop.symbol'XKeysymToKeycode(x11, "XKeysymToKeycode")
        .setFocus = expect LinuxDesktop.symbol'XSetInputFocus(x11, "XSetInputFocus")
        .getFocus = expect LinuxDesktop.symbol'XGetInputFocus(x11, "XGetInputFocus")
        .sync = expect LinuxDesktop.symbol'XSync(x11, "XSync")
        var revertTo: s32
        discard .getFocus(.display, &.priorFocus, &revertTo)
    }

    internal mtd closeNative()
    {
        let display = unwrap .display
        let x11 = unwrap .x11
        let xtst = unwrap .xtst
        if .pressedKeyCode != 0 do
            discard .key(display, .pressedKeyCode, 0, 0)
        if .heldAlt do
            .releaseModifier(.Alt)
        if .heldShift do
            .releaseModifier(.Shift)
        if .heldControl do
            .releaseModifier(.Control)
        if .mousePressed do
            discard .button(display, 1, 0, 0)
        discard .setFocus(display, .priorFocus, 2, 0)
        discard .sync(display, 0)
        let close = expect LinuxDesktop.symbol'Linux.XCloseDisplay_fn(x11, "XCloseDisplay")
        discard close(display)
        discard Linux.dlclose(xtst)
        discard Linux.dlclose(x11)
    }

    internal mtd focusNative()
    {
        let display = unwrap .display
        discard .setFocus(display, .surface.windowId, 2, 0)
        discard .sync(display, 0)
    }

    internal mtd requireNativeFocus()
    {
        var focused: u64
        var revertTo: s32
        discard .getFocus(unwrap .display, &focused, &revertTo)
        Swag.require(focused == .surface.windowId, "the test window lost X11 keyboard focus")
    }

    internal mtd requireNativePointerAt(screen: Math.Point)
    {
        Swag.require(.app.surfaceAtNative(screen.x, screen.y) == .surface,
                     "another X11 window covers the pointer target")
    }

    internal mtd sendNativeMotion(screen: Math.Point)
    {
        let display = unwrap .display
        Swag.require(.motion(display, -1, cast(s32, screen.x), cast(s32, screen.y), 0) != 0,
                     "XTEST could not move the desktop pointer")
        discard .sync(display, 0)
    }

    internal mtd sendNativeButton(pressed: bool)
    {
        let display = unwrap .display
        Swag.require(.button(display, 1, pressed ? 1 : 0, 0) != 0,
                     "XTEST could not send the mouse button")
        .mousePressed = pressed
        discard .sync(display, 0)
    }

    internal mtd sendNativeKey(key: Input.Key, pressed: bool)
    {
        let symbol = Input.Keyboard.keyToVirtualKey(key)
        let code = .keycode(unwrap .display, symbol)
        Swag.require(code != 0, "the X11 keyboard map lacks the shortcut key")
        .sendRawKey(code, pressed)
        .pressedKeyCode = pressed ? code : 0
    }

    internal mtd sendNativeModifier(modifier: Input.KeyModifiers, pressed: bool)
    {
        let code = .modifierCode(modifier)
        Swag.require(code != 0, "the X11 keyboard map lacks the shortcut modifier")
        .sendRawKey(code, pressed)
        switch modifier
        {
        case .Control: .heldControl = pressed
        case .Shift:   .heldShift = pressed
        case .Alt:     .heldAlt = pressed
        }
    }

    private mtd modifierCode(modifier: Input.KeyModifiers)->u8
    {
        var symbol: u64
        switch modifier
        {
        case .Control: symbol = 0xFFE3
        case .Shift:   symbol = 0xFFE1
        case .Alt:     symbol = 0xFFE9
        default:       Swag.require(false, "desktop input does not support this modifier")
        }
        return .keycode(unwrap .display, symbol)
    }

    private mtd releaseModifier(modifier: Input.KeyModifiers)
    {
        let code = .modifierCode(modifier)
        if code != 0 do
            discard .key(unwrap .display, code, 0, 0)
    }

    private mtd sendRawKey(code: u32, pressed: bool)
    {
        let display = unwrap .display
        Swag.require(.key(display, code, pressed ? 1 : 0, 0) != 0,
                     "XTEST could not send the keyboard key")
        discard .sync(display, 0)
    }
}
