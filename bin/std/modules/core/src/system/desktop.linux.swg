#global if #os == Swag.TargetOs.Linux
#global namespace LinuxDesktop

// No display connection or desktop library is acquired by console-only Core consumers.
internal struct Context
{
    internal
    {
        libraryXfixes:                           *void?
        cursorReady:                             bool
        cursorBalance:                           s64
        xcb_xfixes_hide_cursor_checked:          Linux.xcb_xfixes_hide_cursor_checked_fn
        xcb_xfixes_show_cursor_checked:          Linux.xcb_xfixes_show_cursor_checked_fn
        screenIndex:                             s32
        libraryRandr:                            *void?
        library:                                 *void?
        connection:                              *void?
        screen:                                  Linux.xcb_screen_t
        uiThread:                                u64
        windows:                                 *WindowState?
        stopRequested:                           bool
        xcb_connect:                             Linux.xcb_connect_fn
        xcb_disconnect:                          Linux.xcb_disconnect_fn
        xcb_connection_has_error:                Linux.xcb_connection_has_error_fn
        xcb_get_extension_data:                  Linux.xcb_get_extension_data_fn
        xcb_get_setup:                           Linux.xcb_get_setup_fn
        xcb_setup_roots_iterator:                Linux.xcb_setup_roots_iterator_fn
        xcb_screen_next:                         Linux.xcb_screen_next_fn
        xcb_generate_id:                         Linux.xcb_generate_id_fn
        xcb_request_check:                       Linux.xcb_request_check_fn
        xcb_flush:                               Linux.xcb_flush_fn
        xcb_poll_for_event:                      Linux.xcb_poll_for_event_fn
        xcb_create_window_checked:               Linux.xcb_create_window_checked_fn
        xcb_destroy_window_checked:              Linux.xcb_destroy_window_checked_fn
        xcb_map_window_checked:                  Linux.xcb_map_window_checked_fn
        xcb_unmap_window_checked:                Linux.xcb_unmap_window_checked_fn
        xcb_configure_window_checked:            Linux.xcb_configure_window_checked_fn
        xcb_change_window_attributes_checked:    Linux.xcb_change_window_attributes_checked_fn
        xcb_change_property_checked:             Linux.xcb_change_property_checked_fn
        xcb_intern_atom:                         Linux.xcb_intern_atom_fn
        xcb_intern_atom_reply:                   Linux.xcb_intern_atom_reply_fn
        xcb_get_geometry:                        Linux.xcb_get_geometry_fn
        xcb_get_geometry_reply:                  Linux.xcb_get_geometry_reply_fn
        xcb_get_property:                        Linux.xcb_get_property_fn
        xcb_get_property_reply:                  Linux.xcb_get_property_reply_fn
        xcb_get_property_value:                  Linux.xcb_get_property_value_fn
        xcb_get_property_value_length:           Linux.xcb_get_property_value_length_fn
        xcb_query_pointer:                       Linux.xcb_query_pointer_fn
        xcb_query_pointer_reply:                 Linux.xcb_query_pointer_reply_fn
        xcb_query_keymap:                        Linux.xcb_query_keymap_fn
        xcb_query_keymap_reply:                  Linux.xcb_query_keymap_reply_fn
        xcb_get_keyboard_mapping:                Linux.xcb_get_keyboard_mapping_fn
        xcb_get_keyboard_mapping_reply:          Linux.xcb_get_keyboard_mapping_reply_fn
        xcb_get_keyboard_mapping_keysyms:        Linux.xcb_get_keyboard_mapping_keysyms_fn
        xcb_get_keyboard_mapping_keysyms_length: Linux.xcb_get_keyboard_mapping_keysyms_length_fn
        xcb_warp_pointer_checked:                Linux.xcb_warp_pointer_checked_fn
        xcb_clear_area_checked:                  Linux.xcb_clear_area_checked_fn
        xcb_send_event_checked:                  Linux.xcb_send_event_checked_fn
        xcb_set_input_focus_checked:             Linux.xcb_set_input_focus_checked_fn
    }
}

internal struct WindowState
{
    internal
    {
        next:            *WindowState?
        owner:           *Env.Window?
        context:         *Context?
        id:              u32
        drawable:        Env.XcbDrawable
        deleteAtom:      u32
        protocolsAtom:   u32
        resizable:       bool
        stopLoopOnClose: bool
    }
}

private var g_Context:      *Context?
private var g_ContextMutex: Swag.Mutex
private var g_Stopping:     bool

internal func(T) symbol(library: *void, name: string)->T fail
{
    // All symbol names are zero-terminated literals at this private boundary.
    let address = Linux.dlsym(library, name.buffer)
    if not address do
        fail Swag.SystemError{"required XCB symbol is unavailable"}
    return cast(T, address)
}

internal func ensure()->*Context fail
{
    g_ContextMutex.lock()
    defer g_ContextMutex.unlock()
    if g_Stopping do
        fail Swag.SystemError{"desktop services have shut down"}
    if g_Context
    {
        let state = unwrap g_Context
        if state.xcb_connection_has_error(unwrap state.connection) != 0 do
            fail Swag.SystemError{"X11 display connection was lost"}
        return state
    }

    let library = Linux.dlopen("libxcb.so.1".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
    if not library do
        fail Swag.SystemError{"cannot load libxcb.so.1"}
    defer #fail discard Linux.dlclose(unwrap library)
    let allocation = Linux.calloc(1, #sizeof(Context))
    if not allocation do
        try Errors.failLinuxError(Linux.ENOMEM)
    let state = cast(*Context, unwrap allocation)
    defer #fail Linux.free(state)
    state.library                                 = library
    state.xcb_connect                             = try symbol'Linux.xcb_connect_fn(library, "xcb_connect")
    state.xcb_disconnect                          = try symbol'Linux.xcb_disconnect_fn(library, "xcb_disconnect")
    state.xcb_connection_has_error                = try symbol'Linux.xcb_connection_has_error_fn(library, "xcb_connection_has_error")
    state.xcb_get_extension_data                  = try symbol'Linux.xcb_get_extension_data_fn(library, "xcb_get_extension_data")
    state.xcb_get_setup                           = try symbol'Linux.xcb_get_setup_fn(library, "xcb_get_setup")
    state.xcb_setup_roots_iterator                = try symbol'Linux.xcb_setup_roots_iterator_fn(library, "xcb_setup_roots_iterator")
    state.xcb_screen_next                         = try symbol'Linux.xcb_screen_next_fn(library, "xcb_screen_next")
    state.xcb_generate_id                         = try symbol'Linux.xcb_generate_id_fn(library, "xcb_generate_id")
    state.xcb_request_check                       = try symbol'Linux.xcb_request_check_fn(library, "xcb_request_check")
    state.xcb_flush                               = try symbol'Linux.xcb_flush_fn(library, "xcb_flush")
    state.xcb_poll_for_event                      = try symbol'Linux.xcb_poll_for_event_fn(library, "xcb_poll_for_event")
    state.xcb_create_window_checked               = try symbol'Linux.xcb_create_window_checked_fn(library, "xcb_create_window_checked")
    state.xcb_destroy_window_checked              = try symbol'Linux.xcb_destroy_window_checked_fn(library, "xcb_destroy_window_checked")
    state.xcb_map_window_checked                  = try symbol'Linux.xcb_map_window_checked_fn(library, "xcb_map_window_checked")
    state.xcb_unmap_window_checked                = try symbol'Linux.xcb_unmap_window_checked_fn(library, "xcb_unmap_window_checked")
    state.xcb_configure_window_checked            = try symbol'Linux.xcb_configure_window_checked_fn(library, "xcb_configure_window_checked")
    state.xcb_change_window_attributes_checked    = try symbol'Linux.xcb_change_window_attributes_checked_fn(library, "xcb_change_window_attributes_checked")
    state.xcb_change_property_checked             = try symbol'Linux.xcb_change_property_checked_fn(library, "xcb_change_property_checked")
    state.xcb_intern_atom                         = try symbol'Linux.xcb_intern_atom_fn(library, "xcb_intern_atom")
    state.xcb_intern_atom_reply                   = try symbol'Linux.xcb_intern_atom_reply_fn(library, "xcb_intern_atom_reply")
    state.xcb_get_geometry                        = try symbol'Linux.xcb_get_geometry_fn(library, "xcb_get_geometry")
    state.xcb_get_geometry_reply                  = try symbol'Linux.xcb_get_geometry_reply_fn(library, "xcb_get_geometry_reply")
    state.xcb_get_property                        = try symbol'Linux.xcb_get_property_fn(library, "xcb_get_property")
    state.xcb_get_property_reply                  = try symbol'Linux.xcb_get_property_reply_fn(library, "xcb_get_property_reply")
    state.xcb_get_property_value                  = try symbol'Linux.xcb_get_property_value_fn(library, "xcb_get_property_value")
    state.xcb_get_property_value_length           = try symbol'Linux.xcb_get_property_value_length_fn(library, "xcb_get_property_value_length")
    state.xcb_query_pointer                       = try symbol'Linux.xcb_query_pointer_fn(library, "xcb_query_pointer")
    state.xcb_query_pointer_reply                 = try symbol'Linux.xcb_query_pointer_reply_fn(library, "xcb_query_pointer_reply")
    state.xcb_query_keymap                        = try symbol'Linux.xcb_query_keymap_fn(library, "xcb_query_keymap")
    state.xcb_query_keymap_reply                  = try symbol'Linux.xcb_query_keymap_reply_fn(library, "xcb_query_keymap_reply")
    state.xcb_get_keyboard_mapping                = try symbol'Linux.xcb_get_keyboard_mapping_fn(library, "xcb_get_keyboard_mapping")
    state.xcb_get_keyboard_mapping_reply          = try symbol'Linux.xcb_get_keyboard_mapping_reply_fn(library, "xcb_get_keyboard_mapping_reply")
    state.xcb_get_keyboard_mapping_keysyms        = try symbol'Linux.xcb_get_keyboard_mapping_keysyms_fn(library, "xcb_get_keyboard_mapping_keysyms")
    state.xcb_get_keyboard_mapping_keysyms_length = try symbol'Linux.xcb_get_keyboard_mapping_keysyms_length_fn(library, "xcb_get_keyboard_mapping_keysyms_length")
    state.xcb_warp_pointer_checked                = try symbol'Linux.xcb_warp_pointer_checked_fn(library, "xcb_warp_pointer_checked")
    state.xcb_clear_area_checked                  = try symbol'Linux.xcb_clear_area_checked_fn(library, "xcb_clear_area_checked")
    state.xcb_send_event_checked                  = try symbol'Linux.xcb_send_event_checked_fn(library, "xcb_send_event_checked")
    state.xcb_set_input_focus_checked             = try symbol'Linux.xcb_set_input_focus_checked_fn(library, "xcb_set_input_focus_checked")
    var screenIndex: s32
    let connection = state.xcb_connect(null, &screenIndex)
    if not connection do
        fail Swag.SystemError{"cannot allocate an X11 connection"}
    defer #fail state.xcb_disconnect(unwrap connection)
    if state.xcb_connection_has_error(connection) != 0 do
        fail Swag.SystemError{"cannot connect to the X11 display selected by DISPLAY"}
    state.screenIndex = screenIndex
    let setup   = state.xcb_get_setup(connection)
    var screens = state.xcb_setup_roots_iterator(setup)
    while screenIndex > 0 and screens.rem > 0
    {
        state.xcb_screen_next(&screens)
        screenIndex -= 1
    }

    if screens.rem <= 0 or not screens.data do
        fail Swag.SystemError{"X11 display has no selected screen"}
    state.screen     = screens.data[]
    state.connection = connection
    g_Context        = state
    return state
}

internal func check(state: *Context, cookie: Linux.xcb_void_cookie_t) fail
{
    let error = state.xcb_request_check(unwrap state.connection, cookie)
    if error
    {
        let code = error.error_code
        Linux.free(error)
        fail Swag.SystemError{"X11 protocol request failed", errorID: code}
    }

    if state.xcb_connection_has_error(state.connection) != 0 do
        fail Swag.SystemError{"X11 display connection was lost"}
}

// XCB assigns extension-cache identities to library-owned descriptors. Keep an acquired
// extension library loaded for the whole connection lifetime instead of reopening it per query.
internal func randrLibrary(state: *Context)->*void?
{
    g_ContextMutex.lock()
    defer g_ContextMutex.unlock()
    if not state.libraryRandr do
        state.libraryRandr = Linux.dlopen("libxcb-randr.so.0".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
    return state.libraryRandr
}

// Sending an extension opcode before checking presence can close the whole XCB connection.
internal func hasExtension(state: *Context, library: *void, descriptor: string)->bool
{
    let address = Linux.dlsym(library, descriptor.buffer)
    if not address do
        return false
    let reply = state.xcb_get_extension_data(unwrap state.connection, cast(*Linux.xcb_extension_t, address))
    return reply != null and reply.present != 0
}

internal func requireUiThread(state: *Context) fail
{
    g_ContextMutex.lock()
    defer g_ContextMutex.unlock()
    let thread = Env.Process.currentThreadId()
    if state.uiThread == 0 do
        state.uiThread = thread
    elif state.uiThread != thread do
        fail Errors.BadParameterError{"window operations require their creating thread"}
}

internal func atom(state: *Context, name: string)->u32 fail
{
    var error: *Linux.xcb_generic_error_t?
    let reply = state.xcb_intern_atom_reply(unwrap state.connection,
                                            state.xcb_intern_atom(state.connection, 0, cast(u16, name.count), name.buffer),
                                            &error)
    defer if error do
        Linux.free(error)
    defer if reply do
        Linux.free(reply)
    if error or not reply do
        fail Swag.SystemError{"cannot resolve an X11 property atom"}
    return reply.atom
}

#init
{
    g_ContextMutex.lock()
    if not g_Context do
        g_Stopping = false
    g_ContextMutex.unlock()
}

#drop
{
    // All application threads must stop using Core before module unloading.
    g_ContextMutex.lock()
    defer g_ContextMutex.unlock()
    g_Stopping = true
    if g_Context
    {
        let state = unwrap g_Context
        while state.windows
        {
            let window = state.windows
            state.windows = window.next
            if window.owner do
                window.owner.nativeHandle = null
            Linux.free(window)
        }

        state.xcb_disconnect(unwrap state.connection)
        if state.libraryXfixes do
            discard Linux.dlclose(state.libraryXfixes)
        if state.libraryRandr do
            discard Linux.dlclose(state.libraryRandr)
        discard Linux.dlclose(unwrap state.library)
        Linux.free(state)
        g_Context = null
    }
}
