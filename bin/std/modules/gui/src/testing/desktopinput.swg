#global public
#global namespace Testing

using Core

// Drives a native GUI surface with desktop pointer and keyboard input.
//
// The borrowed application and surface must outlive this value. Native input affects the user's
// desktop, so run one desktop test at a time in an interactive session. Dropping the value releases
// held inputs and restores the pointer. Each action checks focus and the actual hit target.
#[Swag.Opaque]
#[Swag.NoCopy]
struct DesktopInput
{
    using native: NativeDesktopInput
    app: *Application
    surface: *Surface
    savedCursor: Math.Point
    started: bool
}

impl DesktopInput
{
    // Starts native input for a visible surface and makes it the keyboard target.
    func create(app: *Application, surface: *Surface)->DesktopInput
    {
        var result = DesktopInput{app: app, surface: surface, savedCursor: Input.mousePosition()}
        result.openNative()
        result.started = true
        surface.bringToFront()
        result.focusNative()
        app.runFrame()
        result.requireNativeFocus()
        return result
    }

    mtd opDrop()
    {
        if not .started do
            return
        .closeNative()
        Input.setMousePosition(cast(s32, .savedCursor.x), cast(s32, .savedCursor.y))
    }

    // Moves the desktop pointer to a surface point and checks that `target` receives it.
    mtd moveTo(target: *Wnd, point: Math.Point)
    {
        var screen = point
        .surface.surfaceToScreen(&screen)
        .sendNativeMotion(screen)
        .app.runFrame()
        .requireNativeFocus()
        .requireNativePointerAt(screen)
        let hit = .surface.wnd.windowAt(point.x, point.y, false)
        if hit != target
        {
            Console.println("desktop target=", target.id, " surface=", point.x, ",", point.y)
            Console.println("desktop target rect=", target.surfaceRect())
            if hit do
                Console.println("desktop hit=", hit.id, " rect=", hit.surfaceRect())
            Swag.require(false, "another GUI control covers the desktop pointer target")
        }
    }

    // Clicks the current center of a visible control, following its actual layout.
    mtd click(target: *Wnd)
    {
        var watch: Time.Stopwatch
        watch.start()
        var previous: Math.Rectangle
        while true
        {
            .app.runFrame()
            let rect = target.surfaceRect()
            if rect == previous and not rect.isEmpty() and
               not target.wndFlags.has(.Hidden) and not target.wndFlags.has(.Disabled)
            {
                let center = Math.Point{target.position.width * 0.5, target.position.height * 0.5}
                let point = target.localToSurface(center)
                var screen = point
                .surface.surfaceToScreen(&screen)
                .sendNativeMotion(screen)
                .app.runFrame()
                if target.surfaceRect() == rect and .surface.wnd.windowAt(point.x, point.y, false) == target
                {
                    .requireNativeFocus()
                    .requireNativePointerAt(screen)
                    break
                }
            }
            if watch.elapsedMilliseconds() > 3000 do
                Swag.require(false, "desktop click target did not become stable and actionable")
            previous = rect
        }
        .sendNativeButton(true)
        .app.runFrame()
        .sendNativeButton(false)
        .app.runFrame()
    }

    // Drags between two surface points through the native pointer route.
    mtd drag(target: *Wnd, first, last: Math.Point)
    {
        .moveTo(target, first)
        .sendNativeButton(true)
        .app.runFrame()
        .moveTo(target, last)
        .sendNativeButton(false)
        .app.runFrame()
    }

    // Presses a desktop shortcut through native keyboard input.
    mtd shortcut(key: Input.Key, modifiers: Input.KeyModifiers)
    {
        .requireNativeFocus()
        if modifiers & .Control
        {
            .sendNativeModifier(.Control, true)
            .app.runFrame()
        }
        if modifiers & .Shift
        {
            .sendNativeModifier(.Shift, true)
            .app.runFrame()
        }
        if modifiers & .Alt
        {
            .sendNativeModifier(.Alt, true)
            .app.runFrame()
        }
        .sendNativeKey(key, true)
        .app.runFrame()
        .sendNativeKey(key, false)
        .app.runFrame()
        if modifiers & .Alt
        {
            .sendNativeModifier(.Alt, false)
            .app.runFrame()
        }
        if modifiers & .Shift
        {
            .sendNativeModifier(.Shift, false)
            .app.runFrame()
        }
        if modifiers & .Control
        {
            .sendNativeModifier(.Control, false)
            .app.runFrame()
        }
    }
}
