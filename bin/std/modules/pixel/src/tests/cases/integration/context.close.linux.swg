#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

using Core

struct ManagedCloseProbe
{
    requests: u32
    accept:   bool
    pending:  bool
    focused:  bool
    width:    s32
    height:   s32
}

var g_ManagedClose: ManagedCloseProbe

func recordManagedClose(window: *Env.Window)
{
    Swag.require(window.isOpen())
    g_ManagedClose.requests += 1
    g_ManagedClose.pending  = g_ManagedClose.accept
}

func recordManagedFocus(_: *Env.Window, focused: bool)
{
    g_ManagedClose.focused = focused
}

func recordManagedResize(_: *Env.Window, width, height: s32)
{
    g_ManagedClose.width  = width
    g_ManagedClose.height = height
}

func(T) managedCloseSymbol(library: *void, name: string)->T
{
    let address = Linux.dlsym(library, name.buffer)
    Swag.require(address != null)
    return cast(T, address)
}

// Send the window-manager protocol through the public drawable view, without consuming
// Core's event queue or taking ownership of its connection or window.
func sendManagedClose(window: *Env.Window)
{
    let library = Linux.dlopen("libxcb.so.1".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
    Swag.require(library != null)
    defer discard Linux.dlclose(unwrap library)
    let intern     = managedCloseSymbol'Linux.xcb_intern_atom_fn(library, "xcb_intern_atom")
    let reply      = managedCloseSymbol'Linux.xcb_intern_atom_reply_fn(library, "xcb_intern_atom_reply")
    let send       = managedCloseSymbol'Linux.xcb_send_event_checked_fn(library, "xcb_send_event_checked")
    let check      = managedCloseSymbol'Linux.xcb_request_check_fn(library, "xcb_request_check")
    let drawable   = expect window.xcbDrawable()
    let connection = unwrap drawable.connection
    let protocols  = reply(connection, intern(connection, 0, 12, "WM_PROTOCOLS".buffer), null)
    Swag.require(protocols != null)
    defer Linux.free(protocols)
    let close = reply(connection, intern(connection, 0, 16, "WM_DELETE_WINDOW".buffer), null)
    Swag.require(close != null)
    defer Linux.free(close)
    with var message: Linux.xcb_client_message_event_t
    {
        .response_type = 33
        .format        = 32
        .window        = drawable.window
        .type          = protocols.atom
        .data[0]       = close.atom
    }

    let error = check(connection, send(connection, 0, drawable.window, 0, cast(const [*]u8, &message)))
    defer Linux.free(error)
    Swag.require(error == null)
}

// Requires an isolated X11 display with software OpenGL; no desktop focus is stolen.
#[Swag.TestTag("integration.renderer.opengl")]
#test
{
    g_ManagedClose = {}
    defer g_ManagedClose = {}
    var firstWindow = expect Env.createWindow({identifier: "pixel-managed-first", title: "First managed drawable",
                                               width: 32, height: 32, stopLoopOnClose: false})
    var survivor = expect Env.createWindow({identifier: "pixel-managed-survivor", title: "Surviving drawable",
                                            width: 32, height: 32, stopLoopOnClose: false})
    firstWindow.callbacks.onCloseRequest = &recordManagedClose
    survivor.callbacks.onCloseRequest    = &recordManagedClose
    survivor.callbacks.onResize          = &recordManagedResize
    survivor.callbacks.onFocus           = &recordManagedFocus
    expect firstWindow.show()
    expect survivor.show()
    expect firstWindow.requestFocus()
    let initialPump = Env.processWindowMessages()
    Swag.require(initialPump)

    var backend:  RenderOgl
    let renderer: IRenderer = &backend
    var first = expect renderer.createContext(firstWindow.nativeRenderHandle(), 32, 32)
    defer renderer.deleteContext(&first)
    renderer.setCurrentContext(first)
    renderer.init()
    var second = expect renderer.createContext(survivor.nativeRenderHandle(), 32, 32, &first)
    defer renderer.deleteContext(&second)
    scope
    {
        var target = renderer.createRenderTarget(16, 16)
        defer renderer.deleteRenderTarget(&target)
        var painter = Painter.create(renderer)
        renderer.begin(first)
        painter.begin()
        painter.bindRenderTarget(&target)
        painter.setColorMaskFull()
        painter.setBlendingMode(.Copy)
        painter.clear(Argb.Red)
        painter.unbindRenderTarget()
        painter.end()
        expect renderer.draw(&painter)
        renderer.end()

        // A declined request leaves both the drawable and its renderer borrow alive.
        sendManagedClose(&firstWindow)
        let declinedPump = Env.processWindowMessages()
        Swag.require(declinedPump and g_ManagedClose.requests == 1 and not g_ManagedClose.pending)
        Swag.require(firstWindow.isOpen() and survivor.isOpen())

        // Acceptance schedules teardown after dispatch, so rendering detaches first.
        g_ManagedClose.accept = true
        sendManagedClose(&firstWindow)
        let acceptedPump = Env.processWindowMessages()
        Swag.require(acceptedPump and g_ManagedClose.requests == 2 and g_ManagedClose.pending)
        Swag.require(firstWindow.isOpen())
        renderer.setCurrentContext(second)
        renderer.deleteContext(&first)
        expect firstWindow.close()
        let survivorPump = Env.processWindowMessages()
        Swag.require(survivorPump and not firstWindow.isOpen() and survivor.isOpen())
        Swag.require(g_ManagedClose.requests == 2)
        let retained = renderer.readRenderTarget(&target, 0, 0, 16, 16)
        Swag.require(retained.pixelColor(7, 9).argb == Argb.Red)

        expect survivor.setClientSize(48, 40)
        expect survivor.requestFocus()
        let resizedPump = Env.processWindowMessages()
        Swag.require(resizedPump and g_ManagedClose.focused)
        Swag.require(g_ManagedClose.width == 48 and g_ManagedClose.height == 40)
        second.width  = g_ManagedClose.width
        second.height = g_ManagedClose.height
        renderer.begin(second)
        let size = renderer.targetSize()
        Swag.require(size.width == 48 and size.height == 40)
        painter.begin()
        painter.bindRenderTarget(&target)
        painter.setColorMaskFull()
        painter.setBlendingMode(.Copy)
        painter.clear(Argb.Blue)
        painter.unbindRenderTarget()
        painter.end()
        expect renderer.draw(&painter)
        let actual = renderer.readRenderTarget(&target, 0, 0, 16, 16)
        Swag.require(actual.pixelColor(7, 9).argb == Argb.Blue)
        renderer.end()
    }

    renderer.deleteContext(&second)
    expect survivor.close()
    let finalPump = Env.processWindowMessages()
    Swag.require(finalPump and not survivor.isOpen() and g_ManagedClose.requests == 2)

    // The application chooses to return; closing its last managed window does not quit the pump.
}
