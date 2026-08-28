#global public

using Core, Serialization

// Callback invoked with the application that is processing a frame.
alias FrameCallback = func||(*Application)

// The two colors every Swag product mark is cut from, one glyph over one ground.
//
// A drawn caption keys the ground out with them, so it needs no second copy of the icon, and it
// compares the glyph against its own band to decide whether keying it out is legible at all.
// They are the identity colors and nothing else: a mark that drifts from them stops being one.
const MarkInk = Ink

// Secondary brand color used for the energized edge of the Swag mark.
const MarkVoltage = Voltage

// How much contrast the glyph of a mark owes a caption band before the band is allowed to show
// it without its tile. Three is where a shape stops being separated from what it is drawn over.
const MarkGlyphContrast = 3.0'f32

// Whether a band of `ground` can show a product mark with its tile keyed out.
//
// It is the one question that decides which cut of the mark a caption draws, so it is named
// rather than written inside the paint: a dark band shows the glyph alone, and a light band
// keeps the tile, because Voltage on paper is a mark nobody sees.
func markReadsOn(ground: Pixel.Color)->bool
{
    return MarkVoltage.contrastRatio(ground) >= MarkGlyphContrast
}

// Owns GUI resources, top-level surfaces, input state, and the event loop.
struct Application
{
    public
    {
        using native: ApplicationNative                 // Platform-specific application state.
        sigFrame:     SigArray'func||(*Application)     // Emitted after each processed frame.

        options: ApplicationOptions     // Diagnostics and development options.
        appIcon: Pixel.Image            // Icon used for native windows created by the application.
    }

    // The two cuts of `appIcon`, uploaded the first time a caption asks for one, so the drawn
    // title bar shows the same mark as the taskbar without the application saying so twice.
    // Which one a band takes is decided in [[Gui.Application.appIconAt]].
    appIconList:     ImageList     // The glyph alone, its ink ground keyed out.
    appIconTileList: ImageList     // The mark as it ships: the glyph on its ink tile.
    appIconLoaded:   bool
    public
    {
        // Named resources of the application: theme art, fonts, theme sheets, and language
        // files. The embedded content of every loaded module registers itself as the
        // fallback, so a bare application needs no configuration; add a disk folder before
        // creating the first surface to let files override any of those names.
        resources: Resources.Bundle
        readonly
        {
            #[Swag.Late]
            renderer: Pixel.IRenderer     // Renderer selected before the first surface is created.
        }
    }

    rendererOgl: Pixel.RenderOgl     // Default OpenGL renderer used when none is selected.
    public
    {
        #[Swag.Late]
        theme:       *Theme             // Active application theme.
        style:       ThemeStyle         // Root style inherited by surface window trees.
        keyboard:    Input.Keyboard     // Keyboard state for the current and previous frames.
        mouse:       Input.Mouse        // Mouse state for the current and previous frames.
        mainSurface: #null *Surface     // First surface, whose destruction requests application shutdown.

        // The surface list is maintained by the application: create and destroy surfaces through
        // its own API so the modal stack and the render loop stay consistent.
        readonly surfaces: Array'(*Surface)

        // Frame and input bookkeeping. Reading it tells what the application is doing this frame;
        // writing it from outside would desynchronize the loop from the window tree.
        animator: Animator     // Shared finite-animation scheduler.

        readonly
        {
            timing:           Time.FrameTiming               // Timing of the frame being run.
            motionPreference: MotionPreference = .System     // Application override of the platform motion preference.
            isActivated:      bool                           // Whether the application owns a native window.
        }
    }

    // Focus tracking, moved by the windows themselves as events are dispatched.
    keyboardFocusWnd:      #null *Wnd     // Window currently holding the keyboard focus.
    mouseCaptureWnd:       #null *Wnd     // Window currently holding the mouse capture.
    mouseEnterWnd:         #null *Wnd     // Window the mouse last entered.
    nativeFocusTransition: bool           // Whether a logical focus move is synchronously changing the native focus.

    // Drag and drop tracking. A gesture carrying a payload gets no mouse events at all, so the
    // window it is over and the position it reached are followed apart from the pointer state.
    dragEnterWnd:  #null *Wnd     // Window the drag last entered, or `null` outside a gesture.
    dragScreenPos: Math.Point     // Last position a drag reported, in physical screen pixels.
    public
    {
        // The tool tip belongs here for the same reason the focus and the drag do: it is one
        // pointer's state over one window tree. Held per process instead, two applications in a
        // process share one tip, and a test that leaves one open hands it to the next test — which
        // then destroys a window whose surface has already gone.
        toolTip: ToolTip.State     // The application's tool tip, and the signal its links report through.

        // Whether the keyboard focus must be shown.
        //
        // Keyboard traversal turns it on and a pointer press turns it off, so a control acted on
        // with the mouse keeps the focus without a ring around it while a surface being driven from
        // the keyboard always says where the keyboard is. Widgets read it through
        // [[Gui.Wnd.hasVisibleFocus]].
        readonly focusVisible: bool

        frameCursor: Cursor            // Cursor selected for the current frame.
        fadeDisabledSurface = true     // Whether modal-disabled surfaces fade toward the disabled theme color.
    }

    // Run-loop state. It only means something to the loop that owns it.
    postedEvents:        Array'(IEvent)                                             // Events queued from any thread, drained each frame.
    postDestroy:         Array'(*Wnd)                                               // Windows to destroy once the frame is over.
    hookOnEvent:         Array'(*Wnd)                                               // Windows watching every event of the application.
    endModalExit:        #null WndId                                                // Result the innermost modal loop exits with.
    inModalLoop:         u32                                                        // Depth of the modal loop nesting.
    quitCode:            s32                                                        // Exit code the run loop returns.
    mustQuit:            bool                                                       // Whether the run loop stops at the end of the frame.
    endModal:            bool                                                       // Whether the innermost modal loop stops.
    mutexPostedEvents:   Sync.Mutex                                                 // Guards 'postedEvents' against other threads.
    duringTimerEvents:   bool                                                       // Whether timer callbacks are running, so lists defer.
    timers:              Array'(*Timer)                                             // Active timers.
    timersToAdd:         Array'(*Timer)                                             // Timers added while callbacks were running.
    timersToDelete:      Array'(*Timer)                                             // Timers removed while callbacks were running.
    frameEvents:         Array'(*Wnd)                                               // Windows asking for a per-frame event.
    modalSurfaces:       Array'(*Surface)                                           // Surface stack of the nested modal loops.
    toDelete:            Array'{ ptr: #null *void, type: const *Swag.TypeInfo }     // Deferred deletions.
    systemReducedMotion: bool                                                       // Platform client-area-animation preference.
    public
    {
        // Stops the run loop after this many frames, or never when zero. A test or a scripted
        // run sets it to bound the loop without a user closing the window.
        maxRunFrame: u32
    }

    statePath: String                // File used by [[saveState]] and [[loadState]].
    hotKeys:   Array'KeyShortcut     // Registered system-wide keyboard shortcuts.

    public
    {
        readonly dirtyTheme: u32     // Revision incremented after each theme change.
    }
}

private impl Application
{
    // Send and process an event
    mtd sendEventPrivate(evt: IEvent, stopAt: #null *Wnd)
    {
        // Global hook events
        for hook in .hookOnEvent do
            hook.itf.onHookEvent(evt)

        if let ptr = evt as QuitEvent
        {
            .mustQuit = true
            .quitCode = ptr.quitCode
            return
        }

        let event = cast(*Event) evt

        // Be sure we have a target
        if !event.target do
            return

        // Parent hook events
        //
        // An ancestor that eats a child's event has handled it, so the event says so on its way
        // out: what follows an unaccepted key is a shortcut lookup and the keyboard navigation of
        // the surface, and neither may run over an ancestor that answered the key itself.
        var scan = event.target.ownerOrParent()
        while scan
        {
            if scan.hookOnChildEvent and scan.hookOnChildEvent(scan, evt)
            {
                event.accepted = true
                return
            }

            scan = scan.ownerOrParent()
        }

        // Send event to the target
        // If the target does not accept the event, then pass it to the parent
        event.accepted = true
        event.target.processEvent(evt)
        while !event.accepted
        {
            let target = event.target!
            event.target = target.owner orelse target.parent
            if !event.target or event.target == stopAt do
                break
            event.accepted = true
            event.target.processEvent(evt)
        }
    }

    mtd sendMouseEvents()
    {
        .mouse.update()

        // A drag in flight owns the pointer, and the gesture is already being delivered as its
        // own event to the window under it. The pointer state polled here would only tell a
        // second, contradictory story: a control lighting up as the payload passes over it, a
        // release fired when the payload is dropped, and — the visible one — a cursor set at
        // frame rate over the copy, move and refuse shapes the source is drawing, which takes
        // the pointer back to an arrow the moment it stops moving.
        if .dragEnterWnd
        {
            .frameCursor.clear()
            return
        }

        let mousePos = .mouse.position()

        // Wnd that will receive the message
        var targetWnd: #null *Wnd
        if .mouseCaptureWnd do
            targetWnd = .mouseCaptureWnd
        else do
            targetWnd = .windowAtMouse()
        targetWnd = skipDisabled(targetWnd)

        // If no target window, but one target surface, then we will send
        // to the surfaceWnd (we probably are in the shadow area)
        if !targetWnd
        {
            let targetSurface = .surfaceAt(mousePos.x, mousePos.y)
            if targetSurface
            {
                targetWnd = targetSurface.wnd
                targetWnd = skipDisabled(targetWnd)
            }
        }

        var evt = MouseEvent{}

        // Accept
        if targetWnd
        {
            evt.kind       = .Accept
            evt.surfacePos = targetWnd.screenToSurface(mousePos)
            evt.target     = targetWnd
            .sendEventPrivate(&evt, .mouseEnterWnd)
            targetWnd = evt.target
        }

        // Mouse enter/leave
        if !targetWnd or targetWnd != .mouseEnterWnd
        {
            // Enter
            if targetWnd
            {
                evt.kind       = .Enter
                evt.surfacePos = targetWnd.screenToSurface(mousePos)
                evt.target     = targetWnd
                .sendEventPrivate(&evt, .mouseEnterWnd)

                if targetWnd.toolTip.length do
                    .toolTip.show(targetWnd, evt.surfacePos, targetWnd.toolTip)
            }

            // Leave
            if .mouseEnterWnd and targetWnd != .mouseEnterWnd
            {
                evt.kind       = .Leave
                evt.surfacePos = .mouseEnterWnd.screenToSurface(mousePos)
                evt.target     = .mouseEnterWnd
                .sendEventPrivate(&evt, .mouseCaptureWnd)
            }

            // The tip decides for itself whether this move ends it: one carrying a link has to
            // survive the pointer reaching it, or the link could never be clicked.
            .toolTip.pointerMoved(.mouseEnterWnd, targetWnd)

            .mouseEnterWnd = targetWnd
        }

        evt.modifiers = .keyboard.pressedModifiers()

        // Move
        if targetWnd
        {
            // The raw movement is in physical screen pixels; deliver it in the
            // logical units of the target surface, like `surfacePos`.
            let scale = targetWnd.surface!.dpiScale
            let move  = .mouse.movement() / scale
            evt.surfacePos = targetWnd.screenToSurface(mousePos)
            evt.kind       = .Move
            evt.delta      = move
            targetWnd.sendEvent(&evt)
            if Math.abs(move.x) >= 0.5 or Math.abs(move.y) >= 0.5 do
                .toolTip.resetTimer(evt.surfacePos)
        }

        if .frameCursor.isValid() do
            Cursor.activate(.frameCursor)
        elif targetWnd and targetWnd.cursor.isValid() do
            Cursor.activate(targetWnd.cursor)
        else do
            Cursor.activate(Cursor.from(CursorShape.Arrow))
        .frameCursor.clear()
        if !targetWnd do
            return

        // Detect changes
        for i in @countof(.mouse.previousState.pressed)
        {
            let lastP = .mouse.previousState.pressed[i]
            let curP  = .mouse.currentState.pressed[i]
            if !lastP and curP
            {
                if .mouse.isButtonDoubleClick(cast(Input.MouseButton) i) do
                    evt.kind = .DoubleClick
                else
                {
                    evt.kind = .Pressed

                    // The pointer says which control is being acted on, so the ring the
                    // keyboard needs would only add noise from here on.
                    .setFocusVisible(false)
                    if targetWnd.focusPolicy != .None do
                        targetWnd.setFocus()
                }

                evt.button = cast(Input.MouseButton) i
                targetWnd.sendEvent(&evt)
                .toolTip.hide()
            }
            elif lastP and !curP
            {
                evt.kind   = .Released
                evt.button = cast(Input.MouseButton) i
                targetWnd.sendEvent(&evt)
            }
        }
    }

    // Puts the keyboard on the first traversal stop, or on the root view of a focusless surface.
    //
    // The innermost modal owns the keyboard while one is up; otherwise the main surface does. This
    // is a last resort for a surface that never placed its own focus — see
    // [[Gui.Wnd.setInitialFocus]] for saying it deliberately. A canvas-style surface has no
    // traversal stops, but its root still needs keys for a game or another direct-input view.
    internal mtd seedKeyboardFocus()
    {
        var surface = .mainSurface
        if .modalSurfaces.count do
            surface = .modalSurfaces.back()
        if !surface do
            return

        surface.wnd.setInitialFocus()
        if !.keyboardFocusWnd do
            surface.wnd.view.setFocus()
    }

    mtd sendMouseWheelEvent(z: s32)
    {
        var targetWnd = .mouseEnterWnd
        targetWnd = skipDisabled(targetWnd)
        if !targetWnd do
            return

        var evt      = MouseEvent{kind: .Wheel}
        let mousePos = .mouse.position()
        evt.surfacePos = targetWnd.screenToSurface(mousePos)
        evt.delta.y    = z
        evt.modifiers  = .keyboard.pressedModifiers()
        targetWnd.sendEvent(&evt)
    }

    mtd sendKeyboardEvents()
    {
        .keyboard.update()

        // Modifiers
        let modifiers = .keyboard.pressedModifiers()

        // Detect changes
        for i in @countof(.keyboard.previousState.pressed)
        {
            let lastP = .keyboard.previousState.pressed[i]
            let curP  = .keyboard.currentState.pressed[i]

            // A surface nothing has focused yet would be deaf to the keyboard. The first key
            // pressed is what seeds the focus, so a window can be driven from the keyboard without
            // having been clicked once.
            if curP and !lastP and !.keyboardFocusWnd do
                .seedKeyboardFocus()

            var targetWnd = .keyboardFocusWnd
            targetWnd = skipDisabled(targetWnd)
            if !targetWnd do
                continue

            if !lastP and curP
            {
                var evt = KeyEvent{kind: .Pressed}
                evt.key       = cast(Input.Key) i
                evt.modifiers = modifiers
                targetWnd.sendEvent(&evt)
                if !evt.accepted do
                    .routeUnhandledKey(targetWnd, cast(Input.Key) i, modifiers)
            }
            elif lastP and !curP
            {
                var evt = KeyEvent{kind: .Released}
                evt.key       = cast(Input.Key) i
                evt.modifiers = modifiers
                targetWnd.sendEvent(&evt)
            }
        }
    }

    mtd sendRuneEvent(key: Input.Key, r: rune)
    {
        var targetWnd = .keyboardFocusWnd
        targetWnd = skipDisabled(targetWnd)
        if !targetWnd do
            return

        var evt = KeyEvent{kind: .Character}
        evt.character = r
        evt.key       = key
        evt.modifiers = .keyboard.pressedModifiers()
        targetWnd.sendEvent(&evt)
    }

    mtd sendPostedEvents()
    {
        // Need to make a copy, in case the posted event triggers a modal for
        .mutexPostedEvents.lock()
        let copy = .postedEvents
        .postedEvents.clear()
        .mutexPostedEvents.unlock()

        var needUpdateState = false
        for it in copy
        {
            let evt = (it as Event)!

            if it is InvalidateEvent
            {
                let target = evt.target!
                target.invalidate()
            }
            else do
                .sendEvent(it)

            // Special event post process
            if it is CommandEvent do
                needUpdateState = true

            .toDelete.add({evt, evt.type!})
        }

        if needUpdateState do
            .updateCommandState()
    }

    mtd sendDestroyEvents()
    {
        if .inModalLoop do
            return
        for w in .postDestroy do
            .destroyWnd(w)
        .postDestroy.clear()
    }

    // Update UI state of all surfaces
    mtd updateCommandState()
    {
        for s in .surfaces do
            s.wnd.updateCommandState()
    }

    // Remove and destroy the given surface
    // To cleanly close a surface, you should call surface.destroy()
    mtd destroySurface(surface: *Surface)
    {
        .surfaces.remove(surface)
        if surface == .mainSurface do
            .postQuitEvent()

        if .modalSurfaces.count and surface == .modalSurfaces.back() do
            .endModal = true

        surface.destroyNative()
        .toDelete.add({surface, #typeof(surface[])})
    }

    mtd unregisterWnd(wnd: *Wnd)
    {
        .animator.cancelTarget(wnd)

        if wnd == .mouseEnterWnd or wnd.isOwnerOf(.mouseEnterWnd) do
            .mouseEnterWnd = null
        if wnd == .mouseCaptureWnd or wnd.isOwnerOf(.mouseCaptureWnd) do
            .mouseCaptureWnd = null
        if wnd == .keyboardFocusWnd or wnd.isOwnerOf(.keyboardFocusWnd) do
            .keyboardFocusWnd = null
        if wnd == .dragEnterWnd or wnd.isOwnerOf(.dragEnterWnd) do
            .dragEnterWnd = null

        .unregisterWndTimers(wnd)

        // Remove from various lists
        .frameEvents.remove(wnd)
        .hookOnEvent.remove(wnd)

        // A global shortcut must never retain a target after its window is destroyed.
        var hotKeyIndex = .hotKeys.count
        while hotKeyIndex
        {
            hotKeyIndex -= 1
            let shortcut = .hotKeys[hotKeyIndex]
            if shortcut.target == wnd
            {
                if !.hotKeysDisabled do
                    unregisterNativeHotKey(shortcut.modifiers, shortcut.key)
                .hotKeys.removeAtOrdered(hotKeyIndex)
            }
        }

        // Be sure there's no posted event for that window
        for e in .postedEvents
        {
            let ptr = (e as Event)!
            if ptr.target == wnd do
                ptr.target = null
        }
    }

    // Retires a window's timers before deferred destruction releases its storage.
    internal mtd unregisterWndTimers(wnd: *Wnd)
    {
        for t in .timers
        {
            if t.target == wnd and !t.isPendingRemoval
            {
                .timersToDelete.add(t)
                t.isPendingRemoval = true
            }
        }

        // A timer created by another timer callback is staged until the current dispatch ends.
        // Retire that one too when its target is destroyed by the same callback.
        for t in .timersToAdd
        {
            if t.target == wnd and !t.isPendingRemoval
            {
                .timersToDelete.add(t)
                t.isPendingRemoval = true
            }
        }
    }

    mtd sendTimerEvents()
    {
        .duringTimerEvents = true
        for t in .timers
        {
            if t.isPendingRemoval do
                continue

            if !t.stopwatch.isRunning() do
                t.stopwatch.start()

            if t.stopwatch.elapsedMilliseconds() >= t.periodMilliseconds
            {
                var evt = TimerEvent{}
                evt.timer = t
                t.target.sendEvent(&evt)
                t.stopwatch.restart()
            }
        }

        .duringTimerEvents = false

        // Add new registered timers
        for t in .timersToAdd do
            .timers.add(t)
        .timersToAdd.clear()

        // Remove some timers
        for t in .timersToDelete
        {
            t.isPendingRemoval = false
            .removeTimer(t)
        }

        .timersToDelete.clear()
    }

    mtd sendFrameEvents()
    {
        // What a window defers to the next frame is often a rebuild, and a rebuild destroys
        // windows — `destroyWnd` then takes them out of this very list. So the walk re-reads the
        // count and the element at each step instead of holding an iterator over it, and only
        // advances when the element it just handed the event to is still where it was.
        var index = 0'u64
        while index < .frameEvents.count
        {
            let target = .frameEvents[index]

            var evt = FrameEvent{}
            target.sendEvent(&evt)

            if index < .frameEvents.count and .frameEvents[index] == target do
                index += 1
        }
    }

    mtd deletePointers()
    {
        if .inModalLoop do
            return
        for p in .toDelete do
            Memory.delete(p.ptr, p.type)
        .toDelete.clear()
    }

    // Repaints every surface that has something to repaint, and does nothing else.
    //
    // This is what a modal loop belonging to someone else calls to keep the application drawing:
    // the desktop's own drag loop is the case that exists, and it runs for as long as the gesture
    // does. Nothing else of [[runFrame]] is safe from inside such a loop, since the owner is
    // already dispatching input and a window destroyed there would be the ground the loop stands
    // on.
    internal mtd paintSurfaces()
    {
        for s in .surfaces do
            s.paint()
    }

    // Processes one complete input, event, paint, and frame-callback cycle.
    public mtd runFrame()
    {
        .timing.update()
        Memory.releaseTemporaryAllocations()

        .animator.advance(.timing.deltaSeconds)
        .toolTip.update(.deltaSeconds())
        .sendFrameEvents()
        .sendTimerEvents()
        .sendSystemEvents()
        .sendKeyboardEvents()
        .sendMouseEvents()
        .sendPostedEvents()
        .sendDestroyEvents()
        .paintSurfaces()
        .deletePointers()

        .sigFrame.call(me)

        if .maxRunFrame and .timing.frameCount >= .maxRunFrame
        {
            .mustQuit = true
            .quitCode = 0
        }
    }

    // Runs a nested event loop for `surface` and returns the identifier passed to [[exitModal]].
    //
    // Other enabled surfaces are disabled for the duration of the loop and restored to their
    // previous state afterwards. The modal surface is destroyed when the loop ends.
    //
    // `restoreTo` is the surface the keyboard belongs to once the box is gone — the one that
    // raised it. It is asked for its own focus rather than being handed a position captured here,
    // because a box that opens ready for the keyboard has already moved it onto itself by the
    // time this runs: what was read here was a rank inside the box, applied to the ring of the
    // form underneath it. See `Surface.focusWnd`.
    public mtd doModalLoop(surface: #null *Surface, cb: #null func||(*Application) = null, restoreTo: #null *Surface = null)->WndId
    {
        .endModal     = false
        .endModalExit = null
        .inModalLoop  += 1
        defer .inModalLoop -= 1

        var disabledSurfaces: Array'(*Surface)
        for s in .surfaces
        {
            if s != surface and !s.isDisabled
            {
                s.disable()
                disabledSurfaces.add(s)
            }
        }

        if surface
        {
            let modalSurface = surface
            modalSurface.enable()
            .modalSurfaces.add(modalSurface)
        }

        while !.mustQuit and !.endModal
        {
            .runFrame()
            if cb do
                cb(me)
        }

        if surface do
            .modalSurfaces.removeBack()

        // A surface disabled on the way in can be destroyed while the loop runs: it has left
        // `surfaces`, but this list still holds the raw pointer, and enabling or focusing it
        // would touch freed windows. Keep only the survivors.
        var index = disabledSurfaces.count
        while index
        {
            index -= 1
            if !.surfaces.contains(disabledSurfaces[index]) do
                disabledSurfaces.removeAtOrdered(index)
        }

        for s in disabledSurfaces do
            s.enable()

        // The keyboard is given back only when the box took it: a loop run without a surface of
        // its own — a captured pop-up, a colour picker — never moved it, and moving it now would
        // be the box choosing for a form that was never left.
        let focus       = .keyboardFocusWnd
        var mustRestore = !focus
        if focus and surface and focus.surface == surface do
            mustRestore = true

        // A box opened over another box gives the keyboard back to that one; otherwise it goes to
        // the surface that raised it. The last surface re-enabled is only a last resort: it is the
        // end of the application's list, which is not necessarily where the reader was.
        var restoreSurface: #null *Surface
        if .modalSurfaces.count do
            restoreSurface = .modalSurfaces.back()
        elif restoreTo and restoreTo != surface do
            restoreSurface = restoreTo
        elif disabledSurfaces.count do
            restoreSurface = disabledSurfaces.back()

        if mustRestore and restoreSurface do
            discard restoreSurface.restoreFocus()

        if surface do
            surface.destroy()

        let result = .endModalExit orelse ""
        .endModal     = false
        .endModalExit = null
        return result
    }
}

internal impl Application
{
    mtd dispatchHotKey(modifiers: Input.KeyModifiers, key: Input.Key)
    {
        let {id, target} = .hotKeyShortcut(modifiers, key)
        if id and target do
            target.sendCommandEvent(id)
    }

    // Finds the visible surface at a screen position.
    mtd surfaceAt(x, y: f32)->#null *Surface
    {
        if .renderer.needsNativeWindow() do
            return .surfaceAtNative(x, y)

        for surface in .surfaces
        {
            if surface.isHidden do
                continue
            if .modalSurfaces.count and surface != .modalSurfaces.back() do
                continue
            if surface.position.contains(Math.Point{x, y}) do
                return surface
        }

        return null
    }
}

impl Application
{
    // Releases resources owned by this value.
    mtd opDrop()
    {
        .animator.cancelAll()
        .setGlobalHotKeysEnabled(false)

        for it in .surfaces do
            it.destroy()
        .sendDestroyEvents()

        for it in .postedEvents
        {
            let ptr = (it as Event)!
            .toDelete.add({ptr, ptr.type!})
        }

        .deletePointers()
        if .appIconLoaded
        {
            if .appIconList.isValid() do
                .appIconList.release(.renderer)
            if .appIconTileList.isValid() do
                .appIconTileList.release(.renderer)
        }

        if @isset(.theme) do
            .theme.freeDefault()
    }

    // Turns the keyboard-focus ring on or off, and repaints what showed it.
    //
    // Keyboard traversal turns it on, a pointer press turns it off. See
    // [[Gui.Application.focusVisible]].
    internal mtd setFocusVisible(visible: bool)
    {
        if .focusVisible == visible do
            return
        .focusVisible = visible
        .keyboardFocusWnd?.invalidate()
    }

    // Routes a pressed key that the focused window and its parents all declined.
    //
    // Explicit intent comes first: a shortcut registered anywhere on the routing chain outranks
    // every default. What is left goes to the keyboard navigation of the surface, which is why a
    // widget wanting Tab, Enter, or Escape for itself only has to accept the event —
    // [[Gui.RichEditCtrl]] keeps its tabulation and the property grid keeps its row-to-row Tab
    // without either of them knowing that a traversal exists.
    internal mtd routeUnhandledKey(from: *Wnd, key: Input.Key, modifiers: Input.KeyModifiers)
    {
        let id = from.keyShortcut(modifiers, key)
        if id != null
        {
            from.sendCommandEvent(id)
            return
        }

        let surface = from.surface
        if surface do
            discard surface.navigateKey(from, key, modifiers)
    }

    // Frequently queried application services and per-frame input state.
    #[Swag.Inline]
    {
        // Returns a mutable borrow of the keyboard state.
        mtd keyboardRef() => &.keyboard

        // Returns a mutable borrow of the mouse state.
        mtd mouseRef() => &.mouse

        // Returns the duration of the current frame, in seconds.
        mtd const deltaSeconds() => .timing.deltaSeconds
    }

    // Selects the renderer borrowed by every painter and surface of this application.
    //
    // Call this before [[Gui.Application.createSurface]]. The concrete renderer must outlive the
    // application. When omitted, the first surface selects [[Pixel.RenderOgl]].
    mtd setRenderer(renderer: Pixel.IRenderer)
    {
        Debug.assert(!.mainSurface, "renderer must be selected before creating a surface")
        .renderer = renderer
    }

    internal mtd clearWndInputState(wnd: *Wnd)
    {
        if wnd == .mouseEnterWnd or wnd.isOwnerOf(.mouseEnterWnd) do
            .mouseEnterWnd = null
        if wnd == .mouseCaptureWnd or wnd.isOwnerOf(.mouseCaptureWnd) do
            .mouseCaptureWnd = null
        if wnd == .keyboardFocusWnd or wnd.isOwnerOf(.keyboardFocusWnd) do
            .keyboardFocusWnd = null
        if wnd == .dragEnterWnd or wnd.isOwnerOf(.dragEnterWnd) do
            .dragEnterWnd = null
    }

    // Kept for callers that still bound their own run; a smoke run already bounds itself.
    #[Swag.Deprecated("a smoke run sets the frame budget itself")]
    mtd applyTestArgs(testFrames: u32 = 50)
    {
        discard testFrames
    }

    // Creates a main surface and runs its application until shutdown.
    //
    // A smoke run stops on its own after the frame budget its launcher set, so an example
    // written with this needs nothing special to be exercised by the test suite.
    func runSurface(x, y, width, height: s32, title: #null string = null, view: #null *Wnd = null, borders = true, canSize = true, hook: #null HookEvent = null, init: #null func(*Application) = null, testFrames: u32 = 50)
    {
        var app: Application

        var flags = SurfaceFlags.StandardWindow
        if !canSize do
            flags &= ~.Resizable
        if !borders do
            flags &= ~.Border
        let surface = (expect app.createSurface(x, y, width, height, flags, view, hook))!
        surface.setTitle(title)
        if init do
            init(&app)
        discard testFrames
        surface.show()
        app.run()
    }

    // Creates an initially hidden top-level surface.
    //
    // The first surface initializes the shared renderer and theme and becomes [[mainSurface]].
    // `width` and `height` are logical units: on a scaled display the native window is
    // created proportionally larger, in physical pixels. `x` and `y` are physical
    // desktop pixels.
    mtd createSurface(x, y, width, height: s32, flags = SurfaceFlags.StandardWindow, view: #null *Wnd = null, hook: #null HookEvent = null, surfaceId: #null string = null)->#null *Surface fail
    {
        let surface = Memory.new'Surface()
        var surfaceCreated: bool
        defer if !surfaceCreated
        {
            surface.destroyNative()
            Memory.delete(surface.wnd)
            Memory.delete(surface)
        }

        surface.app       = me
        surface.position  = {x, y, width, height}
        surface.surfaceId = surfaceId

        if !.mainSurface
        {
            .refreshSystemMotionPreference()
            if !@isset(.renderer) do
                .setRenderer(&.rendererOgl)
            if !@isset(.theme) do
                .theme = Memory.new'Theme()
            .style.set(.theme)
            registerDefaultThemeResources(&.resources)
            registerDefaultStrings(&.resources)
        }

        try Surface.create(surface, x, y, width, height, flags, .mainSurface)
        surfaceCreated = true

        if !.mainSurface
        {
            .renderer.setCurrentContext(surface.rc)
            .renderer.init()

            // Spin up the shared worker pool before anything rasterizes. The theme setup
            // right below is the heaviest CPU work of a startup and its rasterizers band
            // themselves across the pool; starting the pool after it would leave that one
            // step, the only one that matters, running on a single thread.
            if Jobs.isSynchronous() do
                discard catch Jobs.initialize()

            .theme.setupDefault(.renderer, &.resources, surface.dpiScale)
            .mainSurface = surface
        }

        // A surface on a scaled display needs the theme atlas at least at its density.
        .theme.ensureAtlasScale(.renderer, surface.dpiScale)

        // The first surface initializes the theme only just above, so the caption and
        // border paddings computed during Surface.create were still zero. Apply them
        // again now: the view created below must see its final client rectangle in its
        // create event, because callers legitimately lay out their content there.
        surface.applySurfaceFlags()

        .surfaces.add(surface)

        with surface
        {
            .wnd.create(view, hook)
            .wnd.surface = surface
            .wnd.itf     = surface.wnd
            .wnd.computeStyle()
            .wnd.view.computeStyle()
            .wnd.sendResizeEvent()
        }

        return surface
    }

    // Selects the file used to persist surface placement with [[saveState]] and [[loadState]].
    mtd setStatePath(path: string)
    {
        .statePath = path
    }

    // Selects the application icon before the first surface is created.
    //
    // The image becomes the native window icon — taskbar, task switcher, native caption —
    // and the mark a drawn caption shows beside its title. A surface that wants another one
    // there overrides it with [[Gui.Surface.setIcon]].
    mtd setAppIcon(img: Pixel.Image)
    {
        .appIcon       = img
        .appIconLoaded = false
    }

    // Returns the application mark at `size` logical pixels, cut to sit on `ground`, or an
    // invalid icon when the application declares none.
    //
    // The mark ships flattened — one glyph over one ink tile — because that is what a taskbar,
    // a file list and an installer need. A drawn caption has a ground of its own, so on a dark
    // band the tile is keyed out and the glyph floats free, where the tile would have read as a
    // black square around it.
    //
    // On a light band it cannot be, and this is the whole reason `ground` is asked for: the
    // glyph is Voltage, and Voltage on paper is a mark nobody sees. The tile stays there, and
    // the window carries the identity the way the chart says a light surface has to — as a block
    // of brand rather than as a hairline of it. Below the threshold a keyed-out mark simply
    // disappeared from the title bar of every application in the light theme.
    //
    // Both cuts are uploaded once, on the first call, so this can be asked for from inside a
    // paint without costing anything after the first frame.
    mtd appIconAt(size: f32, ground: Pixel.Color)->Icon
    {
        var result: retval
        if !.appIcon.isValid() do
            return result

        if !.appIconLoaded
        {
            // The two colors are the ones the chart declares for every product mark, so the
            // derivation follows the same rule as the art.
            var mark = .appIcon.convertedTo(.RGBA8)
            .appIconTileList.set(.renderer.addImage(mark))

            mark.keyOutGround(MarkInk, MarkVoltage)
            .appIconList.set(.renderer.addImage(mark))
            .appIconLoaded = true
        }

        let list = markReadsOn(ground) ? &.appIconList : &.appIconTileList
        if !list.isValid() do
            return result

        result = Icon.from(list, 0, size, size)

        // The mark carries its own two colors; drawn through the caption tint it would
        // collapse to one. An explicit white leaves the raster alone.
        result.color = Pixel.Argb.White
        return result
    }

    // Applies the theme sheet resource `themes/<name>.tweak` and refreshes every surface.
    //
    // The sheet is resolved through [[resources]], so it can come from a disk folder or
    // from embedded bytes. Values not named by the sheet keep the current theme, which
    // makes a sheet a delta over whatever palette is already applied.
    mtd loadTheme(name: string) fail
    {
        Debug.assert(@isset(.theme), "the theme exists once the first surface is created")

        var resName: String = "themes/"
        resName += name
        resName += ".tweak"
        try .theme.loadSheet(&.resources, resName.toString())
        .notifyThemeChanged()
    }

    // Applies the language `tag` to every registered string table and refreshes every surface.
    //
    // [[Gui.ReferenceLanguage]] restores the built-in reference strings. Any other tag
    // resets the tables to their reference values, then applies the
    // `lang/<tag>/<file>.tweak` resource of each registered table; a table without a file
    // for that tag keeps its reference strings. Fails when the tag is not registered
    // through [[Gui.registerLanguage]] or has no language file for any registered table,
    // so a mistyped tag cannot silently present itself as applied. Menus and
    // command-driven controls pick the new strings up on their next update; text set once
    // at construction keeps its wording until the window is created again, so a window
    // that must follow the switch listens for the
    // [[Gui.NotifyEvent.Kind.LanguageChanged]] notification.
    mtd setLanguage(tag: string) fail
    {
        try applyLanguage(&.resources, tag)
        .notifyLanguageChanged()
    }

    // Applies the registered language that best matches the language of the user account.
    //
    // [[Gui.systemLanguage]] falls back to [[Gui.ReferenceLanguage]], so this only fails
    // on an installation whose language resources are missing.
    mtd setSystemLanguage() fail
    {
        try .setLanguage(systemLanguage())
    }

    // Returns the active language tag, `"en"` by default.
    func language()->string => activeLanguage()

    // Overrides or restores the platform reduced-motion preference.
    mtd setMotionPreference(preference: MotionPreference)
    {
        let wasReduced = .isReducedMotion()
        .motionPreference = preference
        if !wasReduced and .isReducedMotion() do
            .animator.finishDecorative()
    }

    // Reports whether decorative finite transitions complete immediately.
    mtd const isReducedMotion()->bool
    {
        switch #complete .motionPreference
        {
        case .System:  return .systemReducedMotion
        case .Full:    return false
        case .Reduced: return true
        }
    }

    // Emits a language-change notification throughout every surface tree.
    //
    // Rebuilding its own content is the supported answer to this notification — a panel
    // generated from reflection has no other way to change language — so the walk is written
    // to survive a handler that restructures the tree under it: children are taken as a
    // snapshot, and a window that left the tree meanwhile is skipped rather than sent to.
    private mtd notifyLanguageChanged()
    {
        func updateLanguage(wnd: *Wnd)
        {
            if !wnd.surface do
                return

            wnd.invalidate()

            var children: Array'(*Wnd)
            children.add(wnd.children.toSlice())
            for c in children do
                updateLanguage(c)

            if !wnd.surface do
                return

            var evt = NotifyEvent{}
            evt.accepted = false
            evt.kind     = .LanguageChanged
            wnd.sendEvent(&evt)
        }

        for s in .surfaces do
            updateLanguage(s.wnd)
    }

    // Recomputes styles and emits a theme-change notification throughout every surface tree.
    mtd notifyThemeChanged()
    {
        func updateTheme(wnd: *Wnd)
        {
            wnd.style.dirty = true
            wnd.computeStyle()
            wnd.invalidate()
            for c in wnd.children do
                updateTheme(c)

            var evt = NotifyEvent{}
            evt.accepted = false
            evt.kind     = .ThemeChanged
            wnd.sendEvent(&evt)
        }

        .dirtyTheme += 1
        for s in .surfaces
        {
            s.applyNativeSurfaceFlags()
            s.wnd.updateTheme()
        }
    }

    private mtd serializeState(ser: *Serializer) fail
    {
        ser.beginSection(.Unordered)
        for s in .surfaces do
            s.serializeState(ser)
        ser.endSection()
    }

    private func stateId(text: string)->Guid128
    {
        var result: Guid128
        let valid = Guid128.tryParse(text, &result)
        Debug.assert(valid)
        return result
    }

    private func stateContainerKind()->Guid128 => stateId("89c98d18-11dc-42a0-910c-4bb64b3e2776")
    private func stateChunkType()->Guid128     => stateId("cbb8ce58-7baa-4381-aa22-3b95365a8ba2")
    private func stateChunkRole()->Guid128     => stateId("a37d3af6-2ba5-4bc4-b796-48878fd09fe4")

    // Saves serializable surface placement to the configured state file.
    mtd saveState() fail
    {
        if .statePath.isEmpty() do
            return

        var buf:  ConcatBuffer
        var save: Encoder'Write.TagBin
        var ser:  Serializer
        ser.startWrite(&save, &buf)
        .serializeState(&ser)
        ser.end()

        buf.makeLinear()
        var manifest: Scc.Manifest
        manifest.name       = String.from(Path.fileName(.statePath) orelse "")
        manifest.modifiedAt = Time.DateTime.now()

        var writer: Scc.Writer
        writer.initialize(stateContainerKind())
        writer.manifest()[] = #move manifest
        let chunkType = stateChunkType()
        let chunkRole = stateChunkRole()
        let stateId   = try writer.addChunk(buf.toSlice()!, {typeId: chunkType, roleId: chunkRole, flags: .Required | .Metadata})

        var entry: Scc.Entry
        entry.id           = Guid128.random()
        entry.kind         = .File
        entry.name         = "state"
        entry.primaryChunk = stateId
        writer.manifest().entries.add(#move entry)
        writer.saveAtomic(.statePath)
    }

    // Loads serializable surface placement from the configured state file.
    mtd loadState() fail
    {
        if .statePath.isEmpty() do
            return

        var buf: Array'u8
        if try Scc.hasSignature(.statePath)
        {
            var reader: Scc.Reader
            reader.initialize(.statePath)
            if reader.kind() != stateContainerKind() do
                fail Errors.InvalidFormatError{"GUI state file has a different SCC profile"}
            let state = reader.findRole(stateChunkRole())
            if !state do
                fail Errors.InvalidFormatError{"GUI state file has no state chunk"}
            buf = try reader.readChunk(state.id)
        }
        else do
            buf = try File.readAllBytes(.statePath)

        var load: Decoder'Read.TagBin
        var ser:  Serializer
        ser.startRead(&load, buf.toSlice())
        .serializeState(&ser)
        ser.end()
    }

    // Returns the window currently holding mouse capture.
    mtd const mouseCapture()->#null *Wnd
    {
        return .mouseCaptureWnd
    }

    // Sets the captured window without asking the platform for a real capture.
    //
    // 'captureMouse' is the way a window takes the mouse; this one exists for the headless
    // host and its tests, which simulate the platform side themselves.
    internal mtd setMouseCaptureRaw(wnd: #null *Wnd)
    {
        .mouseCaptureWnd = wnd
    }

    // Destroy a window
    // To cleanly close a window, you should call wnd.destroy()
    internal mtd destroyWnd(wnd: *Wnd)
    {
        var evt = DestroyEvent{}
        wnd.sendEvent(&evt)

        .unregisterWnd(wnd)

        // Remove from parent
        if wnd.parent and !wnd.parent.isPendingDestroy
        {
            let oldParent = wnd.parent!
            let detached  = oldParent.detachChild(wnd)
            Debug.assert(detached)
            oldParent.invalidate()
        }

        if wnd.isAllocated
        {
            .toDelete.add({wnd, wnd.type!})
        }
    }

    internal mtd windowAtMouse()->#null *Wnd => .windowAt(.mouse.position())

    // Returns the deepest window under a physical screen position, or `null` when none is there.
    //
    // Which surface the position falls on is asked of the desktop, so this is for a caller that
    // has only a position — the pointer. A caller that already knows the surface asks it
    // directly through [[Gui.Surface.windowAt]]: the desktop's answer is about whatever window
    // happens to be topmost there, which during a drag is the shell's own drag image.
    internal mtd windowAt(screenPos: Math.Point)->#null *Wnd
    {
        let targetSurface = .surfaceAt(screenPos.x, screenPos.y)
        if !targetSurface do
            return null
        return targetSurface.windowAt(screenPos)
    }

    // Returns `wnd` or its closest enabled ancestor, or `null` when nothing there takes input.
    internal func skipDisabled(wnd: #null *Wnd)->#null *Wnd
    {
        if !wnd do
            return null
        if wnd.surface!.isDisabled do
            return null
        var scan = wnd
        while scan
        {
            let cur = scan
            if cur.isEnabled() do
                break
            scan = cur.parent
        }

        return scan
    }

    // Set activated state
    internal mtd setActivated(activated: bool)
    {
        if .isActivated == activated do
            return
        .isActivated = activated
        for s in .modalSurfaces do
            s.bringToFront()
        .invalidate()
    }

    // Schedules every surface for a complete repaint.
    mtd invalidate()
    {
        for s in .surfaces do
            s.invalidate()
    }

    // Posts a thread-safe request to leave the event loop with `quitCode`.
    mtd postQuitEvent(quitCode: s32 = 0)
    {
        let evt = Event.create'QuitEvent()
        evt.quitCode = quitCode
        .postEvent(evt)
    }

    // Queues an event from any thread for delivery during the next frame.
    mtd postEvent(event: IEvent)
    {
        Sync.scopedLock(&.mutexPostedEvents)
        .postedEvents.add(event)
    }

    // Delivers an event synchronously through the GUI routing chain.
    mtd sendEvent(event: IEvent)
    {
        .sendEventPrivate(event, null)
    }

    // Creates a repeating timer that sends [[TimerEvent]] values to `target`.
    mtd addTimer(time: Time.Duration, target: *Wnd)->*Timer
    {
        let timer = Memory.new'Timer()
        Debug.assert(time.milliseconds() > 0, "timer period must be positive")
        timer.periodMilliseconds = time.milliseconds()
        timer.target             = target
        if .duringTimerEvents do
            .timersToAdd.add(timer)
        else do
            .timers.add(timer)
        return timer
    }

    // Removes and destroys a timer created by `addTimer`.
    //
    // Scheduling a target window for destruction retires its timers, so a window that still names
    // one from its own cleanup lands here on a timer this application no longer owns. The registry
    // is what answers that: once a retirement has been flushed the timer is released, and reading
    // its own fields to recognize the duplicate request would read freed memory.
    mtd removeTimer(timer: *Timer)
    {
        if !.ownsTimer(timer) do
            return

        // Retirement is already queued for the end of the current dispatch.
        if timer.isPendingRemoval do
            return

        if .duringTimerEvents
        {
            timer.isPendingRemoval = true
            .timersToDelete.add(timer)
        }
        else
        {
            Memory.delete(timer)
            .timers.remove(timer)
        }
    }

    // Reports whether this application still owns `timer`, without reading through it.
    internal mtd const ownsTimer(timer: const *Timer)->bool
    {
        for t in .timers where t == timer do
            return true
        for t in .timersToAdd where t == timer do
            return true
        return false
    }

    // Asks for [[Gui.IWnd.onFrameEvent]] on `target` at the start of every rendered frame.
    //
    // A surface view is sent one `FrameEvent` before the loop starts, carrying `firstFrame`; that
    // is a startup hook. This is the per-frame half, and it is how a window defers work to the
    // next frame — a rebuild asked for from inside a change notification, where rebuilding on the
    // spot would destroy the control that is reporting.
    //
    // Registration was `internal` and had no caller, so `sendFrameEvents` walked an empty array
    // for the whole run and every deferral written against it silently never happened.
    //
    // Register once and unregister before the window goes; `Application.destroyWnd` also
    // drops a destroyed window from the list, so a normal teardown needs nothing.
    mtd registerFrameEvent(target: *Wnd)
    {
        Debug.assert(!.frameEvents.contains(target))
        .frameEvents.add(target)
    }

    // Stops sending `target` the per-frame event. Sending it one it no longer wants is harmless.
    mtd unregisterFrameEvent(target: *Wnd)
    {
        .frameEvents.remove(target)
    }

    internal mtd registerHookEvents(target: *Wnd)
    {
        Debug.assert(!.hookOnEvent.contains(target))
        .hookOnEvent.add(target)
    }

    internal mtd unregisterHookEvents(target: *Wnd)
    {
        .hookOnEvent.remove(target)
    }

    // Selects the cursor for the current frame; the next frame restores automatic selection.
    mtd setFrameCursor(cursor: Cursor)
    {
        .frameCursor = cursor
    }

    // Processes frames until a quit event is received and returns its exit code.
    #[Swag.Discardable]
    mtd run()->s32
    {
        // A smoke run is bounded by whoever launched it. Applying it here means no
        // application, example or script has to recognize that it is being exercised.
        if !.maxRunFrame do
            .maxRunFrame = Env.smokeFrames()

        for s in .surfaces
        {
            var evt = FrameEvent{}
            evt.firstFrame = true
            s.wnd.view.sendEvent(&evt)
        }

        while !.mustQuit do
            .runFrame()

        return .quitCode
    }

    // Ends the innermost modal loop with `exitId` as its result.
    mtd exitModal(exitId: string = "")
    {
        .endModal     = true
        .endModalExit = exitId
    }

    // Returns the native shell icon for a file name or extension.
    mtd fileIcon(name: string, small = true)->Icon => .fileOrDirectoryIcon(name, false, small)

    // Returns the native shell icon for a directory.
    mtd directoryIcon(name: string, small = true)->Icon => .fileOrDirectoryIcon(name, true, small)

    // Enables or disables all shortcuts registered with [[registerHotKey]].
    mtd setGlobalHotKeysEnabled(enabled = true)
    {
        if .hotKeysDisabled == !enabled do
            return

        .hotKeysDisabled = !enabled
        for shortcut in .hotKeys
        {
            if enabled do
                catch registerNativeHotKey(shortcut.modifiers, shortcut.key)
                else do
                    unregisterNativeHotKey(shortcut.modifiers, shortcut.key)
        }
    }

    // Registers or replaces a system-wide keyboard shortcut routed to `target` as `wndId`.
    mtd registerHotKey(modifiers: Input.KeyModifiers, key: Input.Key, wndId: WndId, target: *Wnd) fail
    {
        for &c in .hotKeys
        {
            if c.modifiers == modifiers and c.key == key
            {
                c.id     = wndId
                c.target = target
                return
            }
        }

        .hotKeys.add({modifiers, key, wndId, target})
        if !.hotKeysDisabled do
            try registerNativeHotKey(modifiers, key)
    }

    // Unregisters a system-wide keyboard shortcut and returns whether it existed.
    mtd unregisterHotKey(modifiers: Input.KeyModifiers, key: Input.Key)->bool
    {
        for shortcut, idx in .hotKeys
        {
            if shortcut.modifiers == modifiers and shortcut.key == key
            {
                if !.hotKeysDisabled do
                    unregisterNativeHotKey(modifiers, key)
                .hotKeys.removeAtOrdered(idx)
                return true
            }
        }

        return false
    }

    // Unregisters every system-wide keyboard shortcut owned by this application.
    mtd unregisterAllHotKeys()
    {
        if !.hotKeysDisabled
        {
            for shortcut in .hotKeys do
                unregisterNativeHotKey(shortcut.modifiers, shortcut.key)
        }

        .hotKeys.clear()
    }

    internal mtd hotKeyShortcut(modifiers: Input.KeyModifiers, key: Input.Key)->{ id: #null WndId, wnd: #null *Wnd }
    {
        for c in .hotKeys
        {
            if c.modifiers == modifiers and c.key == key do
                return {c.id, c.target}
        }

        return {null, null}
    }

    internal mtd hotKeyShortcutName(wndId: WndId)->String
    {
        var result: retval
        for c in .hotKeys
        {
            if c.id == wndId
            {
                result = Input.formatKeyShortcut(c.modifiers, c.key)
                return result
            }
        }

        return result
    }
}
