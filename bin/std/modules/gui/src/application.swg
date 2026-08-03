#global public

using Core, Serialization

// Callback invoked with the application that is processing a frame.
alias FrameCallback = func||(*Application)

// Owns GUI resources, top-level surfaces, input state, and the event loop.
struct Application
{
    using native: ApplicationNative                 // Platform-specific application state.
    sigFrame:     SigArray'func||(*Application)     // Emitted after each processed frame.

    options: ApplicationOptions     // Diagnostics and development options.
    appIcon: Pixel.Image            // Icon used for native windows created by the application.
    readonly
    {
        #[Swag.Late]
        renderer: Pixel.IRenderer     // Renderer selected before the first surface is created.
    }

    internal
    rendererOgl: Pixel.RenderOgl     // Default OpenGL renderer used when none is selected.
    #[Swag.Late]
    theme:       *Theme             // Active application theme.
    style:       ThemeStyle         // Root style inherited by surface window trees.
    keyboard:    Input.Keyboard     // Keyboard state for the current and previous frames.
    mouse:       Input.Mouse        // Mouse state for the current and previous frames.
    mainSurface: #null *Surface     // First surface, whose destruction requests application shutdown.

    // The surface list is maintained by the application: create and destroy surfaces through
    // its own API so the modal stack and the render loop stay consistent.
    readonly
    surfaces: Array'(*Surface)

    // Frame and input bookkeeping. Reading it tells what the application is doing this frame;
    // writing it from outside would desynchronize the loop from the window tree.
    readonly
    {
        timing:      Time.FrameTiming     // Timing of the frame being run.
        isActivated: bool                 // Whether the application owns the active native window.
    }

    // Focus tracking, moved by the windows themselves as events are dispatched.
    internal
    {
        keyboardFocusWnd: #null *Wnd     // Window currently holding the keyboard focus.
        mouseCaptureWnd:  #null *Wnd     // Window currently holding the mouse capture.
        mouseEnterWnd:    #null *Wnd     // Window the mouse last entered.
    }

    frameCursor: Cursor            // Cursor selected for the current frame.
    fadeDisabledSurface = true     // Whether modal-disabled surfaces fade toward the disabled theme color.

    // Run-loop state. It only means something to the loop that owns it.
    internal
    {
        postedEvents:      Array'(IEvent)                                             // Events queued from any thread, drained each frame.
        postDestroy:       Array'(*Wnd)                                               // Windows to destroy once the frame is over.
        hookOnEvent:       Array'(*Wnd)                                               // Windows watching every event of the application.
        endModalExit:      #null WndId                                                // Result the innermost modal loop exits with.
        inModalLoop:       u32                                                        // Depth of the modal loop nesting.
        quitCode:          s32                                                        // Exit code the run loop returns.
        mustQuit:          bool                                                       // Whether the run loop stops at the end of the frame.
        endModal:          bool                                                       // Whether the innermost modal loop stops.
        mutexPostedEvents: Sync.Mutex                                                 // Guards 'postedEvents' against other threads.
        duringTimerEvents: bool                                                       // Whether timer callbacks are running, so lists defer.
        timers:            Array'(*Timer)                                             // Active timers.
        timersToAdd:       Array'(*Timer)                                             // Timers added while callbacks were running.
        timersToDelete:    Array'(*Timer)                                             // Timers removed while callbacks were running.
        frameEvents:       Array'(*Wnd)                                               // Windows asking for a per-frame event.
        modalSurfaces:     Array'(*Surface)                                           // Surface stack of the nested modal loops.
        toDelete:          Array'{ ptr: #null *void, type: const *Swag.TypeInfo }     // Deferred deletions.
    }

    // Stops the run loop after this many frames, or never when zero. A test or a scripted
    // run sets it to bound the loop without a user closing the window.
    maxRunFrame: u32
    internal
    {
        statePath: String                // File used by [[saveState]] and [[loadState]].
        hotKeys:   Array'KeyShortcut     // Registered system-wide keyboard shortcuts.
    }

    readonly
    dirtyTheme: u32     // Revision incremented after each theme change.
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
        var scan = event.target.ownerOrParent()
        while scan
        {
            if scan.hookOnChildEvent and scan.hookOnChildEvent(scan, evt) do
                return
            scan = scan.ownerOrParent()
        }

        // Send event to the target
        // If the target does not accept the event, then pass it to the parent
        event.accepted = true
        event.target.processEvent(evt)
        while !event.accepted
        {
            let target = notnull event.target
            event.target = target.owner orelse target.parent
            if !event.target or event.target == stopAt do
                break
            event.accepted = true
            event.target.processEvent(evt)
        }
    }

    func skipDisabled(wnd: #null *Wnd)->#null *Wnd
    {
        if !wnd do
            return null
        if (notnull wnd.surface).isDisabled do
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

    mtd sendMouseEvents()
    {
        .mouse.update()

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
                    ToolTip.show(targetWnd, evt.surfacePos, targetWnd.toolTip)
            }

            // Leave
            if .mouseEnterWnd and targetWnd != .mouseEnterWnd
            {
                evt.kind       = .Leave
                evt.surfacePos = .mouseEnterWnd.screenToSurface(mousePos)
                evt.target     = .mouseEnterWnd
                .sendEventPrivate(&evt, .mouseCaptureWnd)

                ToolTip.hide(.mouseEnterWnd)
            }

            .mouseEnterWnd = targetWnd
        }

        evt.modifiers = .keyboard.pressedModifiers()

        // Move
        if targetWnd
        {
            let move = .mouse.movement()
            evt.surfacePos = targetWnd.screenToSurface(mousePos)
            evt.kind       = .Move
            evt.delta      = move
            targetWnd.sendEvent(&evt)
            if Math.abs(move.x) >= 0.5 or Math.abs(move.y) >= 0.5 do
                ToolTip.resetTimer(evt.surfacePos)
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
        for [i] in @countof(.mouse.previousState.pressed)
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
                    if targetWnd.focusStrategy == .OnMousePress do
                        targetWnd.setFocus()
                }

                evt.button = cast(Input.MouseButton) i
                targetWnd.sendEvent(&evt)
                ToolTip.hide()
            }
            elif lastP and !curP
            {
                evt.kind   = .Released
                evt.button = cast(Input.MouseButton) i
                targetWnd.sendEvent(&evt)
            }
        }
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

        var targetWnd = .keyboardFocusWnd
        targetWnd = skipDisabled(targetWnd)
        if !targetWnd do
            return

        // Modifiers
        let modifiers = .keyboard.pressedModifiers()

        // Detect changes
        for [i] in @countof(.keyboard.previousState.pressed)
        {
            let lastP = .keyboard.previousState.pressed[i]
            let curP  = .keyboard.currentState.pressed[i]
            if !lastP and curP
            {
                var evt = KeyEvent{kind: .Pressed}
                evt.key       = cast(Input.Key) i
                evt.modifiers = modifiers
                targetWnd.sendEvent(&evt)

                // Convert key to command (shortcuts)
                if !evt.accepted
                {
                    let id = targetWnd.keyShortcut(modifiers, cast(Input.Key) i)
                    if id != null do
                        targetWnd.sendCommandEvent(id)
                }
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
            let evt = notnull (it as Event)

            if it is InvalidateEvent
            {
                let target = notnull evt.target
                target.invalidate()
            }
            else do
                .sendEvent(it)

            // Special event post process
            if it is CommandEvent do
                needUpdateState = true

            .toDelete.add({evt, notnull evt.type})
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
        .toDelete.add({surface, #typeof(dref surface)})
    }

    mtd unregisterWnd(wnd: *Wnd)
    {
        if wnd == .mouseEnterWnd or wnd.isOwnerOf(.mouseEnterWnd) do
            .mouseEnterWnd = null
        if wnd == .mouseCaptureWnd or wnd.isOwnerOf(.mouseCaptureWnd) do
            .mouseCaptureWnd = null
        if wnd == .keyboardFocusWnd or wnd.isOwnerOf(.keyboardFocusWnd) do
            .keyboardFocusWnd = null

        // Be sure there's no timer for that window
        for t in .timers
        {
            if t.target == wnd and !t.isPendingRemoval
            {
                .timersToDelete.add(t)
                t.isPendingRemoval = true
            }
        }

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
            let ptr = notnull (e as Event)
            if ptr.target == wnd do
                ptr.target = null
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
        for t in .frameEvents
        {
            var evt = FrameEvent{}
            t.sendEvent(&evt)
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

    // Processes one complete input, event, paint, and frame-callback cycle.
    public mtd runFrame()
    {
        .timing.update()
        Memory.releaseTemporaryAllocations()

        ToolTip.update(.deltaSeconds())
        .sendFrameEvents()
        .sendTimerEvents()
        .sendSystemEvents()
        .sendKeyboardEvents()
        .sendMouseEvents()
        .sendPostedEvents()
        .sendDestroyEvents()

        for s in .surfaces do
            s.paint()

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
    public mtd doModalLoop(surface: #null *Surface, cb: #null func||(*Application) = null)->WndId
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

        for s in disabledSurfaces do
            s.enable()

        if .modalSurfaces.count do
            .modalSurfaces.back().wnd.view.setFocus()
        elif disabledSurfaces.count do
            disabledSurfaces.back().wnd.view.setFocus()

        if surface do
            surface.destroy()

        let result = .endModalExit orelse ""
        .endModal     = false
        .endModalExit = null
        return result
    }
}

impl Application
{
    // Releases resources owned by this value.
    mtd opDrop()
    {
        .setGlobalHotKeysEnabled(false)

        for it in .surfaces do
            it.destroy()
        .sendDestroyEvents()

        for it in .postedEvents
        {
            let ptr = notnull (it as Event)
            .toDelete.add({ptr, notnull ptr.type})
        }

        .deletePointers()
        if @isset(.theme) do
            .theme.freeDefault()
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
        let surface = notnull (expect app.createSurface(x, y, width, height, flags, view, hook))
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
            if !@isset(.renderer) do
                .setRenderer(&.rendererOgl)
            if !@isset(.theme) do
                .theme = Memory.new'Theme()
            .style.set(.theme)
        }

        try Surface.create(surface, x, y, width, height, flags, .mainSurface)
        surfaceCreated = true

        if !.mainSurface
        {
            .renderer.setCurrentContext(surface.rc)
            .renderer.init()
            .theme.setupDefault(.renderer)
            .mainSurface = surface

            // Spin up the shared worker pool so the parallel rasterizers (glyph MSDF
            // generation, image resize/filtering, ...) actually run multi-core instead
            // of falling back to a synchronous single thread.
            if Jobs.isSynchronous() do
                discard catch Jobs.initialize()
        }

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

    // Selects the native application icon before the first surface is created.
    mtd setAppIcon(img: Pixel.Image)
    {
        .appIcon = img
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

        File.writeAllBytes(.statePath, buf)
    }

    // Loads serializable surface placement from the configured state file.
    mtd loadState() fail
    {
        if .statePath.isEmpty() do
            return

        var buf = File.readAllBytes(.statePath)

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
            let oldParent = notnull wnd.parent
            let detached  = oldParent.detachChild(wnd)
            Debug.assert(detached)
            oldParent.invalidate()
        }

        if wnd.isAllocated
        {
            .toDelete.add({wnd, notnull wnd.type})
        }
    }

    internal mtd windowAtMouse()->#null *Wnd
    {
        var mousePos      = .mouse.position()
        let targetSurface = .surfaceAt(mousePos.x, mousePos.y)
        if !targetSurface do
            return null
        let surface = targetSurface
        surface.screenToSurface(&mousePos)
        if !surface.isMaximized and surface.wnd.hitTestBorders(mousePos) != SizingBorder.None do
            return surface.wnd
        let targetWnd = surface.wnd.windowAt(mousePos.x, mousePos.y)
        return targetWnd
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
    mtd removeTimer(timer: *Timer)
    {
        if .duringTimerEvents
        {
            Debug.assert(!timer.isPendingRemoval)
            timer.isPendingRemoval = true
            .timersToDelete.add(timer)
        }
        else
        {
            Debug.assert(!timer.isPendingRemoval)
            Memory.delete(timer)
            .timers.remove(timer)
        }
    }

    internal mtd registerFrameEvent(target: *Wnd)
    {
        Debug.assert(!.frameEvents.contains(target))
        .frameEvents.add(target)
    }

    internal mtd unregisterFrameEvent(target: *Wnd)
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
        for shortcut, [idx] in .hotKeys
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
