#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

private func(T) xcbTestSymbol(library: *void, name: string)->T
{
    let address = dlsym(library, name.buffer)
    Swag.assert(address != null)
    return cast(T, address)
}

#[Swag.TestTag("integration.xcb")]
#test
{
    let library = dlopen("libxcb.so.1".buffer, RTLD_NOW | RTLD_LOCAL)
    Swag.assert(library != null)
    defer discard dlclose(unwrap library)
    let connect    = xcbTestSymbol'xcb_connect_fn(library, "xcb_connect")
    let disconnect = xcbTestSymbol'xcb_disconnect_fn(library, "xcb_disconnect")
    let hasError   = xcbTestSymbol'xcb_connection_has_error_fn(library, "xcb_connection_has_error")
    let connection = connect("invalid-display-syntax".buffer, null)
    Swag.assert(connection != null)
    defer disconnect(unwrap connection)
    Swag.assert(hasError(connection) != 0)
}

// Requires an explicitly selected test tag and an isolated X11 display, such as Xvfb.
#[Swag.TestTag("integration.xcb")]
#test
{
    let library = dlopen("libxcb.so.1".buffer, RTLD_NOW | RTLD_LOCAL)
    Swag.assert(library != null)
    defer discard dlclose(unwrap library)
    let connect       = xcbTestSymbol'xcb_connect_fn(library, "xcb_connect")
    let disconnect    = xcbTestSymbol'xcb_disconnect_fn(library, "xcb_disconnect")
    let hasError      = xcbTestSymbol'xcb_connection_has_error_fn(library, "xcb_connection_has_error")
    let getSetup      = xcbTestSymbol'xcb_get_setup_fn(library, "xcb_get_setup")
    let roots         = xcbTestSymbol'xcb_setup_roots_iterator_fn(library, "xcb_setup_roots_iterator")
    let nextScreen    = xcbTestSymbol'xcb_screen_next_fn(library, "xcb_screen_next")
    let generateId    = xcbTestSymbol'xcb_generate_id_fn(library, "xcb_generate_id")
    let check         = xcbTestSymbol'xcb_request_check_fn(library, "xcb_request_check")
    let create        = xcbTestSymbol'xcb_create_window_checked_fn(library, "xcb_create_window_checked")
    let map           = xcbTestSymbol'xcb_map_window_checked_fn(library, "xcb_map_window_checked")
    let configure     = xcbTestSymbol'xcb_configure_window_checked_fn(library, "xcb_configure_window_checked")
    let destroy       = xcbTestSymbol'xcb_destroy_window_checked_fn(library, "xcb_destroy_window_checked")
    let pollEvent     = xcbTestSymbol'xcb_poll_for_event_fn(library, "xcb_poll_for_event")
    let geometry      = xcbTestSymbol'xcb_get_geometry_fn(library, "xcb_get_geometry")
    let geometryReply = xcbTestSymbol'xcb_get_geometry_reply_fn(library, "xcb_get_geometry_reply")
    var screenIndex: s32
    let connection    = connect(null, &screenIndex)
    Swag.assert(connection != null)
    defer disconnect(unwrap connection)
    Swag.assert(hasError(connection) == 0, "integration.xcb needs a reachable isolated DISPLAY")
    let setup = getSetup(connection)
    Swag.assert(setup.status == 1 and setup.roots_len != 0 and setup.min_keycode <= setup.max_keycode)
    var screens = roots(setup)
    for cast(u32, screenIndex) do
        nextScreen(&screens)
    Swag.assert(screens.rem > 0 and screens.data != null)
    let screen = screens.data
    Swag.assert(screen.width_in_pixels != 0 and screen.height_in_pixels != 0)
    let window          = generateId(connection)
    let values: [2] u32 = [screen.black_pixel, (1 << 15) | (1 << 17)]
    let created         = create(connection, screen.root_depth, window, screen.root, 10, 20, 80, 60, 0, 1, screen.root_visual, (1 << 1) | (1 << 11), &values)
    let createError     = check(connection, created)
    defer free(createError)
    Swag.assert(createError == null)
    var destroyed = false
    defer if not destroyed do
        free(check(unwrap connection, destroy(connection, window)))
    let internAtom     = xcbTestSymbol'xcb_intern_atom_fn(library, "xcb_intern_atom")
    let atomReply      = xcbTestSymbol'xcb_intern_atom_reply_fn(library, "xcb_intern_atom_reply")
    let changeProperty = xcbTestSymbol'xcb_change_property_checked_fn(library, "xcb_change_property_checked")
    let getProperty    = xcbTestSymbol'xcb_get_property_fn(library, "xcb_get_property")
    let propertyReply  = xcbTestSymbol'xcb_get_property_reply_fn(library, "xcb_get_property_reply")
    let propertyValue  = xcbTestSymbol'xcb_get_property_value_fn(library, "xcb_get_property_value")
    let propertyLength = xcbTestSymbol'xcb_get_property_value_length_fn(library, "xcb_get_property_value_length")
    var atomError: *xcb_generic_error_t?
    let atomName       = "_SWAG_XCB_TEST"
    let atom           = atomReply(connection, internAtom(connection, 0, cast(u16, atomName.count), atomName.buffer), &atomError)
    defer free(atomError)
    defer free(atom)
    Swag.assert(atom != null and atomError == null and atom.atom != 0)
    let text    = "éx"
    let changed = check(connection, changeProperty(connection, 0, window, atom.atom, 31, 8, cast(u32, text.count), text.buffer))
    defer free(changed)
    Swag.assert(changed == null)
    var propertyError: *xcb_generic_error_t?
    let property = propertyReply(connection, getProperty(connection, 0, window, atom.atom, 31, 0, 1), &propertyError)
    defer free(propertyError)
    defer free(property)
    Swag.assert(property != null and propertyError == null)
    Swag.assert(property.type == 31 and
                property.format == 8 and
                property.value_len == text.count and
                property.bytes_after == 0)
    Swag.assert(propertyLength(property) == cast(s32, text.count))
    let propertyBytes = cast([*] u8, propertyValue(property))
    Swag.assert(cast(string, Swag.makeSlice(propertyBytes, text.count)) == text)

    let mapError = check(connection, map(connection, window))
    defer free(mapError)
    Swag.assert(mapError == null)
    let size: [2] u32 = [120, 90]
    let resizeError   = check(connection, configure(connection, window, (1 << 2) | (1 << 3), &size))
    defer free(resizeError)
    Swag.assert(resizeError == null)
    var replyError: *xcb_generic_error_t?
    let reply = geometryReply(connection, geometry(connection, window), &replyError)
    defer free(replyError)
    defer free(reply)
    Swag.assert(reply != null and replyError == null)
    Swag.assert(reply.width == 120 and reply.height == 90 and reply.root == screen.root)
    var exposed, resized: bool
    for
    {
        let event = pollEvent(connection)
        if not event do
            break
        defer free(event)
        let kind = event.response_type & 0x7F
        if kind == 12
        {
            let expose = cast(*xcb_expose_event_t, cast(*void, event))
            exposed = exposed or expose.window == window
        }
        elif kind == 22
        {
            let resize = cast(*xcb_configure_notify_event_t, cast(*void, event))
            resized = resized or (resize.window == window and resize.width == 120 and resize.height == 90)
        }

        Swag.assert(kind != 0)
    }

    Swag.assert(exposed and resized)

    // SendEvent marks the response bit but preserves signed coordinates and input state.
    // Focus packets have a smaller C view; the request still reads a full 32-byte wire event.
    let send = xcbTestSymbol'xcb_send_event_checked_fn(library, "xcb_send_event_checked")
    for kind in [XCB_KEY_PRESS, XCB_KEY_RELEASE, XCB_BUTTON_PRESS, XCB_BUTTON_RELEASE,
                 XCB_MOTION_NOTIFY, XCB_ENTER_NOTIFY, XCB_LEAVE_NOTIFY, XCB_FOCUS_IN, XCB_FOCUS_OUT]
    {
        var storage: [8]u32
        let bytes = cast([*]u8, &storage)
        if kind == XCB_FOCUS_IN or kind == XCB_FOCUS_OUT
        {
            let focus = cast(*xcb_focus_in_event_t, cast(*void, bytes))
            focus.response_type = kind
            focus.event         = window
            focus.detail        = 3
            focus.mode          = 1
        }
        else
        {
            let input = cast(*xcb_key_press_event_t, cast(*void, bytes))
            input.response_type = kind
            input.detail        = 38
            input.time          = 0x12345678
            input.root          = screen.root
            input.event         = window
            input.root_x        = -321
            input.root_y        = 456
            input.event_x       = -123
            input.event_y       = 234
            input.state         = 0x104
            input.same_screen   = 1
            if kind == XCB_ENTER_NOTIFY or kind == XCB_LEAVE_NOTIFY
            {
                let crossing = cast(*xcb_enter_notify_event_t, cast(*void, bytes))
                crossing.mode              = 2
                crossing.same_screen_focus = 3
            }
        }

        let sendError = check(connection, send(connection, 0, window, 0, bytes))
        defer free(sendError)
        Swag.assert(sendError == null)
        let event = pollEvent(connection)
        Swag.assert(event != null)
        defer free(event)
        Swag.assert(event.response_type == (kind | 0x80))
        let received = cast([*]u8, event)
        // X11 replaces the sequence field, but none of the input payload.
        Swag.assert(received[1] == bytes[1])
        for index in 4 until 32 do
            Swag.assert(received[index] == bytes[index])
    }
    let destroyError = check(connection, destroy(connection, window))
    defer free(destroyError)
    Swag.assert(destroyError == null)
    destroyed = true
    let badWindow = check(connection, destroy(connection, window))
    defer free(badWindow)
    Swag.assert(badWindow != null)
    Swag.assert(badWindow.error_code == 3 and badWindow.resource_id == window and badWindow.major_code == 4)
    Swag.assert(hasError(connection) == 0)
}

#[Swag.TestTag("integration.xcb")]
#test
{
    let library = dlopen("libxcb.so.1".buffer, RTLD_NOW | RTLD_LOCAL)
    Swag.assert(library != null)
    defer discard dlclose(unwrap library)
    let connect      = xcbTestSymbol'xcb_connect_fn(library, "xcb_connect")
    let disconnect   = xcbTestSymbol'xcb_disconnect_fn(library, "xcb_disconnect")
    let hasError     = xcbTestSymbol'xcb_connection_has_error_fn(library, "xcb_connection_has_error")
    let getSetup     = xcbTestSymbol'xcb_get_setup_fn(library, "xcb_get_setup")
    let roots        = xcbTestSymbol'xcb_setup_roots_iterator_fn(library, "xcb_setup_roots_iterator")
    let keymap       = xcbTestSymbol'xcb_query_keymap_fn(library, "xcb_query_keymap")
    let keymapReply  = xcbTestSymbol'xcb_query_keymap_reply_fn(library, "xcb_query_keymap_reply")
    let mapping      = xcbTestSymbol'xcb_get_keyboard_mapping_fn(library, "xcb_get_keyboard_mapping")
    let mappingReply = xcbTestSymbol'xcb_get_keyboard_mapping_reply_fn(library, "xcb_get_keyboard_mapping_reply")
    let keysyms      = xcbTestSymbol'xcb_get_keyboard_mapping_keysyms_fn(library, "xcb_get_keyboard_mapping_keysyms")
    let keysymsCount = xcbTestSymbol'xcb_get_keyboard_mapping_keysyms_length_fn(library, "xcb_get_keyboard_mapping_keysyms_length")
    let queryPointer = xcbTestSymbol'xcb_query_pointer_fn(library, "xcb_query_pointer")
    let pointerReply = xcbTestSymbol'xcb_query_pointer_reply_fn(library, "xcb_query_pointer_reply")
    let connection   = connect(null, null)
    Swag.assert(connection != null)
    defer disconnect(unwrap connection)
    Swag.assert(hasError(connection) == 0)
    let setup   = getSetup(connection)
    let screens = roots(setup)
    Swag.assert(screens.rem > 0 and screens.data != null)
    let screen   = screens.data
    var keyboardError: *xcb_generic_error_t?
    let keyboard = keymapReply(connection, keymap(connection), &keyboardError)
    defer free(keyboard)
    defer free(keyboardError)
    Swag.assert(keyboard != null and keyboardError == null and keyboard.length == 2)
    let count   = cast(u8, cast(u32, setup.max_keycode) - setup.min_keycode + 1)
    var mappingError: *xcb_generic_error_t?
    let symbols = mappingReply(connection, mapping(connection, setup.min_keycode, count), &mappingError)
    defer free(symbols)
    defer free(mappingError)
    Swag.assert(symbols != null and mappingError == null and symbols.keysyms_per_keycode != 0)
    Swag.assert(keysymsCount(symbols) == cast(s32, count) * symbols.keysyms_per_keycode)
    var foundLetter = false
    let values      = keysyms(symbols)
    for index in cast(u32, keysymsCount(symbols)) where values[index] == 'a' do
        foundLetter = true
    Swag.assert(foundLetter)
    var pointerError: *xcb_generic_error_t?
    let pointer = pointerReply(connection, queryPointer(connection, screen.root), &pointerError)
    defer free(pointer)
    defer free(pointerError)
    Swag.assert(pointer != null and
                pointerError == null and
                pointer.same_screen == 1 and
                pointer.root == screen.root)

    let randrLibrary = dlopen("libxcb-randr.so.0".buffer, RTLD_NOW | RTLD_LOCAL)
    Swag.assert(randrLibrary != null)
    defer discard dlclose(unwrap randrLibrary)
    let version       = xcbTestSymbol'xcb_randr_query_version_fn(randrLibrary, "xcb_randr_query_version")
    let versionReply  = xcbTestSymbol'xcb_randr_query_version_reply_fn(randrLibrary, "xcb_randr_query_version_reply")
    let monitors      = xcbTestSymbol'xcb_randr_get_monitors_fn(randrLibrary, "xcb_randr_get_monitors")
    let monitorsReply = xcbTestSymbol'xcb_randr_get_monitors_reply_fn(randrLibrary, "xcb_randr_get_monitors_reply")
    let iterate       = xcbTestSymbol'xcb_randr_get_monitors_monitors_iterator_fn(randrLibrary, "xcb_randr_get_monitors_monitors_iterator")
    let next          = xcbTestSymbol'xcb_randr_monitor_info_next_fn(randrLibrary, "xcb_randr_monitor_info_next")
    var versionError: *xcb_generic_error_t?
    let negotiated    = versionReply(connection, version(connection, 1, 5), &versionError)
    defer free(negotiated)
    defer free(versionError)
    Swag.assert(negotiated != null and versionError == null)
    Swag.assert(negotiated.major_version == 1 and negotiated.minor_version >= 5)
    var monitorError: *xcb_generic_error_t?
    let reply = monitorsReply(connection, monitors(connection, screen.root, 1), &monitorError)
    defer free(reply)
    defer free(monitorError)
    Swag.assert(reply != null and monitorError == null and reply.nMonitors != 0)
    var iterator = iterate(reply)
    var seen     = 0'u32
    while iterator.rem > 0
    {
        let info = unwrap iterator.data
        Swag.assert(info.width != 0 and info.height != 0)
        seen += 1
        next(&iterator)
    }

    Swag.assert(seen == reply.nMonitors)
}
