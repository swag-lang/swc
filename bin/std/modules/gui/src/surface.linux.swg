#global public
#global if #os == Swag.TargetOs.Linux

using Core, Pixel

// X11 resources owned by one GUI surface; the drawable borrows the GUI event connection.
#[Swag.Opaque]
#[Swag.NoCopy]
internal struct NativeSurface
{
    windowId:           u32
    drawable:           Env.XcbDrawable
    colormap:           u32
    compose:            *void?
    topMost:            bool
    initializing:       bool
    preparingFrame:     bool
    preparedFrame:      bool
    presentedFrame:     bool
    presentationTarget: RenderTarget
    presentationWidth:  s32
    presentationHeight: s32
    dropTarget:         LinuxDrag.Target
    dropTargetActive:   bool
    trayWindow:         u32
    trayImage:          Image
}

internal func postLinuxSurfaceCommand(surface: *Surface, kind: SysCommandEvent.Kind)
{
    if surface.wnd.isPendingDestroy do
        return
    let event = Event.create'SysCommandEvent()
    event.kind = kind
    surface.wnd.view.postEvent(event)
}

impl Surface
{
    internal func createNative(app: *Application, result: *Surface, x, y, width, height: s32, _: SurfaceFlags) fail
    {
        if width <= 0 or
           width > 65535 or
           height <= 0 or
           height > 65535 or
           x < -32768 or
           x > 32767 or
           y < -32768 or
           y > 32767 do
            fail Errors.BadParameterError{"X11 GUI geometry is outside protocol limits"}
        let context    = try LinuxDesktop.ensure()
        let connection = unwrap context.connection
        try LinuxDesktop.initializeKeyboard(context)
        let scale          = LinuxDesktop.preferences(context).scale
        let physicalWidth  = cast(s32, Math.round(width * scale))
        let physicalHeight = cast(s32, Math.round(height * scale))
        if physicalWidth > 65535 or physicalHeight > 65535 do
            fail Errors.BadParameterError{"scaled X11 GUI geometry is outside protocol limits"}
        var visual: u32
        var depths = context.xcb_screen_allowed_depths_iterator(unwrap context.screenPtr)
        while depths.rem > 0
        {
            let depth = unwrap depths.data
            if depth.depth == 32
            {
                var visuals = context.xcb_depth_visuals_iterator(depth)
                while visuals.rem > 0
                {
                    let item = unwrap visuals.data
                    if item._class == 4 and
                       item.red_mask == 0xFF0000 and
                       item.green_mask == 0xFF00 and
                       item.blue_mask == 0xFF
                    {
                        visual = item.visual_id
                        break
                    }

                    context.xcb_visualtype_next(&visuals)
                }
            }

            if visual != 0 do
                break
            context.xcb_depth_next(&depths)
        }

        if visual == 0 do
            fail Swag.SystemError{"the X11 screen has no ARGB32 visual for GUI surfaces"}
        result.colormap = context.xcb_generate_id(connection)
        try LinuxDesktop.check(context, context.xcb_create_colormap_checked(connection, 0, result.colormap, context.screen.root, visual))
        defer #fail
        {
            discard catch LinuxDesktop.check(context, context.xcb_free_colormap_checked(connection, result.colormap))
            result.colormap = 0
        }

        let id = context.xcb_generate_id(connection)
        let events: u32 = (1 << 0) | (1 << 1) | (1 << 2) | (1 << 3) | (1 << 6) |
                          (1 << 15) | (1 << 17) | (1 << 21) | (1 << 22)
        let values: [4]u32 = [0, 0, events, result.colormap]
        try LinuxDesktop.check(context,
                               context.xcb_create_window_checked(connection,
                                                                 32,
                                                                 id,
                                                                 context.screen.root,
                                                                 cast(s16, x),
                                                                 cast(s16, y),
                                                                 cast(u16, physicalWidth),
                                                                 cast(u16, physicalHeight),
                                                                 0,
                                                                 1,
                                                                 visual,
                                                                 (1 << 1) |
                                                                 (1 << 3) |
                                                                 (1 << 11) |
                                                                 (1 << 13),
                                                                 values))
        result.windowId = id
        result.drawable = {context.connection, id, visual, context.screenIndex}
        defer #fail
        {
            discard catch LinuxDesktop.check(context, context.xcb_destroy_window_checked(connection, id))
            result.windowId = 0
            result.drawable = {}
        }

        result.compose = context.xkb_compose_state_new(unwrap context.composeTable, 0)
        if not result.compose do
            fail Swag.SystemError{"cannot create keyboard composition state"}
        defer #fail
        {
            context.xkb_compose_state_unref(unwrap result.compose)
            result.compose = null
        }

        let protocols: [2]u32 = [try LinuxDesktop.atom(context, "WM_DELETE_WINDOW"), try LinuxDesktop.atom(context, "_NET_WM_PING")]
        try LinuxDesktop.property(context, id, try LinuxDesktop.atom(context, "WM_PROTOCOLS"), 4, 32, 2, protocols)
        let motif: [5]u32 = [2, 0, 0, 0, 0]
        try LinuxDesktop.property(context, id, try LinuxDesktop.atom(context, "_MOTIF_WM_HINTS"), try LinuxDesktop.atom(context, "_MOTIF_WM_HINTS"), 32, 5, motif)
        let identity = result.surfaceId.toString()
        try LinuxDesktop.property(context, id, try LinuxDesktop.atom(context, "_SWAG_GUI_SURFACE"), try LinuxDesktop.atom(context, "UTF8_STRING"), 8, cast(u32, identity.count), identity.buffer)
        var className = String.from("swag")
        className += "\0Swag\0"
        try LinuxDesktop.property(context, id, 67, 31, 8, cast(u32, className.count), className.buffer)
        let process = cast(u32, Env.Process.currentProcessId())
        try LinuxDesktop.property(context, id, try LinuxDesktop.atom(context, "_NET_WM_PID"), 6, 32, 1, &process)
        if app.appIcon.isValid()
        {
            var icons: Array'u32
            for size in [32, 64]
            {
                let icon = app.appIcon.resized(size, size, .Bilinear)
                icons.add(cast(u32, size))
                icons.add(cast(u32, size))
                for row in size do
                    for column in size do
                        icons.add(icon.pixelColor(column, row).argb)
            }

            try LinuxDesktop.property(context, id, try LinuxDesktop.atom(context, "_NET_WM_ICON"), 6, 32, cast(u32, icons.count), icons.buffer)
        }

        let owner = app.mainSurface
        if owner and owner.windowId != 0 do
            try LinuxDesktop.property(context, id, 68, 33, 32, 1, &owner.windowId)
        result.position = {x, y, physicalWidth, physicalHeight}
        result.dpiScale = scale
        result.applyNativeSurfaceFlags()
        if context.cursors[context.currentCursor] != 0
        {
            let cursor = context.cursors[context.currentCursor]
            try LinuxDesktop.check(context, context.xcb_change_window_attributes_checked(connection, id, 1 << 14, &cursor))
        }

        context.surfaces.add(result)
        result.registerDropTarget()
    }

    internal mtd destroyNative()
    {
        if .rc.data
        {
            .app.renderer.setCurrentContext(.rc)
            if .presentationTarget.colorBuffer.isValid() do
                .app.renderer.deleteRenderTarget(&.presentationTarget)
        }

        .destroyRendering()
        if .windowId == 0 and .colormap == 0 do
            return
        let context    = expect LinuxDesktop.ensure()
        let connection = unwrap context.connection
        if context.pointerCapture == me do
            .app.releaseMouse()
        .revokeDropTarget()
        .removeTrayIcon()
        for surface, index in context.surfaces where surface == me
        {
            context.surfaces.removeAt(index)
            break
        }

        if .compose do
            context.xkb_compose_state_unref(.compose)
        .compose = null
        if .windowId != 0 do
            discard catch LinuxDesktop.check(context, context.xcb_destroy_window_checked(connection, .windowId))
        if .colormap != 0 do
            discard catch LinuxDesktop.check(context, context.xcb_free_colormap_checked(connection, .colormap))
        .windowId = 0
        .colormap = 0
        .drawable = {}
    }

    // Returns the borrowed XCB drawable of a live native surface.
    //
    // The connection and window remain owned by the GUI thread. Fails for a closed or headless
    // surface. Do not destroy the window, disconnect the connection or consume its event queue.
    mtd const xcbDrawable()->Env.XcbDrawable fail
    {
        if .windowId == 0 do
            fail Errors.BadParameterError{"surface has no native XCB drawable"}
        discard try LinuxDesktop.ensure()
        return .drawable
    }

    internal mtd const nativeRenderHandle()->const *void?
    {
        return .windowId != 0 ? &.drawable : null
    }

    internal mtd setFocus()
    {
        if .windowId == 0 or .isHidden or .isDisabled do
            return
        let context    = expect LinuxDesktop.ensure()
        let connection = unwrap context.connection
        let manager    = expect LinuxDesktop.readProperty(context, context.screen.root, expect LinuxDesktop.atom(context, "_NET_SUPPORTING_WM_CHECK"))
        if manager.count >= 4
        {
            expect LinuxDesktop.send(context, .windowId, expect LinuxDesktop.atom(context, "_NET_ACTIVE_WINDOW"), [1, 0, 0, 0, 0])
            return
        }

        let attributes = context.xcb_get_window_attributes_reply(connection, context.xcb_get_window_attributes(connection, .windowId), null)
        if not attributes do
            return
        let mapped = attributes.map_state == 2
        Linux.free(attributes)
        if mapped do
            expect LinuxDesktop.check(context, context.xcb_set_input_focus_checked(connection, 2, .windowId, 0))
    }

    internal mtd bindNativePresentationTarget()
    {
        if .presentationWidth != .rc.width or .presentationHeight != .rc.height
        {
            if .presentationTarget.colorBuffer.isValid() do
                .app.renderer.deleteRenderTarget(&.presentationTarget)
            .presentationTarget = .app.renderer.createRenderTarget(.rc.width, .rc.height)
            .presentationWidth  = .rc.width
            .presentationHeight = .rc.height
        }

        .app.renderer.bindRenderTarget(&.presentationTarget)
    }

    // EGL presents directly at renderer.end; this path owns no asynchronous CPU readback.
    internal mtd canQueueNativePresentation()->bool => false
    internal mtd queueNativePresentation(_: const *RenderTarget)->bool => false
    internal mtd advanceNativePresentation()->bool  => true
    internal mtd cancelNativePresentation() { .preparedFrame = false }

    internal mtd prepareNativePresentation(target: const *RenderTarget)
    {
        .painter.begin()
        .painter.setContentScale(1)
        .painter.setDefaultShader(.Simple)
        .painter.setColorMaskFull()
        .painter.setInterpolationMode(.Pixel)
        .painter.setBlendingMode(.Copy)
        let area = Math.Rectangle{0, 0, cast(f32, .rc.width), cast(f32, .rc.height)}
        .painter.drawTexture(area, area, target.colorBuffer, Argb.White)
        .painter.end()
        .app.renderer.unbindRenderTarget()
        .app.renderer.draw(&.painter)
        .preparedFrame = true
    }

    internal mtd publishNativePresentation()
    {
        // renderer.end has completed eglSwapBuffers; retain the completed-frame state.
        .presentedFrame = .preparedFrame
        .preparedFrame  = false
    }

    internal mtd applyNativeTitle()
    {
        if .windowId == 0 do
            return
        let context = expect LinuxDesktop.ensure()
        let title   = .wnd.name.raw.isEmpty() ? .surfaceId.toString() : .wnd.name.raw.toString()
        expect LinuxDesktop.property(context,
                                     .windowId,
                                     expect LinuxDesktop.atom(context, "_NET_WM_NAME"),
                                     expect LinuxDesktop.atom(context, "UTF8_STRING"),
                                     8,
                                     cast(u32, title.count),
                                     title.buffer)
    }

    internal mtd applyNativeSurfaceFlags()
    {
        .topMost = .flags.has(.TopMost)
        if .windowId == 0 do
            return
        let context = expect LinuxDesktop.ensure()
        let kind    = expect LinuxDesktop.atom(context, .flags.has(.ToolWindow) ? "_NET_WM_WINDOW_TYPE_UTILITY" : "_NET_WM_WINDOW_TYPE_NORMAL")
        expect LinuxDesktop.property(context, .windowId, expect LinuxDesktop.atom(context, "_NET_WM_WINDOW_TYPE"), 4, 32, 1, &kind)
        var hints: [18]u32
        hints[0] = (1 << 4) | (1 << 5)
        let fixed = not .flags.has(.Resizable)
        hints[5] = cast(u32, fixed ? .position.width : Math.max(1, .minSize.x * .dpiScale))
        hints[6] = cast(u32, fixed ? .position.height : Math.max(1, .minSize.y * .dpiScale))
        hints[7] = cast(u32, fixed ? .position.width : .maxSize.x > 0 ? .maxSize.x * .dpiScale : 65535)
        hints[8] = cast(u32, fixed ? .position.height : .maxSize.y > 0 ? .maxSize.y * .dpiScale : 65535)
        expect LinuxDesktop.property(context, .windowId, 40, 41, 32, 18, hints)
        .setNativeState("_NET_WM_STATE_ABOVE", .topMost)
    }

    private mtd setNativeState(name: string, enabled: bool)
    {
        if .windowId == 0 do
            return
        let context       = expect LinuxDesktop.ensure()
        let stateProperty = expect LinuxDesktop.atom(context, "_NET_WM_STATE")
        let state         = expect LinuxDesktop.atom(context, name)
        if .isHidden
        {
            let bytes  = expect LinuxDesktop.readProperty(context, .windowId, stateProperty)
            var states: Array'u32
            let values = cast(const [*]u32?, bytes.buffer)
            for index in bytes.count / 4 where (unwrap values)[index] != state do
                states.add(values[index])
            if enabled do
                states.add(state)
            expect LinuxDesktop.property(context, .windowId, stateProperty, 4, 32, cast(u32, states.count), states.buffer)
        }
        else
        {
            expect LinuxDesktop.send(context, .windowId, stateProperty, [enabled ? 1'u32 : 0'u32, state, 0, 1, 0])
        }
    }

    private mtd const clampToSizeLimits(pos: Math.Rectangle)->Math.Rectangle
    {
        var result = pos
        result.width  = Math.max(result.width, Math.max(1, .minSize.x * .dpiScale))
        result.height = Math.max(result.height, Math.max(1, .minSize.y * .dpiScale))
        if .maxSize.x > 0 do
            result.width = Math.min(result.width, .maxSize.x * .dpiScale)
        if .maxSize.y > 0 do
            result.height = Math.min(result.height, .maxSize.y * .dpiScale)
        return result
    }

    // Sets physical screen bounds, clamped to the surface size limits.
    mtd setPosition(pos: Math.Rectangle)
    {
        let next = .clampToSizeLimits(pos)
        .position = next
        if .windowId != 0
        {
            let context    = expect LinuxDesktop.ensure()
            let connection = unwrap context.connection
            Swag.assert(next.x >= -32768 and next.x <= 32767 and next.y >= -32768 and next.y <= 32767)
            Swag.assert(next.width <= 65535 and next.height <= 65535)
            let values: [4]u32 = [cast #bit(u32, cast(s32, next.x)), cast #bit(u32, cast(s32, next.y)), cast(u32, next.width), cast(u32, next.height)]
            expect LinuxDesktop.check(context, context.xcb_configure_window_checked(connection, .windowId, 15, values))
        }

        .sendResizeEvent(next.width, next.height)
    }

    // Enables placement above ordinary windows, subject to the window manager's policy.
    mtd setTopMost(enabled = true)
    {
        if enabled do
            .flags.add(.TopMost)
        else do
            .flags.remove(.TopMost)
        .applyNativeSurfaceFlags()
    }

    // Reports the requested topmost state.
    mtd const isTopMost()->bool => .topMost

    // Raises this surface within its current native stacking group.
    mtd bringToFront()
    {
        if .windowId == 0 do
            return
        let context    = expect LinuxDesktop.ensure()
        let connection = unwrap context.connection
        let above: u32 = 0
        expect LinuxDesktop.check(context, context.xcb_configure_window_checked(connection, .windowId, 1 << 6, &above))
        expect LinuxDesktop.send(context, .windowId, expect LinuxDesktop.atom(context, "_NET_ACTIVE_WINDOW"), [1, 0, 0, 0, 0])
    }

    // Enables input and repaints the surface without its modal tint.
    mtd enable()
    {
        if not .isDisabled do
            return
        .isDisabled = false
        .invalidate()
    }

    // Disables input and repaints the surface with its modal tint.
    mtd disable()
    {
        if .isDisabled do
            return
        .isDisabled = true
        .invalidate()
    }

    // Requests the composited opacity from zero through one.
    mtd setOpacity(opacity: f32)
    {
        let next = Math.saturate(opacity)
        if .opacity == next do
            return
        .opacity = next
        if .windowId == 0 do
            return
        let context = expect LinuxDesktop.ensure()
        let value   = cast(u32, cast(f64, next) * 4294967295.0'f64)
        expect LinuxDesktop.property(context, .windowId, expect LinuxDesktop.atom(context, "_NET_WM_WINDOW_OPACITY"), 6, 32, 1, &value)
    }

    // Hides the surface without releasing its native or rendering resources.
    mtd hide()
    {
        if .isHidden do
            return
        .isHidden = true
        if .windowId != 0
        {
            let context    = expect LinuxDesktop.ensure()
            let connection = unwrap context.connection
            expect LinuxDesktop.check(context, context.xcb_unmap_window_checked(connection, .windowId))
        }

        .wnd.view.sendStateEvent(.Hide)
    }

    // Requests closure through the surface's ordinary deferred close command.
    mtd requestClose() { postLinuxSurfaceCommand(me, .Close) }

    // Requests minimization through the surface's ordinary system-command route.
    mtd requestMinimize() { postLinuxSurfaceCommand(me, .Minimize) }

    // Requests maximization through the surface's ordinary system-command route.
    mtd requestMaximize() { postLinuxSurfaceCommand(me, .Maximize) }

    // Requests restoration through the surface's ordinary system-command route.
    mtd requestRestore() { postLinuxSurfaceCommand(me, .Restore) }

    // Shows a maximized surface and remembers its current normal placement.
    mtd showMaximized() { .showMaximized(#copy .position) }

    // Shows a maximized surface with an explicit placement to restore later.
    mtd showMaximized(restoreTo: Math.Rectangle)
    {
        if not .isMaximized do
            .restoredPosition = restoreTo
        .restoreNativeMapping()
        .isMaximized = true
        .isMinimized = false
        .setNativeState("_NET_WM_STATE_MAXIMIZED_HORZ", true)
        .setNativeState("_NET_WM_STATE_MAXIMIZED_VERT", true)
        .show()
        .invalidate()
    }

    // Restores normal state and requests the supplied physical screen bounds.
    mtd showNormalAt(pos: Math.Rectangle)
    {
        .restoreNativeMapping()
        .isMaximized = false
        .isMinimized = false
        .setNativeState("_NET_WM_STATE_MAXIMIZED_HORZ", false)
        .setNativeState("_NET_WM_STATE_MAXIMIZED_VERT", false)
        .setPosition(pos)
        .show()
    }

    private mtd restoreNativeMapping()
    {
        if .windowId != 0 and .isMinimized and not .isHidden
        {
            let context = expect LinuxDesktop.ensure()
            expect LinuxDesktop.check(context, context.xcb_map_window_checked(unwrap context.connection, .windowId))
        }
    }

    // Restores the normal bounds saved before minimization or maximization.
    mtd showNormal()
    {
        if .isMaximized or .isMinimized do
            .showNormalAt(.restoredPosition)
    }

    // Asks the window manager to iconify the surface.
    mtd showMinimized()
    {
        if .isMinimized do
            return
        if not .isMaximized do
            .restoredPosition = .position
        .isMinimized = true
        if .windowId != 0
        {
            let context = expect LinuxDesktop.ensure()
            expect LinuxDesktop.send(context, .windowId, expect LinuxDesktop.atom(context, "WM_CHANGE_STATE"), [3, 0, 0, 0, 0])
        }
    }

    // Converts physical desktop coordinates to logical client coordinates in place.
    mtd screenToSurface(point: *Math.Point)
    {
        if .windowId != 0
        {
            let context    = expect LinuxDesktop.ensure()
            let connection = unwrap context.connection
            let reply      = context.xcb_translate_coordinates_reply(connection,
                                                                     context.xcb_translate_coordinates(connection, context.screen.root, .windowId, cast(s16, point.x), cast(s16, point.y)),
                                                                     null)
            if not reply

            {
                expect LinuxDesktop.failNative(Linux.EIO)

                unreachable
            }

            defer Linux.free(reply)
            point[] = {cast(f32, reply.dst_x) / .dpiScale, cast(f32, reply.dst_y) / .dpiScale}
            return
        }

        point[] = {(point.x - .position.x) / .dpiScale, (point.y - .position.y) / .dpiScale}
    }

    // Converts logical client coordinates to physical desktop coordinates in place.
    mtd surfaceToScreen(point: *Math.Point)
    {
        if .windowId != 0
        {
            let context    = expect LinuxDesktop.ensure()
            let connection = unwrap context.connection
            let reply      = context.xcb_translate_coordinates_reply(connection,
                                                                     context.xcb_translate_coordinates(connection, .windowId, context.screen.root, cast(s16, point.x * .dpiScale), cast(s16, point.y * .dpiScale)),
                                                                     null)
            if not reply

            {
                expect LinuxDesktop.failNative(Linux.EIO)

                unreachable
            }

            defer Linux.free(reply)
            point[] = {reply.dst_x, reply.dst_y}
            return
        }

        point[] = {point.x * .dpiScale + .position.x, point.y * .dpiScale + .position.y}
    }

    // Shows the surface and emits its one-time initialization event when needed.
    //
    // A [[Gui.SurfaceFlags.Sheet]] arrives the way a floating surface does inside a window: it
    // fades in over its owner, without travel, unless motion is reduced.
    mtd show()
    {
        if not .isHidden do
            return

        .isHidden = false
        if .flags.has(.Sheet) and not .app.isReducedMotion()
        {
            .opacity = 0
            var options: AnimationOptions
            options.duration = Time.Duration.fromSeconds(.wnd.themeMetrics().motion_PageSeconds)
            options.easing   = .EaseOut
            discard .app.animator.animateF32(.wnd,
                                             AnimationChannel.from("Gui.Surface.Opacity"),
                                             0,
                                             1,
                                             func(wnd, value) { wnd.surface?.setOpacity(value) },
                                             options,
                                             func|srf = me|(_) { srf.setOpacity(1) })
        }

        // First-show initialization stage. Runs while the window is still hidden,
        // so the application can perform slow setup (restoring state, loading
        // content, resizing the surface, ...). The window is only made visible
        // afterwards, once a first frame has been rendered.
        if not .isInitialized
        {
            .isInitialized = true
            .initializing  = true
            .wnd.view.sendStateEvent(.Init)
            .initializing = false
        }

        .invalidate()
        .wnd.applyLayout(.size())

        // Render the first complete frame into the back buffer *before* the window
        // becomes visible. Otherwise the compositor displays the still-empty (black)
        // GL surface, and the user sees a black flash until the first runFrame()
        // paint completes (which is slow on the first frame because of the lazy
        // font/glyph generation it triggers). Painting while still hidden means the
        // window appears already showing correct content.
        .preparingFrame = true
        .paint()
        .preparingFrame = false

        if not .app.renderer.needsNativeWindow()
        {
            let curFocus = .wnd.view.focusedWindow()
            if not curFocus or not .wnd.isAncestorOf(curFocus) do
                discard .restoreFocus()
            .wnd.view.sendStateEvent(.Show)
            return
        }

        let context    = expect LinuxDesktop.ensure()
        let connection = unwrap context.connection
        expect LinuxDesktop.check(context, context.xcb_map_window_checked(connection, .windowId))

        let curFocus = .wnd.view.focusedWindow()
        if not curFocus or not .wnd.isAncestorOf(curFocus) do
            discard .restoreFocus()
        .bringToFront()
        .setFocus()

        .wnd.view.sendStateEvent(.Show)
    }
}

impl Surface
{
    internal mtd refreshNativeState()
    {
        if .windowId == 0 do
            return
        let context    = expect LinuxDesktop.ensure()
        let bytes      = catch LinuxDesktop.readProperty(context, .windowId, expect LinuxDesktop.atom(context, "_NET_WM_STATE")) { return; }
        let count      = bytes.count / 4
        let values     = cast(const [*]u32?, bytes.buffer)
        let horizontal = expect LinuxDesktop.atom(context, "_NET_WM_STATE_MAXIMIZED_HORZ")
        let vertical   = expect LinuxDesktop.atom(context, "_NET_WM_STATE_MAXIMIZED_VERT")
        let hidden     = expect LinuxDesktop.atom(context, "_NET_WM_STATE_HIDDEN")
        var hasHorizontal, hasVertical, minimized: bool
        for index in count
        {
            let value = (unwrap values)[index]
            hasHorizontal = hasHorizontal or value == horizontal
            hasVertical   = hasVertical or value == vertical
            minimized     = minimized or value == hidden
        }

        let maximized = hasHorizontal and hasVertical
        if maximized != .isMaximized or minimized != .isMinimized
        {
            if maximized and not .isMaximized do
                .restoredPosition = .position
            .isMaximized = maximized
            .isMinimized = minimized
            .invalidate()
        }
    }

    // Sends an application-defined message to a native surface identified by its creation id.
    //
    // Searches this X11 display, including windows reparented by a window manager. Returns false
    // when no matching surface exists or the server rejects the request.
    func sendCustomMessage(surfaceId: string, id: u32, param: u64)->bool
    {
        let context    = catch LinuxDesktop.ensure() { return false; }
        let connection = unwrap context.connection
        let identity   = catch LinuxDesktop.atom(context, "_SWAG_GUI_SURFACE") { return false; }
        let kind       = catch LinuxDesktop.atom(context, "_SWAG_GUI_MESSAGE") { return false; }
        var pending: Array'u32
        pending.add(context.screen.root)
        while not pending.isEmpty()
        {
            let window = pending.back()
            pending.removeBack()
            let property = catch LinuxDesktop.readProperty(context, window, identity)
            if property.count == surfaceId.count and Utf8.compare(property.toSlice(), surfaceId) == 0
            {
                var event: Linux.xcb_client_message_event_t
                event.response_type = 33
                event.format        = 32
                event.window        = window
                event.type          = kind
                event.data          = [id, cast(u32, param & 0xFFFFFFFF), cast(u32, param >> 32), 0, 0]
                var outcome: Swag.Error
                catch LinuxDesktop.check(context, context.xcb_send_event_checked(connection, 0, window, 0, cast(const [*]u8, &event))) as outcome
                return outcome.value() == null
            }

            let reply = context.xcb_query_tree_reply(connection, context.xcb_query_tree(connection, window), null)
            if not reply do
                continue
            defer Linux.free(reply)
            let children = context.xcb_query_tree_children(reply)
            for index in context.xcb_query_tree_children_length(reply) do
                pending.add(children[index])
        }

        return false
    }

    // Publishes an XEmbed notification-area icon when this display has a system-tray manager.
    //
    // The image is owned until replacement or surface destruction. Without a tray manager,
    // a native surface or a valid image, nothing is published. Activation and context-menu
    // requests arrive through [[Gui.SysUserEvent]].
    mtd setTrayIcon(icon: Image, tip: string? = null)
    {
        if .windowId == 0 or not icon.isValid() do
            return
        let context    = expect LinuxDesktop.ensure()
        let connection = unwrap context.connection
        let selection  = expect LinuxDesktop.atom(context, Format.toString("_NET_SYSTEM_TRAY_S%", context.screenIndex).toString())
        let owner      = context.xcb_get_selection_owner_reply(connection, context.xcb_get_selection_owner(connection, selection), null)
        if not owner do
            return
        let manager = owner.owner
        Linux.free(owner)
        if manager == 0 do
            return
        .removeTrayIcon()
        let id = context.xcb_generate_id(connection)
        let values: [4]u32 = [0, 0, (1 << 2) | (1 << 15) | (1 << 17), .colormap]
        expect LinuxDesktop.check(context,
                                  context.xcb_create_window_checked(connection,
                                                                    32,
                                                                    id,
                                                                    context.screen.root,
                                                                    0,
                                                                    0,
                                                                    32,
                                                                    32,
                                                                    0,
                                                                    1,
                                                                    .drawable.visual,
                                                                    (1 << 1) |
                                                                    (1 << 3) |
                                                                    (1 << 11) |
                                                                    (1 << 13),
                                                                    values))
        .trayWindow = id
        .trayImage  = icon
        let info: [2]u32 = [0, 1]
        let embed        = expect LinuxDesktop.atom(context, "_XEMBED_INFO")
        expect LinuxDesktop.property(context, id, embed, embed, 32, 2, info)
        if tip do
            expect LinuxDesktop.property(context,
                                         id,
                                         expect LinuxDesktop.atom(context, "_NET_WM_NAME"),
                                         expect LinuxDesktop.atom(context, "UTF8_STRING"),
                                         8,
                                         cast(u32, tip.count),
                                         tip.buffer)
        var event: Linux.xcb_client_message_event_t
        event.response_type = 33
        event.format        = 32
        event.window        = manager
        event.type          = expect LinuxDesktop.atom(context, "_NET_SYSTEM_TRAY_OPCODE")
        event.data          = [0, 0, id, 0, 0]
        expect LinuxDesktop.check(context, context.xcb_send_event_checked(connection, 0, manager, 0, cast(const [*]u8, &event)))
    }

    internal mtd paintTrayIcon()
    {
        if .trayWindow == 0 or not .trayImage.isValid() do
            return
        let context    = expect LinuxDesktop.ensure()
        let connection = unwrap context.connection
        let geometry   = context.xcb_get_geometry_reply(connection, context.xcb_get_geometry(connection, .trayWindow), null)
        if not geometry do
            return
        let width  = geometry.width
        let height = geometry.height
        Linux.free(geometry)
        if width == 0 or height == 0 or width > 512 or height > 512 do
            return
        var pixels: Array'u8
        let order = context.xcb_get_setup(connection).image_byte_order
        for y in height
        {
            for x in width
            {
                let color = .trayImage.pixelColor(cast(s32, x) * .trayImage.width / width, cast(s32, y) * .trayImage.height / height)
                let alpha = cast(u32, color.a)
                let pixel = (alpha << 24) | (cast(u32, color.r) * alpha / 255 << 16) |
                            (cast(u32, color.g) * alpha / 255 << 8) | (cast(u32, color.b) * alpha / 255)
                for byte in 4 do
                    pixels.add(cast(u8, (pixel >> (order == 0 ? byte * 8 : (3 - byte) * 8)) & 255))
            }
        }

        let gc = context.xcb_generate_id(connection)
        expect LinuxDesktop.check(context, context.xcb_create_gc_checked(connection, gc, .trayWindow, 0, null))
        defer discard catch LinuxDesktop.check(context, context.xcb_free_gc_checked(connection, gc))
        expect LinuxDesktop.check(context,
                                  context.xcb_put_image_checked(connection,
                                                                2,
                                                                .trayWindow,
                                                                gc,
                                                                width,
                                                                height,
                                                                0,
                                                                0,
                                                                0,
                                                                32,
                                                                cast(u32, pixels.count),
                                                                unwrap pixels.buffer))
    }

    // Removes the notification-area icon owned by this surface.
    mtd removeTrayIcon()
    {
        if .trayWindow == 0 do
            return
        let context = expect LinuxDesktop.ensure()
        expect LinuxDesktop.check(context, context.xcb_destroy_window_checked(unwrap context.connection, .trayWindow))
        .trayWindow = 0
        .trayImage  = {}
    }
}

impl Surface
{
    internal mtd acceptNativeGeometry(width, height: u16)
    {
        var origin: Math.Point
        .surfaceToScreen(&origin)
        .position.x = origin.x
        .position.y = origin.y
        if .rc.width != width or .rc.height != height do
            .sendResizeEvent(cast(f32, width), cast(f32, height))
    }
}

impl Surface
{
    internal mtd acceptNativeScale(scale: f32)
    {
        if .dpiScale == scale do
            return
        let ratio  = scale / .dpiScale
        var bounds = .position
        bounds.width  = Math.round(bounds.width * ratio)
        bounds.height = Math.round(bounds.height * ratio)
        .setDpiScaleRaw(scale)
        .setPosition(bounds)
        .applyNativeSurfaceFlags()
    }
}
