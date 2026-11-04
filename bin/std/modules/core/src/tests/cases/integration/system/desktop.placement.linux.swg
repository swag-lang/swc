#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

var g_PlacementFocused: bool

func recordPlacementFocus(_: *Env.Window, focused: bool)
{
    g_PlacementFocused = focused
}

// Requires an isolated X11 display without a window manager, so requested coordinates
// are directly observable instead of being adjusted by desktop placement policy.
#[Swag.TestTag("integration.desktop.placement")]
#test
{
    func geometry(window: *Env.Window)->Math.Rectangle
    {
        let context  = expect LinuxDesktop.ensure()
        let drawable = expect window.xcbDrawable()
        var error: *Linux.xcb_generic_error_t?
        let reply    = context.xcb_get_geometry_reply(unwrap context.connection,
                                                      context.xcb_get_geometry(context.connection, drawable.window),
                                                      &error)
        defer if error do
            Linux.free(error)
        defer if reply do
            Linux.free(reply)
        Swag.require(error == null and reply != null)
        return {cast(f32, reply.x), cast(f32, reply.y), cast(f32, reply.width), cast(f32, reply.height)}
    }

    var original = expect Env.createWindow({identifier: "swag-placement", title: "Window placement", width: 80, height: 60})
    let drawable = original.nativeRenderHandle()
    var window   = #move original
    window.callbacks.onFocus = &recordPlacementFocus
    expect window.setPosition(-130, 42)
    Swag.require(geometry(&window) == Math.Rectangle{-130, 42, 80, 60})
    expect window.show()
    expect window.requestFocus()
    Swag.require(Env.processWindowMessages() and g_PlacementFocused)
    expect window.hide()
    expect window.hide()
    Swag.require(window.isOpen() and window.nativeRenderHandle() == drawable)
    Swag.require(Env.processWindowMessages() and not g_PlacementFocused)

    // A hidden drawable still has geometry, but the X11 server rejects keyboard focus.
    var outcome: Swag.Error
    catch window.requestFocus() as outcome
    Swag.require(outcome.value() is Swag.SystemError)
    expect window.setPosition(19, -7)
    expect window.setClientSize(110, 70)
    Swag.require(geometry(&window) == Math.Rectangle{19, -7, 110, 70})
    expect window.show()
    expect window.requestFocus()
    Swag.require(Env.processWindowMessages() and g_PlacementFocused)

    let outside: [4]Math.Point = [{-32769, 0}, {32768, 0}, {0, -32769}, {0, 32768}]
    for point in outside
    {
        catch window.setPosition(cast(s32, point.x), cast(s32, point.y)) as outcome
        Swag.require(outcome.value() is Errors.BadParameterError)
    }

    Swag.require(geometry(&window) == Math.Rectangle{19, -7, 110, 70})
    expect window.close()
    catch window.hide() as outcome
    Swag.require(outcome.value() is Errors.BadParameterError)
    catch window.requestFocus() as outcome
    Swag.require(outcome.value() is Errors.BadParameterError)
    catch window.setPosition(0, 0) as outcome
    Swag.require(outcome.value() is Errors.BadParameterError)
    g_PlacementFocused = false
}

struct WindowThreadProbe
{
    window:   *Env.Window?
    rejected: u32
}

func mutateWindowFromWorker(thread: const *Threading.Thread)
{
    let probe  = cast(*WindowThreadProbe, unwrap thread.userParam)
    let window = unwrap probe.window
    var outcome: Swag.Error
    catch window.setPosition(31, 47) as outcome
    if outcome.value() is Errors.BadParameterError do
        probe.rejected += 1
    catch window.hide() as outcome
    if outcome.value() is Errors.BadParameterError do
        probe.rejected += 1
    catch window.requestFocus() as outcome
    if outcome.value() is Errors.BadParameterError do
        probe.rejected += 1
}

#[Swag.TestTag("integration.desktop.placement")]
#test
{
    var window = expect Env.createWindow({identifier: "swag-placement-thread", title: "Window owner", width: 80, height: 60})
    var probe  = WindowThreadProbe{&window}
    var thread: Threading.Thread
    expect thread.init(&mutateWindowFromWorker, &probe)
    expect thread.start()
    thread.wait()
    Swag.require(probe.rejected == 3 and window.isOpen())
    expect window.setPosition(10, 20)
    expect window.show()
    expect window.requestFocus()
    Swag.require(Env.processWindowMessages())
}
