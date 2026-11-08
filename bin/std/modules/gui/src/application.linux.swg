#global if #os == Swag.TargetOs.Linux

using Core, Pixel

// Linux application state. Native windows share one GUI-thread event connection.
#[Swag.Opaque]
struct ApplicationNative
{
    nativeKeyPresses:       [256]Input.Key
    public hotKeysDisabled: bool
    lastClickTime:          [Input.MouseButton]u32
    lastClickPosition:      [Input.MouseButton]Math.Point
}

impl Application
{
    internal mtd releaseNativeApplication()
    {
        if .mouseCaptureWnd do
            .releaseMouse()
    }

    internal mtd nativeFrameWaitMicroseconds(elapsed: u64)->u64
    {
        if .frameTrace.busyLoop do
            return 0
        for surface in .surfaces where not surface.isHidden and not surface.isMinimized
        {
            if surface.isDirty do
                return 0
        }

        let active   = .mouseCaptureWnd or .animator.activeCount() != 0
        let interval = active ? 1000'u64 : 16000'u64
        if elapsed >= interval do
            return 0
        var wait = interval - elapsed
        for timer in .timers where not timer.isPendingRemoval
        {
            let period = timer.periodMilliseconds * 1000
            let passed = timer.stopwatch.isRunning() ? timer.stopwatch.elapsedMicroseconds() : 0
            if passed >= period do
                return 0
            wait = Math.min(wait, period - passed)
        }

        return wait
    }

    internal mtd waitForNativeFrame(startedAt: u64)
    {
        let wait = .nativeFrameWaitMicroseconds(Time.monotonicMicroseconds() - startedAt)
        if wait == 0 do
            return
        let context    = expect LinuxDesktop.ensure()
        let connection = unwrap context.connection
        if context.pendingEvent do
            return
        context.pendingEvent = context.xcb_poll_for_event(connection)
        if context.pendingEvent do
            return
        discard context.xcb_flush(connection)
        var descriptor = Linux.pollfd{context.xcb_get_file_descriptor(connection), Linux.POLLIN, 0}
        let result     = Linux.poll(&descriptor, 1, cast(s32, (wait + 999) / 1000))
        if result < 0 and Linux.errno() != Linux.EINTR do
            expect LinuxDesktop.failNative(Linux.errno())
        if descriptor.revents & (Linux.POLLERR | Linux.POLLHUP | Linux.POLLNVAL) do
            .mustQuit = true
    }

    internal mtd refreshSystemMotionPreference()
    {
        if .renderer != null and not .renderer.needsNativeWindow() do
            return
        let preference = LinuxDesktop.preferences(expect LinuxDesktop.ensure())
        let previous   = .isReducedMotion()
        .systemReducedMotion = preference.reducedMotion
        if not previous and .isReducedMotion() do
            .animator.finishDecorative()
    }

    internal mtd refreshSystemAppearance()
    {
        if .renderer != null and not .renderer.needsNativeWindow() do
            return
        let preference = LinuxDesktop.preferences(expect LinuxDesktop.ensure())
        if .theme != null do
            .setSystemPrefersLight(preference.prefersLight)
        else do
            .systemPrefersLight = preference.prefersLight
    }

    internal mtd captureMouse(window: *Wnd)
    {
        if not .renderer.needsNativeWindow()
        {
            .mouseCaptureWnd = window
            return
        }

        let surface    = unwrap window.surface
        let context    = expect LinuxDesktop.ensure()
        let connection = unwrap context.connection
        let reply      = context.xcb_grab_pointer_reply(connection,
                                                        context.xcb_grab_pointer(connection,
                                                                                 0,
                                                                                 surface.windowId,
                                                                                 (1 << 2) |
                                                                                 (1 << 3) |
                                                                                 (1 << 6),
                                                                                 1,
                                                                                 1,
                                                                                 0,
                                                                                 0,
                                                                                 0),
                                                        null)
        if not reply

        {
            expect LinuxDesktop.failNative(Linux.EIO)

            unreachable
        }

        defer Linux.free(reply)
        if reply.status != 0 do
            expect LinuxDesktop.failNative(Linux.EBUSY)
        context.pointerCapture = surface
        .mouseCaptureWnd       = window
    }

    internal mtd releaseMouse()
    {
        if .mouseCaptureWnd and .renderer.needsNativeWindow()
        {
            let context    = expect LinuxDesktop.ensure()
            let connection = unwrap context.connection
            expect LinuxDesktop.check(context, context.xcb_ungrab_pointer_checked(connection, 0))
            context.pointerCapture = null
        }

        .mouseCaptureWnd = null
    }

    private func nativeModifiers(modifiers: Input.KeyModifiers)->u16
    {
        var result: u16
        if modifiers & .Shift do
            result |= 1
        if modifiers & .Control do
            result |= 4
        if modifiers & .Alt do
            result |= 8
        return result
    }

    private func nativeKeyCode(context: *LinuxDesktop.Context, key: Input.Key)->u8 fail
    {
        let connection = unwrap context.connection
        let setup      = context.xcb_get_setup(connection)
        let count      = cast(u16, setup.max_keycode) - setup.min_keycode + 1
        if count > 255 do
            fail Swag.SystemError{"X11 keyboard map is too large"}
        let mapping = context.xcb_get_keyboard_mapping_reply(connection,
                                                             context.xcb_get_keyboard_mapping(connection, setup.min_keycode, cast(u8, count)),
                                                             null)
        if not mapping do
            fail Swag.SystemError{"cannot read the X11 keyboard map"}
        defer Linux.free(mapping)
        let symbols = context.xcb_get_keyboard_mapping_keysyms(mapping)
        let wanted  = Input.Keyboard.keyToVirtualKey(key)
        for index in count
        {
            for column in mapping.keysyms_per_keycode
            {
                if symbols[index * mapping.keysyms_per_keycode + column] == wanted do
                    return cast(u8, setup.min_keycode + index)
            }
        }

        fail Errors.BadParameterError{"the requested shortcut key is absent from the keyboard map"}
    }

    internal func registerNativeHotKey(modifiers: Input.KeyModifiers, key: Input.Key) fail
    {
        let context = try LinuxDesktop.ensure()
        try LinuxDesktop.initializeKeyboard(context)
        let connection         = unwrap context.connection
        let code               = try nativeKeyCode(context, key)
        let mask               = nativeModifiers(modifiers)
        let locks:      [4]u16 = [0, 2, 16, 18]
        var registered: u32
        defer #fail
        {
            for index in registered do
                discard catch LinuxDesktop.check(context, context.xcb_ungrab_key_checked(connection, code, context.screen.root, mask | locks[index]))
        }

        for lock in locks
        {
            try LinuxDesktop.check(context, context.xcb_grab_key_checked(connection, 0, context.screen.root, mask | lock, code, 1, 1))
            registered += 1
        }
    }

    internal func unregisterNativeHotKey(modifiers: Input.KeyModifiers, key: Input.Key)
    {
        let context       = catch LinuxDesktop.ensure() { return; }
        let connection    = unwrap context.connection
        let code          = catch nativeKeyCode(context, key) { return; }
        let mask          = nativeModifiers(modifiers)
        let locks: [4]u16 = [0, 2, 16, 18]
        for lock in locks do
            discard catch LinuxDesktop.check(context, context.xcb_ungrab_key_checked(connection, code, context.screen.root, mask | lock))
    }

    internal mtd sendSystemEvents()
    {
        if not .renderer.needsNativeWindow() do
            return
        .nativeKeyboardEvents = true
        .nativeMouseButtons   = true
        let context    = expect LinuxDesktop.ensure()
        let connection = unwrap context.connection
        for 4096
        {
            let event = context.pendingEvent orelse context.xcb_poll_for_event(connection)
            context.pendingEvent = null
            if not event do
                break
            defer Linux.free(event)
            let kind = event.response_type & 0x7F
            if kind == 34 or (context.xkbEventBase != 0 and kind == context.xkbEventBase and event.pad0 <= 2)
            {
                var changed: bool
                if kind == 34 or event.pad0 <= 1
                {
                    changed = LinuxDesktop.refreshKeyboardMap(context)
                }
                else
                {
                    let state = cast(*Linux.xcb_xkb_state_notify_event_t, cast(*void, event))
                    changed = state.changed & 0xF0 != 0
                }

                if changed
                {
                    for owned in context.surfaces do
                        owned.app.notifyKeyboardLayoutChanged(owned.wnd)
                }
                continue
            }

            var id: u32
            switch kind
            {
            case 2, 3, 4, 5, 6: id = cast(*Linux.xcb_key_press_event_t, cast(*void, event)).event
            case 9, 10:         id = cast(*Linux.xcb_focus_in_event_t, cast(*void, event)).event
            case 12:            id = cast(*Linux.xcb_expose_event_t, cast(*void, event)).window
            case 17, 19:        id = cast(*Linux.xcb_destroy_notify_event_t, cast(*void, event)).window
            case 22:            id = cast(*Linux.xcb_configure_notify_event_t, cast(*void, event)).window
            case 28:            id = cast(*Linux.xcb_property_notify_event_t, cast(*void, event)).window
            case 33:            id = cast(*Linux.xcb_client_message_event_t, cast(*void, event)).window
            default:            continue
            }

            var refreshPreferences = id == context.settingsOwner and (kind == 28 or kind == 17)
            if id == context.screen.root and kind == 28
            {
                refreshPreferences = cast(*Linux.xcb_property_notify_event_t, cast(*void, event)).atom == expect LinuxDesktop.atom(context, "RESOURCE_MANAGER")
            }
            elif id == context.screen.root and kind == 33
            {
                let notice = cast(*Linux.xcb_client_message_event_t, cast(*void, event))
                refreshPreferences = notice.type == expect LinuxDesktop.atom(context, "MANAGER") and
                                     notice.data[1] == expect LinuxDesktop.atom(context, Format.toString("_XSETTINGS_S%", context.screenIndex))
            }

            if refreshPreferences
            {
                let preference = LinuxDesktop.preferences(context)
                for owned in context.surfaces
                {
                    owned.app.refreshSystemMotionPreference()
                    owned.app.refreshSystemAppearance()
                    owned.acceptNativeScale(preference.scale)
                }
            }

            if id == context.screen.root and kind == 2
            {
                let packet = cast(*Linux.xcb_key_press_event_t, cast(*void, event))
                let key    = LinuxDesktop.portableKey(context, packet.detail, packet.state)
                var modifiers: Input.KeyModifiers
                if packet.state & 1 do
                    modifiers |= .Shift
                if packet.state & 4 do
                    modifiers |= .Control
                if packet.state & 8 do
                    modifiers |= .Alt
                .dispatchHotKey(modifiers, key)
                continue
            }

            let surface = LinuxDesktop.surface(id)
            if not surface do
                continue
            if id == surface.trayWindow
            {
                if kind == 12 or kind == 22
                {
                    surface.paintTrayIcon()
                }
                elif kind == 17
                {
                    surface.trayWindow = 0
                }
                elif kind == 4
                {
                    let packet = cast(*Linux.xcb_button_press_event_t, cast(*void, event))
                    if packet.detail == 1 or packet.detail == 3
                    {
                        var notice = SysUserEvent{}
                        notice.kind       = .TrayIcon
                        notice.trayAction = packet.detail == 1 ? .Activate : .ContextMenu
                        surface.wnd.view.sendEvent(&notice)
                    }
                }

                continue
            }

            if dispatchDragNativeEvent(surface, event) do
                continue
            switch kind
            {
            case 2, 3:
                if not surface.isDisabled
                {
                    let packet = cast(*Linux.xcb_key_press_event_t, cast(*void, event))
                    LinuxDesktop.dispatchKey(context, surface, packet, kind == 2)
                }

            case 4, 5:
                let packet = cast(*Linux.xcb_button_press_event_t, cast(*void, event))
                if not surface.isDisabled
                {
                    if packet.detail == 4 or packet.detail == 5
                    {
                        if kind == 4 do
                            surface.app.sendMouseWheelEvent(surface, {packet.root_x, packet.root_y}, packet.detail == 4 ? 1 : -1)
                    }
                    else
                    {
                        .dispatchNativeButton(surface, packet, kind == 4)
                    }
                }

            case 9:
                surface.app.setActivated(true)
                if not surface.app.nativeFocusTransition do
                    discard surface.restoreFocus()

            case 10:
                Memory.clear(&surface.app.nativeKeyPresses, #sizeof(surface.app.nativeKeyPresses))
                if not surface.app.nativeFocusTransition do
                    surface.loseKeyboardFocus()
                surface.app.setActivated(false)

            case 12:
                surface.invalidate()

            case 17:
                surface.windowId = 0
                surface.drawable = {}
                surface.destroy()

            case 19:
                if not surface.isHidden and not surface.isDisabled do
                    surface.setFocus()

            case 22:
                let packet = cast(*Linux.xcb_configure_notify_event_t, cast(*void, event))
                surface.acceptNativeGeometry(packet.width, packet.height)

            case 28:
                surface.refreshNativeState()

            case 33:
                let message = cast(*Linux.xcb_client_message_event_t, cast(*void, event))
                if message.format != 32 do
                    continue
                if message.type == expect LinuxDesktop.atom(context, "WM_PROTOCOLS")
                {
                    if message.data[0] == expect LinuxDesktop.atom(context, "WM_DELETE_WINDOW")
                    {
                        postLinuxSurfaceCommand(surface, .Close)
                    }
                    elif message.data[0] == expect LinuxDesktop.atom(context, "_NET_WM_PING")
                    {
                        message.window = context.screen.root
                        expect LinuxDesktop.check(context,
                                                  context.xcb_send_event_checked(connection,
                                                                                 0,
                                                                                 context.screen.root,
                                                                                 (1 << 19) | (1 << 20),
                                                                                 cast(const [*]u8, message)))
                    }
                }
                elif message.type == expect LinuxDesktop.atom(context, "_SWAG_GUI_MESSAGE")
                {
                    var notice = SysUserEvent{}
                    notice.kind      = .CustomMessage
                    notice.messageId = message.data[0]
                    notice.param     = cast(u64, message.data[1]) | (cast(u64, message.data[2]) << 32)
                    surface.wnd.view.sendEvent(&notice)
                }
            }
        }

        if context.xcb_connection_has_error(connection) != 0
        {
            .mustQuit = true
            .quitCode = 1
        }
    }

    internal mtd surfaceAtNative(x, y: f32)->*Surface?
    {
        let context    = expect LinuxDesktop.ensure()
        let connection = unwrap context.connection
        var parent     = context.screen.root
        for 64
        {
            let reply = context.xcb_translate_coordinates_reply(connection,
                                                                context.xcb_translate_coordinates(connection, context.screen.root, parent, cast(s16, x), cast(s16, y)),
                                                                null)
            if not reply do
                return null
            let child = reply.child
            Linux.free(reply)
            if child == 0 do
                return null
            let surface = LinuxDesktop.surface(child)
            if surface
            {
                if surface.app != me or surface.isDisabled do
                    return null
                if not .modalSurfaces.isEmpty() and surface != .modalSurfaces.back() do
                    return null
                return surface
            }

            parent = child
        }

        return null
    }

    internal mtd specialDirectoryIcon(what: Env.SpecialDirectory, small = true)->Icon
    {
        return .theme.fileGlyph(Env.getSpecialDirectory(what).toString(), true, small ? 16 : 32)
    }

    internal mtd fileOrDirectoryIcon(name: string, isDirectory: bool, small = true)->Icon
    {
        return .theme.fileGlyph(name, isDirectory, small ? 16 : 32)
    }
}

namespace LinuxDesktop
{
    internal func portableKey(context: *Context, code: u8, state: u16)->Input.Key
    {
        var symbols: const [*]u32?
        let count = context.xkb_keymap_key_get_syms_by_level(unwrap context.keyboardMap, code, 0, 0, &symbols)
        if count <= 0 or not symbols do
            return .None
        var symbol = symbols[0]

        // Keypad commands follow NumLock and Shift. Other shortcuts keep their base symbol.
        if symbol >= 0xFF80 and symbol <= 0xFFBD
        {
            let keyboardState = unwrap context.keyboardState
            discard context.xkb_state_update_mask(keyboardState, state & 255, 0, 0, 0, 0, (state >> 13) & 3)
            symbol = context.xkb_state_key_get_one_sym(keyboardState, code)
        }

        return Input.Keyboard.virtualKeyToKey(symbol)
    }

    internal func dispatchKey(context: *Context, surface: *Surface, packet: *Linux.xcb_key_press_event_t, pressed: bool)
    {
        let app = surface.app
        var key = app.nativeKeyPresses[packet.detail]
        let wasPressed = key != .None
        if key == .None do
            key = portableKey(context, packet.detail, packet.state)

        // A lock change while held must not turn the release into a different key.
        app.nativeKeyPresses[packet.detail] = pressed ? key : .None
        app.keyboard.setCurrentKeyState(key, pressed)
        if pressed and not app.keyboardFocusWnd do
            app.seedKeyboardFocus()
        let target = app.keyboardFocusWnd
        if not target or target.isDisabled() do
            return
        var modifiers: Input.KeyModifiers
        if packet.state & 1 do
            modifiers |= .Shift
        if packet.state & 4 do
            modifiers |= .Control
        if packet.state & 8 do
            modifiers |= .Alt
        // X11 can deliver another KeyPress while the key remains held. Keep the physical
        // transition single, while still delivering the repeated text below.
        if not pressed or not wasPressed
        {
            var event = KeyEvent{kind: pressed ? .Pressed : .Released, key: key, modifiers: modifiers}
            target.sendEvent(&event)
            if pressed and not event.accepted do
                app.routeUnhandledKey(target, key, event.modifiers)
        }
        if not pressed do
            return
        let keyboardState = unwrap context.keyboardState
        discard context.xkb_state_update_mask(keyboardState, packet.state & 255, 0, 0, 0, 0, (packet.state >> 13) & 3)
        var symbol = context.xkb_state_key_get_one_sym(keyboardState, packet.detail)
        if surface.compose
        {
            discard context.xkb_compose_state_feed(surface.compose, symbol)
            let status = context.xkb_compose_state_get_status(surface.compose)
            if status == 1 do
                return
            if status == 2
            {
                // A compose result can contain several Unicode scalars and have no keysym.
                let size = context.xkb_compose_state_get_utf8(surface.compose, null, 0)
                if size > 0 and not (packet.state & (4 | 8))
                {
                    var bytes: Array'u8
                    bytes.resize(cast(u64, size) + 1)
                    let count = context.xkb_compose_state_get_utf8(surface.compose, bytes.buffer, bytes.count)
                    if count > 0 and count <= size
                    {
                        let runes = Unicode.fromUtf8(Swag.makeSlice(bytes.buffer, cast(u64, count)))
                        for r in runes do
                            app.sendRuneEvent(key, r)
                    }
                }

                context.xkb_compose_state_reset(surface.compose)
                return
            }
            if status == 3 do
                context.xkb_compose_state_reset(surface.compose)
            if status == 3 do
                return
        }

        let character = context.xkb_keysym_to_utf32(symbol)
        if character >= 32 and character != 127 and not (packet.state & (4 | 8)) do
            app.sendRuneEvent(key, cast(rune, character))
    }
}

impl Application
{
    // Samples the root drawable pixel under the pointer on the current X11 screen.
    func pickColorAtMouse()->Color
    {
        let context    = expect LinuxDesktop.ensure()
        let connection = unwrap context.connection
        let pointer    = context.xcb_query_pointer_reply(connection, context.xcb_query_pointer(connection, context.screen.root), null)
        if not pointer

        {
            expect LinuxDesktop.failNative(Linux.EIO)

            unreachable
        }

        defer Linux.free(pointer)
        let reply = context.xcb_get_image_reply(connection,
                                                context.xcb_get_image(connection, 2, context.screen.root, pointer.root_x, pointer.root_y, 1, 1, 0xFFFFFFFF),
                                                null)
        if not reply

        {
            expect LinuxDesktop.failNative(Linux.EIO)

            unreachable
        }

        defer Linux.free(reply)
        let setup   = context.xcb_get_setup(connection)
        var formats = context.xcb_setup_pixmap_formats_iterator(setup)
        var bits: u8
        while formats.rem > 0
        {
            let format = unwrap formats.data
            if format.depth == reply.depth
            {
                bits = format.bits_per_pixel
                break
            }

            context.xcb_format_next(&formats)
        }

        if bits != 16 and bits != 24 and bits != 32 do
            expect LinuxDesktop.failNative(Linux.ENOTSUP)
        let count = bits / 8
        if context.xcb_get_image_data_length(reply) < count do
            expect LinuxDesktop.failNative(Linux.EIO)
        let bytes = context.xcb_get_image_data(reply)
        var pixel: u32
        for index in count do
            pixel |= cast(u32, bytes[index]) << (setup.image_byte_order == 0 ? index * 8 : (count - 1 - index) * 8)
        var depths = context.xcb_screen_allowed_depths_iterator(unwrap context.screenPtr)
        while depths.rem > 0
        {
            let depth   = unwrap depths.data
            var visuals = context.xcb_depth_visuals_iterator(depth)
            while visuals.rem > 0
            {
                let visual = unwrap visuals.data
                if visual.visual_id == context.screen.root_visual
                {
                    if visual._class != 4 do
                        expect LinuxDesktop.failNative(Linux.ENOTSUP)

                    func channel(value, mask: u32)->u8
                    {
                        if mask == 0 do
                            return 0
                        var shifted = mask
                        var result  = value
                        while shifted & 1 == 0
                        {
                            shifted >>= 1
                            result  >>= 1
                        }

                        return cast(u8, ((result & shifted) * 255) / shifted)
                    }

                    return Color.fromRgb(channel(pixel, visual.red_mask), channel(pixel, visual.green_mask), channel(pixel, visual.blue_mask))
                }

                context.xcb_visualtype_next(&visuals)
            }

            context.xcb_depth_next(&depths)
        }

        expect LinuxDesktop.failNative(Linux.ENOTSUP)
        unreachable
    }

    private mtd dispatchNativeButton(surface: *Surface, packet: *Linux.xcb_button_press_event_t, pressed: bool)
    {
        var button: Input.MouseButton
        switch packet.detail
        {
        case 1:  button = .Left
        case 2:  button = .Middle
        case 3:  button = .Right
        case 8:  button = .XButton1
        case 9:  button = .XButton2
        default: return
        }

        let position = Math.Point{packet.root_x, packet.root_y}
        .mouse.setCurrentButtonState(button, pressed)
        .mouse.setPositions(.mouse.position(), position)
        if .dragEnterWnd do
            return
        var target = .mouseCaptureWnd orelse .windowAt(position) orelse surface.windowAt(position)
        target = skipDisabled(target)
        if not target do
            return
        var event = MouseEvent{kind: .Accept, surfacePos: target.screenToSurface(position)}
        event.target = target
        .sendEventPrivate(&event, .mouseEnterWnd)
        target = event.target
        if not target do
            return
        event.button = button
        if packet.state & 1 do
            event.modifiers |= .Shift
        if packet.state & 4 do
            event.modifiers |= .Control
        if packet.state & 8 do
            event.modifiers |= .Alt
        event.kind = pressed ? .Pressed : .Released
        if pressed
        {
            // X11 timestamps wrap at 32 bits; unsigned subtraction preserves short intervals.
            let delta = cast(u32, (cast(u64, packet.time) + 0x100000000 - .lastClickTime[button]) & 0xFFFFFFFF)
            if .lastClickTime[button] != 0 and
               delta < .mouse.doubleClickTimeMs and
               .lastClickPosition[button] == position
            {
                event.kind = .DoubleClick
                .lastClickTime[button] = 0
            }
            else
            {
                .lastClickTime[button]     = packet.time
                .lastClickPosition[button] = position
                .focusPointerTarget(target)
            }

            .toolTip.hide()
        }

        target.sendEvent(&event)
    }
}
