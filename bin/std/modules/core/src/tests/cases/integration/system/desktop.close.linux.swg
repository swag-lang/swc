#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

var g_CloseRequests:    u32
var g_CloseOwner:       *Env.Window?
var g_CloseMovedWindow: Env.Window
var g_ClosePaints:      u32

func requestDesktopClose(window: *Env.Window)
{
    let native  = cast #unconst (*LinuxDesktop.WindowState, unwrap window.nativeHandle)
    let context = unwrap native.context
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
}

func expectDesktopPump(running: bool)
{
    let result = Env.processWindowMessages()
    Swag.require(result == running)
}

func recordDesktopClose(owner: *Env.Window)
{
    g_CloseRequests += 1
    g_CloseOwner    = owner
}

func acceptDesktopClose(owner: *Env.Window)
{
    recordDesktopClose(owner)
    expect owner.close()
}

func moveDesktopClose(owner: *Env.Window)
{
    recordDesktopClose(owner)
    g_CloseMovedWindow = #move owner[]
}

func recordCloseSurvivorPaint(owner: *Env.Window)
{
    g_ClosePaints += 1
    g_CloseOwner  = owner
}

func managedDesktopWindow()->Env.Window fail
{
    return try Env.createWindow({identifier: "managed-close", title: "Managed close",
                                 width: 80, height: 60, stopLoopOnClose: false})
}

#[Swag.TestTag("integration.desktop")]
#test
{
    // The default still stops dispatch without destroying the requested window.
    var window = expect Env.createWindow({identifier: "default-close", title: "Default close",
                                          width: 80, height: 60})
    requestDesktopClose(&window)
    expectDesktopPump(false)
    Swag.require(window.isOpen())
    expectDesktopPump(true)
    expect window.close()
}

#[Swag.TestTag("integration.desktop")]
#test
{
    g_CloseRequests = 0
    defer g_CloseOwner = null
    var window = expect managedDesktopWindow()
    window.callbacks.onCloseRequest = &recordDesktopClose
    for 2
    {
        requestDesktopClose(&window)
        expectDesktopPump(true)
        Swag.require(window.isOpen())
    }

    Swag.require(g_CloseRequests == 2 and g_CloseOwner == &window)
    expect window.close()
    expect window.close()
    expectDesktopPump(true)
    Swag.require(g_CloseRequests == 2)
}

#[Swag.TestTag("integration.desktop")]
#test
{
    g_CloseRequests = 0
    g_ClosePaints   = 0
    defer g_CloseOwner = null
    var closing  = expect managedDesktopWindow()
    var survivor = expect managedDesktopWindow()
    closing.callbacks.onCloseRequest = &acceptDesktopClose
    survivor.callbacks.onPaint       = &recordCloseSurvivorPaint
    expect survivor.showOffScreen()
    expectDesktopPump(true)
    g_ClosePaints = 0

    requestDesktopClose(&closing)
    survivor.requestPaint()
    expectDesktopPump(true)
    Swag.require(not closing.isOpen() and survivor.isOpen())
    Swag.require(g_CloseRequests == 1 and g_ClosePaints > 0 and g_CloseOwner == &survivor)
    expect survivor.close()
    expectDesktopPump(true)
    Swag.require(g_CloseRequests == 1)
}

#[Swag.TestTag("integration.desktop")]
#test
{
    g_CloseRequests = 0
    defer g_CloseOwner = null
    defer expect g_CloseMovedWindow.close()
    var original = expect managedDesktopWindow()
    original.callbacks.onCloseRequest = &moveDesktopClose
    requestDesktopClose(&original)
    expectDesktopPump(true)
    Swag.require(not original.isOpen() and g_CloseMovedWindow.isOpen() and g_CloseRequests == 1)

    g_CloseMovedWindow.callbacks.onCloseRequest = &acceptDesktopClose
    requestDesktopClose(&g_CloseMovedWindow)
    expectDesktopPump(true)
    Swag.require(not g_CloseMovedWindow.isOpen() and g_CloseRequests == 2 and g_CloseOwner == &g_CloseMovedWindow)
}

#[Swag.TestTag("integration.desktop")]
#test
{
    // DestroyNotify honors the same creation policy, including the last window.
    for stop in [false, true]
    {
        g_CloseRequests = 0
        var window = expect Env.createWindow({identifier: "external-close", title: "External close",
                                              width: 80, height: 60, stopLoopOnClose: stop})
        window.callbacks.onCloseRequest = &recordDesktopClose
        let native  = cast #unconst (*LinuxDesktop.WindowState, unwrap window.nativeHandle)
        let context = unwrap native.context
        expect LinuxDesktop.check(context,
                                  context.xcb_destroy_window_checked(unwrap context.connection, native.id))
        expectDesktopPump(not stop)
        Swag.require(not window.isOpen() and g_CloseRequests == 0)
    }
}

#[Swag.TestTag("integration.desktop")]
#test
{
    g_CloseRequests = 0
    defer g_CloseOwner = null
    var window = expect Env.createWindow({identifier: "default-callback", title: "Default callback",
                                          width: 80, height: 60})
    window.callbacks.onCloseRequest = &acceptDesktopClose
    requestDesktopClose(&window)
    expectDesktopPump(false)
    Swag.require(not window.isOpen() and g_CloseRequests == 1)
}
