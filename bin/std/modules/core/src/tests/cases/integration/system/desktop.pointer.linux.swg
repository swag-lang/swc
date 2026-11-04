#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

struct WindowPointerNotice
{
    owner: *Env.Window?
    event: Env.WindowPointerEvent
}

var g_WindowPointerNotices: Array'WindowPointerNotice

func recordWindowPointer(owner: *Env.Window, event: Env.WindowPointerEvent)
{
    g_WindowPointerNotices.add({owner, event})
}

func sendWindowPointerForTest(window: u32, kind, button: u8, x, y: s16)
{
    let context = expect LinuxDesktop.ensure()
    with var packet: Linux.xcb_button_press_event_t
    {
        .response_type = kind
        .detail        = button
        .event         = window
        .event_x       = x
        .event_y       = y
        .same_screen   = 1
    }

    var mask: u32
    switch kind
    {
    case Linux.XCB_MOTION_NOTIFY:  mask = Linux.XCB_EVENT_MASK_POINTER_MOTION
    case Linux.XCB_BUTTON_PRESS:   mask = Linux.XCB_EVENT_MASK_BUTTON_PRESS
    case Linux.XCB_BUTTON_RELEASE: mask = Linux.XCB_EVENT_MASK_BUTTON_RELEASE
    }

    expect LinuxDesktop.check(context,
                              context.xcb_send_event_checked(unwrap context.connection,
                                                             0,
                                                             window,
                                                             mask,
                                                             cast(const [*]u8, &packet)))
}

#[Swag.TestTag("integration.desktop")]
#test
{
    var window = expect Env.createWindow({identifier: "swag-pointer", title: "Pointer", width: 80, height: 60})
    let id     = (expect window.xcbDrawable()).window
    sendWindowPointerForTest(id, Linux.XCB_MOTION_NOTIFY, 0, 1, 2)
    let runningWithoutCallback = Env.processWindowMessages()
    Swag.require(runningWithoutCallback)
    window.callbacks.onPointer = &recordWindowPointer
    g_WindowPointerNotices.clear()
    defer g_WindowPointerNotices.clear()

    sendWindowPointerForTest(id, Linux.XCB_MOTION_NOTIFY, 0, -32768, 32767)
    let nativeButtons: [5]u8 = [1, 2, 3, 8, 9]
    for button in nativeButtons
    {
        sendWindowPointerForTest(id, Linux.XCB_BUTTON_PRESS, button, -11, 23)
        sendWindowPointerForTest(id, Linux.XCB_BUTTON_RELEASE, button, 17, -31)
    }

    for button in 4'u8 to 7'u8
    {
        sendWindowPointerForTest(id, Linux.XCB_BUTTON_PRESS, button, 5, 7)
        sendWindowPointerForTest(id, Linux.XCB_BUTTON_RELEASE, button, 5, 7)
    }

    // Unsupported button numbers must not become a left click.
    sendWindowPointerForTest(id, Linux.XCB_BUTTON_PRESS, 10, 0, 0)
    sendWindowPointerForTest(id, Linux.XCB_BUTTON_RELEASE, 0, 0, 0)

    var moved   = #move window
    let running = Env.processWindowMessages()
    Swag.require(running and g_WindowPointerNotices.count == 15)
    for notice in g_WindowPointerNotices do
        Swag.require(notice.owner == &moved)
    let motion = g_WindowPointerNotices[0].event
    Swag.require(motion.kind == .Move and motion.x == -32768 and motion.y == 32767)
    Swag.require(motion.wheelX == 0 and motion.wheelY == 0)

    let buttons: [5]Input.MouseButton = [.Left, .Middle, .Right, .XButton1, .XButton2]
    for button, index in buttons
    {
        let down = g_WindowPointerNotices[1 + index * 2].event
        let up   = g_WindowPointerNotices[2 + index * 2].event
        Swag.require(down.kind == .ButtonDown and up.kind == .ButtonUp)
        Swag.require(down.button == button and up.button == button)
        Swag.require(down.x == -11 and down.y == 23 and up.x == 17 and up.y == -31)
        Swag.require(down.wheelX == 0 and down.wheelY == 0 and up.wheelX == 0 and up.wheelY == 0)
    }

    let wheelX: [4]f32 = [0, 0, -1, 1]
    let wheelY: [4]f32 = [1, -1, 0, 0]
    for index in 0 until 4
    {
        let wheel = g_WindowPointerNotices[11 + index].event
        Swag.require(wheel.kind == .Wheel and wheel.x == 5 and wheel.y == 7)
        Swag.require(wheel.wheelX == wheelX[index] and wheel.wheelY == wheelY[index])
    }
}

func closeWindowOnPointer(owner: *Env.Window, event: Env.WindowPointerEvent)
{
    recordWindowPointer(owner, event)
    expect owner.close()
}

#[Swag.TestTag("integration.desktop")]
#test
{
    var survivor = expect Env.createWindow({identifier: "swag-pointer-survivor", title: "Survivor", width: 80, height: 60})
    var closing  = expect Env.createWindow({identifier: "swag-pointer-close", title: "Closing", width: 80, height: 60})
    survivor.callbacks.onPointer = &recordWindowPointer
    closing.callbacks.onPointer  = &closeWindowOnPointer
    g_WindowPointerNotices.clear()
    defer g_WindowPointerNotices.clear()

    let closingId = (expect closing.xcbDrawable()).window
    sendWindowPointerForTest(closingId, Linux.XCB_BUTTON_PRESS, 1, 2, 3)
    sendWindowPointerForTest(closingId, Linux.XCB_BUTTON_RELEASE, 1, 2, 3)
    sendWindowPointerForTest((expect survivor.xcbDrawable()).window, Linux.XCB_MOTION_NOTIFY, 0, 4, 5)
    let running = Env.processWindowMessages()

    // Closing any Core window stops this loop, even when another window remains owned.
    Swag.require(not running and not closing.isOpen() and survivor.isOpen())
    Swag.require(g_WindowPointerNotices.count == 1 and g_WindowPointerNotices[0].owner == &closing)
    expect survivor.close()

    // Restarting after all owners close must discard packets for the previous windows.
    var fresh = expect Env.createWindow({identifier: "swag-pointer-fresh", title: "Fresh", width: 80, height: 60})
    fresh.callbacks.onPointer = &recordWindowPointer
    sendWindowPointerForTest((expect fresh.xcbDrawable()).window, Linux.XCB_MOTION_NOTIFY, 0, 6, 7)
    let restarted = Env.processWindowMessages()
    Swag.require(restarted and g_WindowPointerNotices.count == 2)
    Swag.require(g_WindowPointerNotices[1].owner == &fresh)
    Swag.require(g_WindowPointerNotices[1].event.kind == .Move)
}

// Requires an isolated display: this uses native pointer motion rather than SendEvent.
#[Swag.TestTag("integration.desktop")]
#test
{
    let previous = Input.mousePosition()
    defer Input.setMousePosition(cast(s32, previous.x), cast(s32, previous.y))
    var window = expect Env.createWindow({identifier: "swag-pointer-motion", title: "Motion", width: 80, height: 60})
    expect window.show()
    let context  = expect LinuxDesktop.ensure()
    let drawable = expect window.xcbDrawable()
    expect LinuxDesktop.check(context,
                              context.xcb_warp_pointer_checked(unwrap drawable.connection,
                                                               0,
                                                               drawable.window,
                                                               0,
                                                               0,
                                                               0,
                                                               0,
                                                               1,
                                                               1))
    let initialRunning = Env.processWindowMessages()
    Swag.require(initialRunning)
    window.callbacks.onPointer = &recordWindowPointer
    g_WindowPointerNotices.clear()
    defer g_WindowPointerNotices.clear()

    expect LinuxDesktop.check(context,
                              context.xcb_warp_pointer_checked(unwrap drawable.connection,
                                                               0,
                                                               drawable.window,
                                                               0,
                                                               0,
                                                               0,
                                                               0,
                                                               37,
                                                               29))
    let running = Env.processWindowMessages()
    Swag.require(running and g_WindowPointerNotices.count == 1)
    let notice = g_WindowPointerNotices[0]
    Swag.require(notice.owner == &window and notice.event.kind == .Move)
    Swag.require(notice.event.x == 37 and notice.event.y == 29)
}
