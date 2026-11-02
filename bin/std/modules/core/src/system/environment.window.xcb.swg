#global if #os == Swag.TargetOs.Linux
#global namespace Env

// Borrows the XCB drawable of an open environment window for a native rendering adapter.
//
// The connection and identifiers remain valid only while the window is open and Core is loaded.
// Never disconnect the connection, destroy the window, or consume its event queue through this view.
public struct XcbDrawable
{
    public
    {
        connection: *void?     // Borrowed xcb_connection_t pointer.
        window:     u32        // Native X11 window identifier.
        visual:     u32        // Visual of the window, used to select a compatible renderer configuration.
        screen:     s32        // Zero-based X11 screen selected by DISPLAY.
    }
}

impl Window
{
    // Borrows the XCB drawable on the window's owning thread.
    //
    // Fails if the window is closed or the calling thread does not own it. The returned view
    // follows [[Core.Env.XcbDrawable]]'s lifetime; moving the owner does not change the drawable.
    public mtd xcbDrawable()->XcbDrawable fail
    {
        if not .isOpen() do
            fail Errors.BadParameterError{"an XCB drawable needs an open window"}
        let window  = cast(const *LinuxDesktop.WindowState, unwrap .nativeHandle)
        let context = unwrap window.context
        try LinuxDesktop.requireUiThread(context)
        .rebindNative()
        return {context.connection, window.id, context.screen.root_visual, context.screenIndex}
    }
}
