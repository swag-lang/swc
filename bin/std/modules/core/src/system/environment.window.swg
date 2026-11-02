#global public
#global namespace Env

// Handles a window paint request.
alias WindowPaintCallback = func||(*Window)

// Handles a window resize and receives the new client size in physical pixels.
alias WindowResizeCallback = func||(*Window, s32, s32)

// Handles native keyboard-focus gain (`true`) or loss (`false`) for a window.
//
// Runs during platform event dispatch on the window-owning thread. The callback may close
// its window; the dispatcher does not access the owner after returning from this callback.
alias WindowFocusCallback = func||(*Window, bool)

// Identifies the mouse action delivered to a window.
enum WindowPointerKind
{
    Move           // The pointer moved in the client area.
    ButtonDown     // A supported mouse button was pressed.
    ButtonUp       // A supported mouse button was released.
    Wheel          // A horizontal or vertical wheel moved.
}

// Describes one mouse action in a window's client coordinate system.
//
// Coordinates are physical pixels from the client area's top-left corner and may be negative.
// Wheel deltas are measured in notches: positive X scrolls right and positive Y scrolls up.
// Fractional wheel deltas are preserved when the backend supplies them. This value contains
// no borrowed storage and may be copied by the receiver.
struct WindowPointerEvent
{
    public
    {
        kind:   WindowPointerKind     // Selects the meaningful action fields.
        x:      s32                   // Horizontal client coordinate in physical pixels.
        y:      s32                   // Vertical client coordinate in physical pixels.
        button: Input.MouseButton     // Meaningful only for ButtonDown and ButtonUp.
        wheelX: f32                   // Horizontal notches for Wheel; zero for other actions.
        wheelY: f32                   // Vertical notches for Wheel; zero for other actions.
    }
}

// Handles a mouse action delivered to a window.
//
// Runs during platform event dispatch on the window-owning thread. The callback may close
// its window. Delivery follows the platform's native pointer routing; installing this callback
// does not request pointer capture, keyboard focus, or double-click recognition.
alias WindowPointerCallback = func||(*Window, WindowPointerEvent)

// Groups the optional callbacks dispatched by a [[Core.Env.Window]].
struct WindowCallbacks
{
    public
    {
        onPaint:   WindowPaintCallback?       // Invoked for a paint request.
        onResize:  WindowResizeCallback?      // Invoked with the new client size in physical pixels.
        onFocus:   WindowFocusCallback?       // Invoked when native keyboard focus is gained or lost.
        onPointer: WindowPointerCallback?     // Invoked for mouse movement, buttons, or wheel input.
    }
}

// Configures the capabilities exposed by a top-level window.
#[Swag.EnumFlags]
enum WindowFlags
{
    None = 0        // Creates a fixed-size window without minimize or maximize controls.
    Resizable       // Lets the user resize the window.
    Minimizable     // Displays a minimize control.
    Maximizable     // Displays a maximize control.
    Standard = Resizable | Minimizable | Maximizable     // Creates a standard resizable application window.
}

// Configures top-level window creation.
//
// `width` and `height` are logical units: the created window is proportionally
// larger, in physical pixels, on a scaled display. The client size reported to
// [[Core.Env.WindowResizeCallback]] is physical.
struct WindowOptions
{
    public
    {
        identifier: string     // Unique backend-independent window identifier.
        title:      string     // Initial window title.
        width:      s32        // Width in logical units.
        height:     s32        // Height in logical units.
        flags:      WindowFlags = .Standard     // Window-manager capabilities.
    }
}

// Owns one top-level application window.
//
// Create a window with [[Core.Env.createWindow]]. The value closes any remaining window
// when it leaves scope; call [[Core.Env.Window.close]] to release it earlier.
// On Linux, windows use X11/XWayland and belong to the thread that creates the first
// window. Creation, methods, moves, destruction and event dispatch must stay on that
// thread. Logical units equal physical pixels; native Wayland and automatic scaling
// are not provided. Console-only use of Core does not load a desktop library.
#[Swag.NoCopy]
struct Window
{
    internal
    {
        nativeHandle: const *void?     // Opaque platform window storage.
    }

    public callbacks: WindowCallbacks     // Callbacks dispatched by the platform event adapter.
}

// Pumps window events until closing is requested or a smoke run's frame budget is spent.
//
// A close request stops the loop while the window is still open. Release resources that use
// its native handle before closing the window or leaving its scope.
struct WindowLoop
{
    // Frames a smoke run should render for this program, or zero to take the launcher's budget.
    //
    // A program that cycles through pages knows how many frames it takes to show them all,
    // and that count is a property of its content rather than of whoever launched it. It has
    // no effect on a normal run, which ends when the window is asked to close.
    public smokeFrames: u32

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
    // Only a platform rendering adapter should interpret this value. Obtain it on the owning
    // window thread; the borrowed descriptor may then be read by a rendering worker while the
    // window stays open. Closing the window invalidates it; moving the owner does not.
    mtd nativeRenderHandle()->const *void?
    {
        if .isOpen() do
            .rebindNative()
        return .renderHandleNative()
    }

    // Closes the window if it is still open.
    //
    // Calling `close` repeatedly is safe. Failure leaves the platform resource owned by this
    // value, so a later call or scope cleanup can retry the release.
    mtd close() fail
    {
        if not .isOpen() do
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

    // Resizes the client area to `width` by `height` logical units, keeping the window position.
    //
    // The realized client area is proportionally larger, in physical pixels, on a
    // scaled display; [[Core.Env.WindowResizeCallback]] reports that physical size.
    mtd setClientSize(width, height: s32) fail
    {
        if .isOpen() do
            .rebindNative()
        let scale          = .dpiScale()
        let physicalWidth  = cast(s32, Math.round(width * scale))
        let physicalHeight = cast(s32, Math.round(height * scale))
        try .setClientSizeNative(physicalWidth, physicalHeight)
    }

    // Requests a window position in physical screen pixels without resizing or activating it.
    //
    // `x` and `y` name the native top-level placement request. Unlike client sizes, screen
    // positions are not multiplied by the window's DPI scale. A window manager may adjust or
    // defer that request and account for its own decoration frame; this does not guarantee an
    // exact outer-frame or client-area origin. Completion does not promise that the desktop has
    // already presented the new placement.
    // Platform coordinate limits may reject the request. Fails for a closed window, a rejected
    // native request, or a call outside the window-owning thread.
    mtd setPosition(x, y: s32) fail => try .setPositionNative(x, y)

    // Hides the window without releasing its drawable or callbacks.
    //
    // Repeated calls on an open hidden window are harmless. Call [[Core.Env.Window.show]] to
    // display it again. Fails for a closed window, a rejected native request, or a call outside
    // the window-owning thread. The desktop may deliver focus loss during this operation.
    mtd hide() fail => try .hideNative()

    // Requests keyboard focus for an open, visible window.
    //
    // Does not show a hidden window. Native focus rules and the window manager may reject or
    // override the request; [[Core.Env.WindowCallbacks.onFocus]] reports actual transitions.
    // Fails for a closed or hidden window, a rejected native request, or a call outside the
    // window-owning thread. Focus callbacks may run before this call returns.
    mtd requestFocus() fail => try .requestFocusNative()

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
            .callbacks.onResize(me, width, height)
        }

        try .showNative()
    }

    // Realizes the window without putting it in front of the user.
    //
    // The window is placed outside the visible desktop and shown without taking activation, so
    // its drawable is complete — which is what a graphics context needs before it can render and
    // read back — while nothing appears on screen and nothing steals the focus. A headless check
    // that needs a real drawable asks for this instead of [[Core.Env.Window.show]].
    // On Linux, at least one client dimension must be at most 32768 pixels so X11 can
    // place the complete drawable outside its root screen; larger pairs fail.
    mtd showOffScreen() fail
    {
        if .isOpen() do
            .rebindNative()
        if .callbacks.onResize
        {
            let {width, height} = try .clientSizeNative()
            .callbacks.onResize(me, width, height)
        }

        try .showOffScreenNative()
    }
}

// Creates and owns a top-level application window.
//
// The returned [[Core.Env.Window]] keeps its platform-specific state opaque and closes the
// window when it leaves scope. The logical `options` size is realized in the physical pixels
// of the monitor where the platform creates it.
func createWindow(options: WindowOptions)->Window fail
{
    var result: #returntype
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

        if not processWindowMessages() do
            return false

        if .frameBudget do
            .framesRun += 1

        return true
    }
}
