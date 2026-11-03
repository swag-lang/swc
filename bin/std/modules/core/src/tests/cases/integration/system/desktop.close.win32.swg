#global if #command == Swag.CompilerCommand.Test
#global if WINDOWS
#global private

using Win32

var g_CloseRequestCount: u32
var g_CloseRequestOwner: *Env.Window?

func recordCloseRequest(owner: *Env.Window)
{
    g_CloseRequestCount += 1
    g_CloseRequestOwner = owner
}

func moveAndCloseRequestedWindow(owner: *Env.Window)
{
    recordCloseRequest(owner)
    var moved = #move owner[]
    expect moved.close()
}

// Other desktop tests may have destroyed a default-policy window without draining its quit.
func drainCloseTestQuitMessages()
{
    var message: MSG
    while PeekMessageA(&message, null, WM_QUIT, WM_QUIT, PM_REMOVE) != 0 {}
}

#[Swag.TestTag("integration.desktop")]
#test
{
    drainCloseTestQuitMessages()
    defer drainCloseTestQuitMessages()
    g_CloseRequestCount = 0
    defer g_CloseRequestOwner = null
    var window = expect Env.createWindow({identifier: "swag-close-default", title: "Default close", width: 80, height: 60})
    window.callbacks.onCloseRequest = &recordCloseRequest
    let handle = cast(HWND, window.nativeRenderHandle())
    discard SendMessageA(handle, WM_CLOSE, 0, 0)
    Swag.require(g_CloseRequestCount == 1 and g_CloseRequestOwner == &window)
    let afterRequest = Env.processWindowMessages()
    Swag.require(window.isOpen() and not afterRequest)
    let afterConsumedQuit = Env.processWindowMessages()
    Swag.require(afterConsumedQuit and window.isOpen())
    expect window.close()
    let afterDestruction = Env.processWindowMessages()
    Swag.require(g_CloseRequestCount == 1 and not afterDestruction)
}

#[Swag.TestTag("integration.desktop")]
#test
{
    drainCloseTestQuitMessages()
    defer drainCloseTestQuitMessages()
    g_CloseRequestCount = 0
    defer g_CloseRequestOwner = null
    var survivor = expect Env.createWindow({identifier: "swag-close-survivor", title: "Survivor", width: 80, height: 60, stopLoopOnClose: false})
    var window   = expect Env.createWindow({identifier: "swag-close-managed", title: "Managed close", width: 80, height: 60, stopLoopOnClose: false})
    window.callbacks.onCloseRequest = &recordCloseRequest
    let handle = cast(HWND, window.nativeRenderHandle())
    discard SendMessageA(handle, WM_CLOSE, 0, 0)
    let afterRequest = Env.processWindowMessages()
    Swag.require(g_CloseRequestCount == 1 and window.isOpen() and afterRequest)
    expect window.close()
    let afterClose = Env.processWindowMessages()
    Swag.require(g_CloseRequestCount == 1 and survivor.isOpen() and afterClose)

    // Without a callback the managed request is ignored, but an external quit still exits.
    discard SendMessageA(cast(HWND, survivor.nativeRenderHandle()), WM_CLOSE, 0, 0)
    let afterUnhandledRequest = Env.processWindowMessages()
    Swag.require(survivor.isOpen() and afterUnhandledRequest)
    PostQuitMessage(7)
    let afterExternalQuit = Env.processWindowMessages()
    Swag.require(not afterExternalQuit)
    expect survivor.close()
    let afterFinalClose = Env.processWindowMessages()
    Swag.require(afterFinalClose)
}

#[Swag.TestTag("integration.desktop")]
#test
{
    drainCloseTestQuitMessages()
    defer drainCloseTestQuitMessages()
    g_CloseRequestCount = 0
    defer g_CloseRequestOwner = null
    var window = expect Env.createWindow({identifier: "swag-close-moved-managed", title: "Moved managed close", width: 80, height: 60, stopLoopOnClose: false})
    window.callbacks.onCloseRequest = &moveAndCloseRequestedWindow
    discard SendMessageA(cast(HWND, window.nativeRenderHandle()), WM_CLOSE, 0, 0)
    let running = Env.processWindowMessages()
    Swag.require(g_CloseRequestCount == 1 and not window.isOpen() and running)
}

#[Swag.TestTag("integration.desktop")]
#test
{
    drainCloseTestQuitMessages()
    defer drainCloseTestQuitMessages()
    g_CloseRequestCount = 0
    defer g_CloseRequestOwner = null
    var window = expect Env.createWindow({identifier: "swag-close-moved-default", title: "Moved default close", width: 80, height: 60})
    window.callbacks.onCloseRequest = &moveAndCloseRequestedWindow
    discard SendMessageA(cast(HWND, window.nativeRenderHandle()), WM_CLOSE, 0, 0)
    let running = Env.processWindowMessages()
    Swag.require(g_CloseRequestCount == 1 and not window.isOpen() and not running)
}
