#global public
#global namespace Env

// Handles a window paint request.
alias WindowPaintCallback = func||(*Window)

// Handles a window resize and receives the new client size in physical pixels.
alias WindowResizeCallback = func||(*Window, s32, s32)

// Groups the optional callbacks dispatched by a [[Core.Env.Window]].
struct WindowCallbacks
{
    onPaint:  #null WindowPaintCallback      // Invoked for a paint request.
    onResize: #null WindowResizeCallback     // Invoked after the logical client size changes.
}

// Configures the capabilities exposed by a top-level window.
#[Swag.EnumFlags]
enum WindowFlags
{
    None = 0                                             // Creates a fixed-size window without minimize or maximize controls.
    Resizable                                            // Lets the user resize the window.
    Minimizable                                          // Displays a minimize control.
    Maximizable                                          // Displays a maximize control.
    Standard = Resizable | Minimizable | Maximizable     // Creates a standard resizable application window.
}

// Configures top-level window creation.
//
// `width` and `height` are logical units: the created window is proportionally
// larger, in physical pixels, on a scaled display. The client size reported to
// [[Core.Env.WindowResizeCallback]] is physical.
struct WindowOptions
{
    identifier: string                      // Unique backend-independent window identifier.
    title:      string                      // Initial window title.
    width:      s32                         // Width in logical units.
    height:     s32                         // Height in logical units.
    flags:      WindowFlags = .Standard     // Window-manager capabilities.
}

// Owns one top-level application window.
//
// Create a window with [[Core.Env.createWindow]]. The value closes any remaining window
// when it leaves scope; call [[Core.Env.Window.close]] to release it earlier.
#[Swag.NoCopy]
struct Window
{
    internal
    {
        nativeHandle: #null const *void     // Opaque platform window storage.
    }

    callbacks: WindowCallbacks     // Callbacks dispatched by the platform event adapter.
}

// Provides iterable window-event processing.
// Pumps events until the window closes, or until a smoke run's frame budget is spent.
struct WindowLoop
{
    // Frames a smoke run should render for this program, or zero to take the launcher's budget.
    //
    // A program that cycles through pages knows how many frames it takes to show them all,
    // and that count is a property of its content rather than of whoever launched it. It has
    // no effect on a normal run, which ends only when the window closes.
    smokeFrames: u32

    internal
    {
        frameBudget: u32     // Frames this run may render; zero outside a smoke run.
        framesRun:   u32     // Frames rendered so far.
    }
}

impl Window
{
    // Rebinds the platform callback state when an owning window value moves.
    mtd opPostMove()
    {
        if .isOpen() do
            .rebindNative()
    }

    // Closes any remaining window when this value leaves scope.
    mtd opDrop()
    {
        catch .close()
    }

    // Returns whether the window still owns a platform resource.
    mtd const isOpen()->bool => .nativeHandle != null

    // Returns the borrowed opaque drawable used to create a rendering context.
    //
    // Only a platform rendering adapter should interpret this value.
    mtd nativeRenderHandle()->#null const *void
    {
        if .isOpen() do
            .rebindNative()
        return .nativeHandle
    }

    // Closes the window if it is still open.
    //
    // Calling `close` repeatedly is safe. Failure leaves the platform resource owned by this
    // value, so a later call or scope cleanup can retry the release.
    mtd close() fail
    {
        if !.isOpen() do
            return

        // Keep callbacks bound to the owning value even when a return-value move was elided
        // without invoking opPostMove in an unoptimized build.
        .rebindNative()
        try .closeNative()
        .nativeHandle = null
    }

    // Queues a paint request for this window.
    mtd requestPaint()
    {
        if .isOpen() do
            .rebindNative()
        .requestPaintNative()
    }

    // Resizes the client area to `width` by `height` logical units while preserving
    // the current position.
    //
    // The realized client area is proportionally larger, in physical pixels, on a
    // scaled display; [[Core.Env.WindowResizeCallback]] reports that physical size.
    mtd setClientSize(width, height: s32) fail
    {
        if .isOpen() do
            .rebindNative()
        let scale          = .dpiScale()
        let physicalWidth  = cast(s32) Math.round(width * scale)
        let physicalHeight = cast(s32) Math.round(height * scale)
        try .setClientSizeNative(physicalWidth, physicalHeight)
    }

    // Shows the window and updates its client area.
    //
    // The resize callback receives the initial physical client size before the
    // window becomes visible, so a renderer never draws a frame at a stale size.
    mtd show() fail
    {
        if .isOpen() do
            .rebindNative()
        if .callbacks.onResize
        {
            let {width, height} = try .clientSizeNative()
            let onResize        = .callbacks.onResize!
            onResize(&me, width, height)
        }

        try .showNative()
    }
}

// Creates and owns a top-level application window.
//
// The returned [[Core.Env.Window]] keeps its platform-specific state opaque and closes the
// window when it leaves scope. The logical `options` size is realized in the physical pixels
// of the monitor where the platform creates it.
func createWindow(options: WindowOptions)->Window fail
{
    var result: retval
    defer #fail catch result.close()
    try createWindowNative(&result, options)
    try result.setClientSize(options.width, options.height)
    return result
}

impl WindowLoop
{
    // Processes pending events and returns whether the application should continue.
    mtd next()->bool
    {
        // A smoke run is bounded by whoever launched it, so a program driving its own loop
        // stops on its own without recognizing that it is being exercised.
        if .frameBudget == 0
        {
            .frameBudget = Env.smokeFrames()
            if .frameBudget and .smokeFrames do
                .frameBudget = .smokeFrames
        }

        if .frameBudget and .framesRun >= .frameBudget do
            return false

        if !processWindowMessages() do
            return false

        if .frameBudget do
            .framesRun += 1

        return true
    }
}
