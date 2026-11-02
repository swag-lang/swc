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
    var window   = #move returned
    Swag.assert(window.isOpen() and window.nativeRenderHandle() != null)
    let context = expect LinuxDesktop.ensure()
    let native  = unwrap context.windows
    Swag.assert(native.owner == &window)
    window.callbacks.onResize = &recordDesktopResize
    g_DesktopResizeCount      = 0
    expect window.setClientSize(240, 120)
    expect window.showOffScreen()
    Swag.assert(g_DesktopCallbackOwner == &window and g_DesktopResizeCount > 0)
    Swag.assert(g_DesktopWidth == 240 and g_DesktopHeight == 120)
    Swag.assert(window.dpiScale() == 1)
    Swag.assert(Env.processWindowMessages())

    let monitors = Env.getMonitors()
    Swag.assert(not monitors.isEmpty())
    for monitor in monitors
    {
        Swag.assert(monitor.scaleFactor == 1)
        Swag.assert(monitor.physicalBounds.width > 0 and monitor.physicalBounds.height > 0)
        Swag.assert(monitor.bounds == monitor.physicalBounds)
    }

    Swag.assert(Env.getSystemMetric(.DesktopWidth) > 0)
    let previousPointer = Input.mousePosition()
    defer Input.setMousePosition(cast(s32, previousPointer.x), cast(s32, previousPointer.y))
    Input.setMousePosition(11, 23)
    let pointer = Input.mousePosition()
    Swag.assert(pointer.x == 11 and pointer.y == 23)
    var keyboard: Input.Keyboard
    keyboard.update()
    Swag.assert(not keyboard.isKeyPressed(.None))
    Swag.assert(Input.Keyboard.keyToVirtualKey(.A) == 'a')
    Swag.assert(Input.Keyboard.virtualKeyToKey('a') == .A)

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
    Swag.assert(not Env.processWindowMessages())
    Swag.assert(window.isOpen())
    expect window.close()
    expect window.close()
    Swag.assert(not window.isOpen() and context.windows == null)

    // Callback closure must not leave a dangling owner in event dispatch.
    var callbackWindow = expect returnedDesktopWindow()
    callbackWindow.callbacks.onPaint = &closeDesktopPaint
    expect callbackWindow.showOffScreen()
    callbackWindow.requestPaint()
    Swag.assert(not Env.processWindowMessages())
    Swag.assert(not callbackWindow.isOpen() and context.windows == null)

    // A native consumer can destroy the drawable before the owner sees DestroyNotify.
    var externalWindow = expect returnedDesktopWindow()
    let external       = context.windows
    expect LinuxDesktop.check(context, context.xcb_destroy_window_checked(unwrap context.connection, external.id))
    expect externalWindow.close()
    Swag.assert(not externalWindow.isOpen() and context.windows == null)
    g_DesktopCallbackOwner = null
}

#[Swag.TestTag("integration.desktop")]
#test
{
    var outcome: Swag.Error
    discard catch Env.createWindow({identifier: "invalid", title: "invalid", width: 0, height: 10}) as outcome
    Swag.assert(outcome.value() is Errors.BadParameterError)
    discard catch Env.createWindow({identifier: "invalid", title: "invalid", width: 10, height: 65536}) as outcome
    Swag.assert(outcome.value() is Errors.BadParameterError)
    discard catch Env.createWindow({identifier: "invalid", title: "bad\0title", width: 10, height: 10}) as outcome
    Swag.assert(outcome.value() is Errors.BadParameterError)
}

// Run separately with DISPLAY naming an unavailable server, so no desktop is required.
#[Swag.TestTag("integration.desktop.missing")]
#test
{
    for 4
    {
        Swag.assert(Env.getMonitors().isEmpty())
        let position = Input.mousePosition()
        Swag.assert(position.x == 0 and position.y == 0)
        var keyboard: Input.Keyboard
        keyboard.update()
        for key in Input.Key do
            Swag.assert(not keyboard.isKeyPressed(key))
        var outcome: Swag.Error
        discard catch returnedDesktopWindow() as outcome
        Swag.assert(outcome.value() is Swag.SystemError)
    }
}
