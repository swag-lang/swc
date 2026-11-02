#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

struct WindowFocusNotice
{
    owner: *Env.Window?
    focused: bool
}

var g_WindowFocusNotices: Array'WindowFocusNotice

func recordWindowFocus(owner: *Env.Window, focused: bool)
{
    g_WindowFocusNotices.add({owner, focused})
}

func setWindowFocusForTest(window: u32)
{
    let context = expect LinuxDesktop.ensure()
    let setFocus = expect LinuxDesktop.symbol'Linux.xcb_set_input_focus_checked_fn(unwrap context.library, "xcb_set_input_focus_checked")
    expect LinuxDesktop.check(context, setFocus(unwrap context.connection, 0, window, 0))
}

// Requires an isolated X11 display: these requests change its real keyboard focus.
#[Swag.TestTag("integration.desktop")]
#test
{
    var first = expect Env.createWindow({identifier: "swag-focus-first", title: "Focus first", width: 80, height: 60})
    var second = expect Env.createWindow({identifier: "swag-focus-second", title: "Focus second", width: 80, height: 60})
    first.callbacks.onFocus = &recordWindowFocus
    second.callbacks.onFocus = &recordWindowFocus
    expect first.showOffScreen()
    expect second.showOffScreen()
    Swag.assert(Env.processWindowMessages())
    g_WindowFocusNotices.clear()

    setWindowFocusForTest((expect first.xcbDrawable()).window)
    // The event is already queued; moving must rebind it to the new owner.
    var moved = #move first
    Swag.assert(Env.processWindowMessages())
    Swag.assert(g_WindowFocusNotices.count == 1)
    Swag.assert(g_WindowFocusNotices[0].owner == &moved and g_WindowFocusNotices[0].focused)

    setWindowFocusForTest((expect second.xcbDrawable()).window)
    Swag.assert(Env.processWindowMessages())
    Swag.assert(g_WindowFocusNotices.count == 3)
    Swag.assert(g_WindowFocusNotices[1].owner == &moved and not g_WindowFocusNotices[1].focused)
    Swag.assert(g_WindowFocusNotices[2].owner == &second and g_WindowFocusNotices[2].focused)

    setWindowFocusForTest(0)
    Swag.assert(Env.processWindowMessages())
    Swag.assert(g_WindowFocusNotices.count == 4)
    Swag.assert(g_WindowFocusNotices[3].owner == &second and not g_WindowFocusNotices[3].focused)
    g_WindowFocusNotices.clear()
}

func closeWindowOnFocus(owner: *Env.Window, focused: bool)
{
    if focused do
        expect owner.close()
}

#[Swag.TestTag("integration.desktop")]
#test
{
    var window = expect Env.createWindow({identifier: "swag-focus-close", title: "Focus close", width: 80, height: 60})
    window.callbacks.onFocus = &closeWindowOnFocus
    expect window.showOffScreen()
    Swag.assert(Env.processWindowMessages())
    setWindowFocusForTest((expect window.xcbDrawable()).window)
    Swag.assert(not Env.processWindowMessages())
    Swag.assert(not window.isOpen())
}
