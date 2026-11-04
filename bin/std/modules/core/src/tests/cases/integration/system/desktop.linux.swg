#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

var g_DesktopResizeCount:   u32
var g_DesktopWidth:         s32
var g_DesktopHeight:        s32
var g_DesktopCallbackOwner: *Env.Window?

func recordDesktopResize(owner: *Env.Window, width, height: s32)
{
    g_DesktopCallbackOwner = owner
    g_DesktopResizeCount   += 1
    g_DesktopWidth         = width
    g_DesktopHeight        = height
}

func closeDesktopPaint(owner: *Env.Window)
{
    expect owner.close()
}

func returnedDesktopWindow()->Env.Window fail
{
    return try Env.createWindow({identifier: "swag-linux-desktop-test", title: "Swag X11 é",
                                 width: 160, height: 90})
}

// Select explicitly against an isolated X11 server; this test moves its cursor.
#[Swag.TestTag("integration.desktop")]
#test
{
    var returned = expect returnedDesktopWindow()
    let renderHandle = returned.nativeRenderHandle()
    var window   = #move returned
    Swag.require(window.isOpen() and window.nativeRenderHandle() == renderHandle)
    let drawable = cast(const *Env.XcbDrawable, unwrap renderHandle)[]
    Swag.require(drawable == (expect window.xcbDrawable()))
    let context = expect LinuxDesktop.ensure()
    let native  = unwrap context.windows
    Swag.require(native.owner == &window)
    window.callbacks.onResize = &recordDesktopResize
    g_DesktopResizeCount      = 0
    expect window.setClientSize(240, 120)
    expect window.showOffScreen()
    Swag.require(g_DesktopCallbackOwner == &window and g_DesktopResizeCount > 0)
    Swag.require(g_DesktopWidth == 240 and g_DesktopHeight == 120)
    Swag.require(window.dpiScale() == 1)
    Swag.require(Env.processWindowMessages())

    let monitors = Env.getMonitors()
    Swag.require(not monitors.isEmpty())
    for monitor in monitors
    {
        Swag.require(monitor.scaleFactor == 1)
        Swag.require(monitor.physicalBounds.width > 0 and monitor.physicalBounds.height > 0)
        Swag.require(monitor.bounds == monitor.physicalBounds)
    }

    Swag.require(Env.getSystemMetric(.DesktopWidth) > 0)
    let previousPointer = Input.mousePosition()
    defer Input.setMousePosition(cast(s32, previousPointer.x), cast(s32, previousPointer.y))
    Input.setMousePosition(11, 23)
    let pointer = Input.mousePosition()
    Swag.require(pointer.x == 11 and pointer.y == 23)
    var keyboard: Input.Keyboard
    keyboard.update()
    Swag.require(not keyboard.isKeyPressed(.None))
    Swag.require(Input.Keyboard.keyToVirtualKey(.A) == 'a')
    Swag.require(Input.Keyboard.virtualKeyToKey('a') == .A)

    // A window-manager close request ends the loop but leaves the resource owned.
    var message: Linux.xcb_client_message_event_t
    message.response_type = 33
    message.format        = 32
    message.window        = native.id
    message.type          = native.protocolsAtom
    message.data[0]       = native.deleteAtom
    expect LinuxDesktop.check(context,
                              context.xcb_send_event_checked(unwrap context.connection,
                                                             0,
                                                             native.id,
                                                             0,
                                                             cast(const [*]u8, &message)))
    Swag.require(not Env.processWindowMessages())
    Swag.require(window.isOpen())
    expect window.close()
    expect window.close()
    Swag.require(not window.isOpen() and window.nativeRenderHandle() == null and context.windows == null)

    // Callback closure must not leave a dangling owner in event dispatch.
    var callbackWindow = expect returnedDesktopWindow()
    callbackWindow.callbacks.onPaint = &closeDesktopPaint
    expect callbackWindow.showOffScreen()
    callbackWindow.requestPaint()
    Swag.require(not Env.processWindowMessages())
    Swag.require(not callbackWindow.isOpen() and context.windows == null)

    // A native consumer can destroy the drawable before the owner sees DestroyNotify.
    var externalWindow = expect returnedDesktopWindow()
    let external       = context.windows
    expect LinuxDesktop.check(context, context.xcb_destroy_window_checked(unwrap context.connection, external.id))
    expect externalWindow.close()
    Swag.require(not externalWindow.isOpen() and context.windows == null)
    g_DesktopCallbackOwner = null
}

#[Swag.TestTag("integration.desktop")]
#test
{
    var outcome: Swag.Error
    discard catch Env.createWindow({identifier: "invalid", title: "invalid", width: 0, height: 10}) as outcome
    Swag.require(outcome.value() is Errors.BadParameterError)
    discard catch Env.createWindow({identifier: "invalid", title: "invalid", width: 10, height: 65536}) as outcome
    Swag.require(outcome.value() is Errors.BadParameterError)
    discard catch Env.createWindow({identifier: "invalid", title: "bad\0title", width: 10, height: 10}) as outcome
    Swag.require(outcome.value() is Errors.BadParameterError)
}

// Run separately with DISPLAY naming an unavailable server, so no desktop is required.
#[Swag.TestTag("integration.desktop.missing")]
#test
{
    for 4
    {
        Swag.require(Env.getMonitors().isEmpty())
        Input.showMouseCursor(false)
        Input.showMouseCursor(true)
        let position = Input.mousePosition()
        Swag.require(position.x == 0 and position.y == 0)
        var keyboard: Input.Keyboard
        keyboard.update()
        for key in Input.Key do
            Swag.require(not keyboard.isKeyPressed(key))
        var outcome: Swag.Error
        discard catch returnedDesktopWindow() as outcome
        Swag.require(outcome.value() is Swag.SystemError)
    }
}

// Select only on an isolated X11 server with XFixes 4; the cursor is temporarily hidden.
#[Swag.TestTag("integration.desktop")]
#test
{
    let context = expect LinuxDesktop.ensure()
    Swag.require(context.cursorBalance == 0)
    let root = context.screen.root
    defer
    {
        context.screen.root = root
        for 2
        {
            if context.cursorBalance < 0 do
                Input.showMouseCursor(true)
            elif context.cursorBalance > 0 do
                Input.showMouseCursor(false)
            else do
                break
        }
    }

    // A real BadWindow response must not consume a visibility transition.
    context.screen.root = 0
    Input.showMouseCursor(false)
    context.screen.root = root
    Swag.require(context.cursorReady and context.cursorBalance == 0)
    let library = context.libraryXfixes
    Swag.require(library != null)

    Input.showMouseCursor(false)
    Input.showMouseCursor(false)
    Swag.require(context.cursorBalance == -2)
    Input.showMouseCursor(true)
    Swag.require(context.cursorBalance == -1)
    Input.showMouseCursor(true)
    Swag.require(context.cursorBalance == 0)

    // Surplus shows postpone the next native hide, matching the visibility-counter contract.
    Input.showMouseCursor(true)
    Input.showMouseCursor(false)
    Swag.require(context.cursorBalance == 0)
    for 16
    {
        Input.showMouseCursor(false)
        Input.showMouseCursor(true)
    }

    Swag.require(context.cursorBalance == 0 and context.libraryXfixes == library)
}

// Run on an isolated X11 server with XFIXES and RANDR explicitly disabled.
#[Swag.TestTag("integration.desktop.basic")]
#test
{
    let context  = expect LinuxDesktop.ensure()
    let monitors = Env.getMonitors()
    Swag.require(context.xcb_connection_has_error(unwrap context.connection) == 0,
                "optional monitor discovery must preserve the display connection")
    Swag.require(monitors.count == 1 and monitors[0].bounds.width > 0)
    Input.showMouseCursor(false)
    Input.showMouseCursor(true)
    Swag.require(context.xcb_connection_has_error(context.connection) == 0,
                "unsupported cursor visibility must preserve the display connection")
    Swag.require(not context.cursorReady and context.cursorBalance == 0)
    var window = expect returnedDesktopWindow()
    expect window.showOffScreen()
    Swag.require(Env.processWindowMessages())
    expect window.close()
}
