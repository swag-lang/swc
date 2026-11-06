#global if #os == Swag.TargetOs.Linux
#global namespace LinuxDesktop

using Core

// One GUI event connection belongs to its creating thread. Core desktop services and clipboard
// selection transfers use separate connections, so each pump owns every event it consumes.
internal struct Context
{
    library:                                      *void?
    connection:                                   *void?
    screen:                                       Linux.xcb_screen_t
    screenPtr:                                    const *Linux.xcb_screen_t?
    atoms:                                        HashTable'(String, u32)
    settingsOwner:                                u32
    screenIndex:                                  s32
    uiThread:                                     u64
    wslDpiScale:                                  f32 = 1
    wslDpiResolved:                               bool
    surfaces:                                     Array'(*Surface)
    cursorFont:                                   u32
    cursors:                                      [CursorShape]u32
    currentCursor:                                CursorShape = .Arrow
    pointerCapture:                               *Surface?
    pendingEvent:                                 *Linux.xcb_generic_event_t?
    keyboardLibrary:                              *void?
    keyboardX11Library:                           *void?
    keyboardContext:                              *void?
    keyboardMap:                                  *void?
    keyboardState:                                *void?
    composeTable:                                 *void?
    late xcb_connect:                             Linux.xcb_connect_fn
    late xcb_disconnect:                          Linux.xcb_disconnect_fn
    late xcb_connection_has_error:                Linux.xcb_connection_has_error_fn
    late xcb_get_setup:                           Linux.xcb_get_setup_fn
    late xcb_setup_roots_iterator:                Linux.xcb_setup_roots_iterator_fn
    late xcb_screen_next:                         Linux.xcb_screen_next_fn
    late xcb_generate_id:                         Linux.xcb_generate_id_fn
    late xcb_request_check:                       Linux.xcb_request_check_fn
    late xcb_flush:                               Linux.xcb_flush_fn
    late xcb_poll_for_event:                      Linux.xcb_poll_for_event_fn
    late xcb_create_window_checked:               Linux.xcb_create_window_checked_fn
    late xcb_destroy_window_checked:              Linux.xcb_destroy_window_checked_fn
    late xcb_map_window_checked:                  Linux.xcb_map_window_checked_fn
    late xcb_unmap_window_checked:                Linux.xcb_unmap_window_checked_fn
    late xcb_configure_window_checked:            Linux.xcb_configure_window_checked_fn
    late xcb_change_window_attributes_checked:    Linux.xcb_change_window_attributes_checked_fn
    late xcb_change_property_checked:             Linux.xcb_change_property_checked_fn
    late xcb_intern_atom:                         Linux.xcb_intern_atom_fn
    late xcb_intern_atom_reply:                   Linux.xcb_intern_atom_reply_fn
    late xcb_get_geometry:                        Linux.xcb_get_geometry_fn
    late xcb_get_geometry_reply:                  Linux.xcb_get_geometry_reply_fn
    late xcb_get_property:                        Linux.xcb_get_property_fn
    late xcb_get_property_reply:                  Linux.xcb_get_property_reply_fn
    late xcb_get_property_value:                  Linux.xcb_get_property_value_fn
    late xcb_get_property_value_length:           Linux.xcb_get_property_value_length_fn
    late xcb_query_pointer:                       Linux.xcb_query_pointer_fn
    late xcb_query_pointer_reply:                 Linux.xcb_query_pointer_reply_fn
    late xcb_get_keyboard_mapping:                Linux.xcb_get_keyboard_mapping_fn
    late xcb_get_keyboard_mapping_reply:          Linux.xcb_get_keyboard_mapping_reply_fn
    late xcb_get_keyboard_mapping_keysyms:        Linux.xcb_get_keyboard_mapping_keysyms_fn
    late xcb_get_keyboard_mapping_keysyms_length: Linux.xcb_get_keyboard_mapping_keysyms_length_fn
    late xcb_send_event_checked:                  Linux.xcb_send_event_checked_fn
    late xcb_set_input_focus_checked:             Linux.xcb_set_input_focus_checked_fn
    late xcb_get_file_descriptor:                 Linux.xcb_get_file_descriptor_fn
    late xcb_translate_coordinates:               Linux.xcb_translate_coordinates_fn
    late xcb_translate_coordinates_reply:         Linux.xcb_translate_coordinates_reply_fn
    late xcb_query_tree:                          Linux.xcb_query_tree_fn
    late xcb_query_tree_reply:                    Linux.xcb_query_tree_reply_fn
    late xcb_query_tree_children:                 Linux.xcb_query_tree_children_fn
    late xcb_query_tree_children_length:          Linux.xcb_query_tree_children_length_fn
    late xcb_get_window_attributes:               Linux.xcb_get_window_attributes_fn
    late xcb_get_window_attributes_reply:         Linux.xcb_get_window_attributes_reply_fn
    late xcb_screen_allowed_depths_iterator:      Linux.xcb_screen_allowed_depths_iterator_fn
    late xcb_depth_next:                          Linux.xcb_depth_next_fn
    late xcb_depth_visuals_iterator:              Linux.xcb_depth_visuals_iterator_fn
    late xcb_visualtype_next:                     Linux.xcb_visualtype_next_fn
    late xcb_create_colormap_checked:             Linux.xcb_create_colormap_checked_fn
    late xcb_free_colormap_checked:               Linux.xcb_free_colormap_checked_fn
    late xcb_open_font_checked:                   Linux.xcb_open_font_checked_fn
    late xcb_close_font_checked:                  Linux.xcb_close_font_checked_fn
    late xcb_create_glyph_cursor_checked:         Linux.xcb_create_glyph_cursor_checked_fn
    late xcb_free_cursor_checked:                 Linux.xcb_free_cursor_checked_fn
    late xcb_grab_pointer:                        Linux.xcb_grab_pointer_fn
    late xcb_grab_pointer_reply:                  Linux.xcb_grab_pointer_reply_fn
    late xcb_ungrab_pointer_checked:              Linux.xcb_ungrab_pointer_checked_fn
    late xcb_grab_key_checked:                    Linux.xcb_grab_key_checked_fn
    late xcb_ungrab_key_checked:                  Linux.xcb_ungrab_key_checked_fn
    late xkb_context_new:                         Linux.xkb_context_new_fn
    late xkb_context_unref:                       Linux.xkb_context_unref_fn
    late xkb_keymap_unref:                        Linux.xkb_keymap_unref_fn
    late xkb_state_unref:                         Linux.xkb_state_unref_fn
    late xkb_state_update_mask:                   Linux.xkb_state_update_mask_fn
    late xkb_state_key_get_one_sym:               Linux.xkb_state_key_get_one_sym_fn
    late xkb_keymap_key_get_syms_by_level:        Linux.xkb_keymap_key_get_syms_by_level_fn
    late xkb_keysym_to_utf32:                     Linux.xkb_keysym_to_utf32_fn
    late xkb_compose_table_new_from_locale:       Linux.xkb_compose_table_new_from_locale_fn
    late xkb_compose_table_unref:                 Linux.xkb_compose_table_unref_fn
    late xkb_compose_state_new:                   Linux.xkb_compose_state_new_fn
    late xkb_compose_state_unref:                 Linux.xkb_compose_state_unref_fn
    late xkb_compose_state_feed:                  Linux.xkb_compose_state_feed_fn
    late xkb_compose_state_get_status:            Linux.xkb_compose_state_get_status_fn
    late xkb_compose_state_get_utf8:              Linux.xkb_compose_state_get_utf8_fn
    late xkb_compose_state_reset:                 Linux.xkb_compose_state_reset_fn
    late xkb_x11_setup_xkb_extension:             Linux.xkb_x11_setup_xkb_extension_fn
    late xkb_x11_get_core_keyboard_device_id:     Linux.xkb_x11_get_core_keyboard_device_id_fn
    late xkb_x11_keymap_new_from_device:          Linux.xkb_x11_keymap_new_from_device_fn
    late xkb_x11_state_new_from_device:           Linux.xkb_x11_state_new_from_device_fn
    late xcb_create_gc_checked:                   Linux.xcb_create_gc_checked_fn
    late xcb_free_gc_checked:                     Linux.xcb_free_gc_checked_fn
    late xcb_put_image_checked:                   Linux.xcb_put_image_checked_fn
    late xcb_get_selection_owner:                 Linux.xcb_get_selection_owner_fn
    late xcb_get_selection_owner_reply:           Linux.xcb_get_selection_owner_reply_fn
    late xcb_get_image:                           Linux.xcb_get_image_fn
    late xcb_get_image_reply:                     Linux.xcb_get_image_reply_fn
    late xcb_get_image_data:                      Linux.xcb_get_image_data_fn
    late xcb_get_image_data_length:               Linux.xcb_get_image_data_length_fn
    late xcb_setup_pixmap_formats_iterator:       Linux.xcb_setup_pixmap_formats_iterator_fn
    late xcb_format_next:                         Linux.xcb_format_next_fn
}

private var g_Context: *Context?

internal func(T) symbol(library: *void, name: string)->T fail
{
    let result = Linux.dlsym(library, name.buffer)
    if not result do
        fail Swag.SystemError{"required native desktop function is unavailable"}
    return cast(T, result)
}

internal func check(context: *Context, cookie: Linux.xcb_void_cookie_t) fail
{
    let connection = unwrap context.connection
    let error      = context.xcb_request_check(connection, cookie)
    if error
    {
        let code = error.error_code
        Linux.free(error)
        fail Swag.SystemError{"X11 GUI request failed", errorID: code}
    }

    if context.xcb_connection_has_error(connection) != 0 do
        fail Swag.SystemError{"X11 GUI display connection was lost"}
}

internal func ensure()->*Context fail
{
    if g_Context
    {
        let result = unwrap g_Context
        if result.uiThread != Env.Process.currentThreadId() do
            fail Errors.BadParameterError{"GUI windows require their creating thread"}
        if result.xcb_connection_has_error(unwrap result.connection) != 0 do
            fail Swag.SystemError{"X11 GUI display connection was lost"}
        return result
    }

    let result = Memory.new'Context()
    var ready: bool
    defer if not ready
    {
        if result.connection do
            result.xcb_disconnect(result.connection)
        if result.library do
            discard Linux.dlclose(result.library)
        Memory.delete(result)
    }

    result.library = Linux.dlopen("libxcb.so.1".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
    if not result.library do
        fail Swag.SystemError{"cannot load libxcb.so.1"}
    let library = result.library
    result.xcb_connect                             = try symbol'Linux.xcb_connect_fn(library, "xcb_connect")
    result.xcb_disconnect                          = try symbol'Linux.xcb_disconnect_fn(library, "xcb_disconnect")
    result.xcb_connection_has_error                = try symbol'Linux.xcb_connection_has_error_fn(library, "xcb_connection_has_error")
    result.xcb_get_setup                           = try symbol'Linux.xcb_get_setup_fn(library, "xcb_get_setup")
    result.xcb_setup_roots_iterator                = try symbol'Linux.xcb_setup_roots_iterator_fn(library, "xcb_setup_roots_iterator")
    result.xcb_screen_next                         = try symbol'Linux.xcb_screen_next_fn(library, "xcb_screen_next")
    result.xcb_generate_id                         = try symbol'Linux.xcb_generate_id_fn(library, "xcb_generate_id")
    result.xcb_request_check                       = try symbol'Linux.xcb_request_check_fn(library, "xcb_request_check")
    result.xcb_flush                               = try symbol'Linux.xcb_flush_fn(library, "xcb_flush")
    result.xcb_poll_for_event                      = try symbol'Linux.xcb_poll_for_event_fn(library, "xcb_poll_for_event")
    result.xcb_create_window_checked               = try symbol'Linux.xcb_create_window_checked_fn(library, "xcb_create_window_checked")
    result.xcb_destroy_window_checked              = try symbol'Linux.xcb_destroy_window_checked_fn(library, "xcb_destroy_window_checked")
    result.xcb_map_window_checked                  = try symbol'Linux.xcb_map_window_checked_fn(library, "xcb_map_window_checked")
    result.xcb_unmap_window_checked                = try symbol'Linux.xcb_unmap_window_checked_fn(library, "xcb_unmap_window_checked")
    result.xcb_configure_window_checked            = try symbol'Linux.xcb_configure_window_checked_fn(library, "xcb_configure_window_checked")
    result.xcb_change_window_attributes_checked    = try symbol'Linux.xcb_change_window_attributes_checked_fn(library, "xcb_change_window_attributes_checked")
    result.xcb_change_property_checked             = try symbol'Linux.xcb_change_property_checked_fn(library, "xcb_change_property_checked")
    result.xcb_intern_atom                         = try symbol'Linux.xcb_intern_atom_fn(library, "xcb_intern_atom")
    result.xcb_intern_atom_reply                   = try symbol'Linux.xcb_intern_atom_reply_fn(library, "xcb_intern_atom_reply")
    result.xcb_get_geometry                        = try symbol'Linux.xcb_get_geometry_fn(library, "xcb_get_geometry")
    result.xcb_get_geometry_reply                  = try symbol'Linux.xcb_get_geometry_reply_fn(library, "xcb_get_geometry_reply")
    result.xcb_get_property                        = try symbol'Linux.xcb_get_property_fn(library, "xcb_get_property")
    result.xcb_get_property_reply                  = try symbol'Linux.xcb_get_property_reply_fn(library, "xcb_get_property_reply")
    result.xcb_get_property_value                  = try symbol'Linux.xcb_get_property_value_fn(library, "xcb_get_property_value")
    result.xcb_get_property_value_length           = try symbol'Linux.xcb_get_property_value_length_fn(library, "xcb_get_property_value_length")
    result.xcb_query_pointer                       = try symbol'Linux.xcb_query_pointer_fn(library, "xcb_query_pointer")
    result.xcb_query_pointer_reply                 = try symbol'Linux.xcb_query_pointer_reply_fn(library, "xcb_query_pointer_reply")
    result.xcb_get_keyboard_mapping                = try symbol'Linux.xcb_get_keyboard_mapping_fn(library, "xcb_get_keyboard_mapping")
    result.xcb_get_keyboard_mapping_reply          = try symbol'Linux.xcb_get_keyboard_mapping_reply_fn(library, "xcb_get_keyboard_mapping_reply")
    result.xcb_get_keyboard_mapping_keysyms        = try symbol'Linux.xcb_get_keyboard_mapping_keysyms_fn(library, "xcb_get_keyboard_mapping_keysyms")
    result.xcb_get_keyboard_mapping_keysyms_length = try symbol'Linux.xcb_get_keyboard_mapping_keysyms_length_fn(library, "xcb_get_keyboard_mapping_keysyms_length")
    result.xcb_send_event_checked                  = try symbol'Linux.xcb_send_event_checked_fn(library, "xcb_send_event_checked")
    result.xcb_set_input_focus_checked             = try symbol'Linux.xcb_set_input_focus_checked_fn(library, "xcb_set_input_focus_checked")
    result.xcb_get_file_descriptor                 = try symbol'Linux.xcb_get_file_descriptor_fn(library, "xcb_get_file_descriptor")
    result.xcb_translate_coordinates               = try symbol'Linux.xcb_translate_coordinates_fn(library, "xcb_translate_coordinates")
    result.xcb_translate_coordinates_reply         = try symbol'Linux.xcb_translate_coordinates_reply_fn(library, "xcb_translate_coordinates_reply")
    result.xcb_query_tree                          = try symbol'Linux.xcb_query_tree_fn(library, "xcb_query_tree")
    result.xcb_query_tree_reply                    = try symbol'Linux.xcb_query_tree_reply_fn(library, "xcb_query_tree_reply")
    result.xcb_query_tree_children                 = try symbol'Linux.xcb_query_tree_children_fn(library, "xcb_query_tree_children")
    result.xcb_query_tree_children_length          = try symbol'Linux.xcb_query_tree_children_length_fn(library, "xcb_query_tree_children_length")
    result.xcb_get_window_attributes               = try symbol'Linux.xcb_get_window_attributes_fn(library, "xcb_get_window_attributes")
    result.xcb_get_window_attributes_reply         = try symbol'Linux.xcb_get_window_attributes_reply_fn(library, "xcb_get_window_attributes_reply")
    result.xcb_screen_allowed_depths_iterator      = try symbol'Linux.xcb_screen_allowed_depths_iterator_fn(library, "xcb_screen_allowed_depths_iterator")
    result.xcb_depth_next                          = try symbol'Linux.xcb_depth_next_fn(library, "xcb_depth_next")
    result.xcb_depth_visuals_iterator              = try symbol'Linux.xcb_depth_visuals_iterator_fn(library, "xcb_depth_visuals_iterator")
    result.xcb_visualtype_next                     = try symbol'Linux.xcb_visualtype_next_fn(library, "xcb_visualtype_next")
    result.xcb_create_colormap_checked             = try symbol'Linux.xcb_create_colormap_checked_fn(library, "xcb_create_colormap_checked")
    result.xcb_free_colormap_checked               = try symbol'Linux.xcb_free_colormap_checked_fn(library, "xcb_free_colormap_checked")
    result.xcb_open_font_checked                   = try symbol'Linux.xcb_open_font_checked_fn(library, "xcb_open_font_checked")
    result.xcb_close_font_checked                  = try symbol'Linux.xcb_close_font_checked_fn(library, "xcb_close_font_checked")
    result.xcb_create_glyph_cursor_checked         = try symbol'Linux.xcb_create_glyph_cursor_checked_fn(library, "xcb_create_glyph_cursor_checked")
    result.xcb_free_cursor_checked                 = try symbol'Linux.xcb_free_cursor_checked_fn(library, "xcb_free_cursor_checked")
    result.xcb_grab_pointer                        = try symbol'Linux.xcb_grab_pointer_fn(library, "xcb_grab_pointer")
    result.xcb_grab_pointer_reply                  = try symbol'Linux.xcb_grab_pointer_reply_fn(library, "xcb_grab_pointer_reply")
    result.xcb_ungrab_pointer_checked              = try symbol'Linux.xcb_ungrab_pointer_checked_fn(library, "xcb_ungrab_pointer_checked")
    result.xcb_grab_key_checked                    = try symbol'Linux.xcb_grab_key_checked_fn(library, "xcb_grab_key_checked")
    result.xcb_ungrab_key_checked                  = try symbol'Linux.xcb_ungrab_key_checked_fn(library, "xcb_ungrab_key_checked")
    result.xcb_create_gc_checked                   = try symbol'Linux.xcb_create_gc_checked_fn(library, "xcb_create_gc_checked")
    result.xcb_free_gc_checked                     = try symbol'Linux.xcb_free_gc_checked_fn(library, "xcb_free_gc_checked")
    result.xcb_put_image_checked                   = try symbol'Linux.xcb_put_image_checked_fn(library, "xcb_put_image_checked")
    result.xcb_get_selection_owner                 = try symbol'Linux.xcb_get_selection_owner_fn(library, "xcb_get_selection_owner")
    result.xcb_get_selection_owner_reply           = try symbol'Linux.xcb_get_selection_owner_reply_fn(library, "xcb_get_selection_owner_reply")
    result.xcb_get_image                           = try symbol'Linux.xcb_get_image_fn(library, "xcb_get_image")
    result.xcb_get_image_reply                     = try symbol'Linux.xcb_get_image_reply_fn(library, "xcb_get_image_reply")
    result.xcb_get_image_data                      = try symbol'Linux.xcb_get_image_data_fn(library, "xcb_get_image_data")
    result.xcb_get_image_data_length               = try symbol'Linux.xcb_get_image_data_length_fn(library, "xcb_get_image_data_length")
    result.xcb_setup_pixmap_formats_iterator       = try symbol'Linux.xcb_setup_pixmap_formats_iterator_fn(library, "xcb_setup_pixmap_formats_iterator")
    result.xcb_format_next                         = try symbol'Linux.xcb_format_next_fn(library, "xcb_format_next")
    let connection = result.xcb_connect(null, &result.screenIndex)
    result.connection = connection
    if not connection or result.xcb_connection_has_error(connection) != 0 do
        fail Swag.SystemError{"cannot connect to the X11 GUI display"}
    var screens = result.xcb_setup_roots_iterator(result.xcb_get_setup(connection))
    for result.screenIndex do
        result.xcb_screen_next(&screens)
    if screens.rem <= 0 or not screens.data do
        fail Swag.SystemError{"X11 GUI screen is unavailable"}
    result.screenPtr = screens.data
    result.screen    = screens.data[]
    result.uiThread  = Env.Process.currentThreadId()
    let rootEvents: u32 = (1 << 17) | (1 << 22)
    try check(result, result.xcb_change_window_attributes_checked(connection, result.screen.root, 1 << 11, &rootEvents))
    g_Context = result
    ready     = true
    return result
}

internal func atom(context: *Context, name: string)->u32 fail
{
    let connection = unwrap context.connection
    let key        = String.from(name)
    let cached     = context.atoms.tryFind(key)
    if cached do
        return cached.value
    if name.count > 65535 do
        fail Errors.BadParameterError{"X11 atom name is too long"}
    let reply = context.xcb_intern_atom_reply(connection,
                                              context.xcb_intern_atom(connection, 0, cast(u16, name.count), name.buffer),
                                              null)
    if not reply do
        fail Swag.SystemError{"cannot resolve an X11 atom"}
    defer Linux.free(reply)
    discard context.atoms.add(key, reply.atom)
    return reply.atom
}

internal func property(context: *Context, window, name, kind: u32, format: u8, count: u32, data: const *void?) fail
{
    let connection = unwrap context.connection
    try check(context, context.xcb_change_property_checked(connection, 0, window, name, kind, format, count, data))
}

internal func send(context: *Context, target, kind: u32, values: [5]u32) fail
{
    let connection = unwrap context.connection
    var event: Linux.xcb_client_message_event_t
    event.response_type = 33
    event.format        = 32
    event.window        = target
    event.type          = kind
    event.data          = values
    try check(context,
              context.xcb_send_event_checked(connection,
                                             0,
                                             context.screen.root,
                                             (1 << 19) | (1 << 20),
                                             cast(const [*]u8, &event)))
}

internal func surface(window: u32)->*Surface?
{
    let context = g_Context
    if context do
        for item in context.surfaces where item.windowId == window or item.trayWindow == window do
            return item
    return null
}

internal func initializeKeyboard(context: *Context) fail
{
    if context.keyboardState do
        return
    let library = Linux.dlopen("libxkbcommon.so.0".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
    if not library do
        fail Swag.SystemError{"cannot load libxkbcommon.so.0"}
    defer #fail discard Linux.dlclose(unwrap library)
    let adapter = Linux.dlopen("libxkbcommon-x11.so.0".buffer, Linux.RTLD_NOW | Linux.RTLD_LOCAL)
    if not adapter do
        fail Swag.SystemError{"cannot load libxkbcommon-x11.so.0"}
    defer #fail discard Linux.dlclose(unwrap adapter)
    context.xkb_context_new                     = try symbol'Linux.xkb_context_new_fn(library, "xkb_context_new")
    context.xkb_context_unref                   = try symbol'Linux.xkb_context_unref_fn(library, "xkb_context_unref")
    context.xkb_keymap_unref                    = try symbol'Linux.xkb_keymap_unref_fn(library, "xkb_keymap_unref")
    context.xkb_state_unref                     = try symbol'Linux.xkb_state_unref_fn(library, "xkb_state_unref")
    context.xkb_state_update_mask               = try symbol'Linux.xkb_state_update_mask_fn(library, "xkb_state_update_mask")
    context.xkb_state_key_get_one_sym           = try symbol'Linux.xkb_state_key_get_one_sym_fn(library, "xkb_state_key_get_one_sym")
    context.xkb_keymap_key_get_syms_by_level    = try symbol'Linux.xkb_keymap_key_get_syms_by_level_fn(library, "xkb_keymap_key_get_syms_by_level")
    context.xkb_keysym_to_utf32                 = try symbol'Linux.xkb_keysym_to_utf32_fn(library, "xkb_keysym_to_utf32")
    context.xkb_compose_table_new_from_locale   = try symbol'Linux.xkb_compose_table_new_from_locale_fn(library, "xkb_compose_table_new_from_locale")
    context.xkb_compose_table_unref             = try symbol'Linux.xkb_compose_table_unref_fn(library, "xkb_compose_table_unref")
    context.xkb_compose_state_new               = try symbol'Linux.xkb_compose_state_new_fn(library, "xkb_compose_state_new")
    context.xkb_compose_state_unref             = try symbol'Linux.xkb_compose_state_unref_fn(library, "xkb_compose_state_unref")
    context.xkb_compose_state_feed              = try symbol'Linux.xkb_compose_state_feed_fn(library, "xkb_compose_state_feed")
    context.xkb_compose_state_get_status        = try symbol'Linux.xkb_compose_state_get_status_fn(library, "xkb_compose_state_get_status")
    context.xkb_compose_state_get_utf8          = try symbol'Linux.xkb_compose_state_get_utf8_fn(library, "xkb_compose_state_get_utf8")
    context.xkb_compose_state_reset             = try symbol'Linux.xkb_compose_state_reset_fn(library, "xkb_compose_state_reset")
    context.xkb_x11_setup_xkb_extension         = try symbol'Linux.xkb_x11_setup_xkb_extension_fn(adapter, "xkb_x11_setup_xkb_extension")
    context.xkb_x11_get_core_keyboard_device_id = try symbol'Linux.xkb_x11_get_core_keyboard_device_id_fn(adapter, "xkb_x11_get_core_keyboard_device_id")
    context.xkb_x11_keymap_new_from_device      = try symbol'Linux.xkb_x11_keymap_new_from_device_fn(adapter, "xkb_x11_keymap_new_from_device")
    context.xkb_x11_state_new_from_device       = try symbol'Linux.xkb_x11_state_new_from_device_fn(adapter, "xkb_x11_state_new_from_device")
    let connection = unwrap context.connection
    if context.xkb_x11_setup_xkb_extension(connection, 1, 0, 0, null, null, null, null) == 0 do
        fail Swag.SystemError{"X11 keyboard extension is unavailable"}
    let keyboard = context.xkb_context_new(0)
    if not keyboard do
        fail Swag.SystemError{"cannot create XKB context"}
    defer #fail context.xkb_context_unref(unwrap keyboard)
    let device = context.xkb_x11_get_core_keyboard_device_id(connection)
    if device < 0 do
        fail Swag.SystemError{"X11 core keyboard is unavailable"}
    let keymap = context.xkb_x11_keymap_new_from_device(keyboard, connection, device, 0)
    if not keymap do
        fail Swag.SystemError{"cannot read the X11 keyboard map"}
    defer #fail context.xkb_keymap_unref(unwrap keymap)
    let state = context.xkb_x11_state_new_from_device(keymap, connection, device)
    if not state do
        fail Swag.SystemError{"cannot read the X11 keyboard state"}
    defer #fail context.xkb_state_unref(unwrap state)
    var locale = Env.variable("LC_ALL")
    if locale.isEmpty() do
        locale = Env.variable("LC_CTYPE")
    if locale.isEmpty() do
        locale = Env.variable("LANG")
    if locale.isEmpty() do
        locale = "C.UTF-8"
    let compose = context.xkb_compose_table_new_from_locale(keyboard, unwrap locale.buffer, 0)
    if not compose do
        fail Swag.SystemError{"cannot load keyboard composition rules"}
    context.keyboardLibrary    = library
    context.keyboardX11Library = adapter
    context.keyboardContext    = keyboard
    context.keyboardMap        = keymap
    context.keyboardState      = state
    context.composeTable       = compose
}

#drop
{
    if g_Context
    {
        let context = unwrap g_Context
        if context.pendingEvent do
            Linux.free(context.pendingEvent)
        if context.composeTable do
            context.xkb_compose_table_unref(context.composeTable)
        if context.keyboardState do
            context.xkb_state_unref(context.keyboardState)
        if context.keyboardMap do
            context.xkb_keymap_unref(context.keyboardMap)
        if context.keyboardContext do
            context.xkb_context_unref(context.keyboardContext)
        if context.keyboardX11Library do
            discard Linux.dlclose(context.keyboardX11Library)
        if context.keyboardLibrary do
            discard Linux.dlclose(context.keyboardLibrary)
        context.xcb_disconnect(unwrap context.connection)
        discard Linux.dlclose(unwrap context.library)
        Memory.delete(context)
        g_Context = null
    }
}

internal func current()->*Context? => g_Context

internal func readProperty(context: *Context, window, name: u32)->Array'u8 fail
{
    let connection = unwrap context.connection
    let reply      = context.xcb_get_property_reply(connection,
                                                    context.xcb_get_property(connection, 0, window, name, 0, 0, 262144),
                                                    null)
    if not reply do
        fail Swag.SystemError{"cannot read X11 window property"}
    defer Linux.free(reply)
    if reply.bytes_after != 0 do
        fail Swag.SystemError{"X11 window property is too large"}
    var result: #returntype
    let length = context.xcb_get_property_value_length(reply)
    if length > 0 do
        result.add(Swag.makeSlice(cast(const [*]u8, context.xcb_get_property_value(reply)), cast(u64, length)))
    return result
}

internal func failNative(error: s32) fail
{
    let message = mkString(cast(string, cast(cstring, Linux.strerror(error))))
    fail Swag.SystemError{message, errorID: cast(u64, error)}
}

// Desktop settings are authoritative. WSLg's X11 server can report 96 DPI without publishing
// the Windows monitor scale, so WSL interop supplies a fallback before Xft settings are read.
internal struct Preferences
{
    scale:         f32  = 1
    prefersLight:  bool = true
    reducedMotion: bool
}

internal func parseSettings(bytes: const [..]u8, fallback: Preferences)->Preferences fail
{
    var result     = fallback
    var themeLight = fallback.prefersLight
    var preferDark = false
    var windowScale: u32
    var source     = ByteStream.openRead(bytes)
    let order      = try source.readNative'u8()
    if order > 1 do
        fail Errors.InvalidFormatError{"invalid XSETTINGS byte order"}
    source.advance(3)

    func read32(source: *ByteStream, order: u8)->u32 fail
    {
        return order == 0 ? try source.readLittleEndian'u32() : try source.readBigEndian'u32()
    }

    func padding(source: *ByteStream) fail
    {
        let count = (4 - source.position() % 4) % 4
        if count > source.remainingBytes().count do
            fail Errors.InvalidFormatError{"truncated XSETTINGS padding"}
        source.advance(count)
    }

    func stringBytes(source: *ByteStream, count: u64)->String fail
    {
        if count > source.remainingBytes().count do
            fail Errors.InvalidFormatError{"truncated XSETTINGS string"}
        let result = String.from(Swag.makeString(source.remainingBytes().buffer, count))
        if not Utf8.isValid(result.toString()) do
            fail Errors.InvalidFormatError{"invalid UTF-8 in XSETTINGS string"}
        source.advance(count)
        return result
    }

    discard try read32(&source, order)
    let count = try read32(&source, order)
    if count > bytes.count / 12 do
        fail Errors.InvalidFormatError{"invalid XSETTINGS entry count"}
    for count
    {
        let kind = try source.readNative'u8()
        discard try source.readNative'u8()
        let length = order == 0 ? try source.readLittleEndian'u16() : try source.readBigEndian'u16()
        let name   = try stringBytes(&source, length)
        try padding(&source)
        discard try read32(&source, order)
        switch kind
        {
        case 0:
            let value = try read32(&source, order)
            if name == "Gtk/EnableAnimations" do
                result.reducedMotion = value == 0
            elif name == "Gtk/ApplicationPreferDarkTheme" do
                preferDark = value != 0
            elif name == "Gdk/WindowScalingFactor" and value >= 1 and value <= 8 do
                windowScale = value
            elif name == "Xft/DPI" and value >= 48 * 1024 and value <= 768 * 1024 do
                result.scale = cast(f32, value) / (96 * 1024)

        case 1:
            let value = try stringBytes(&source, try read32(&source, order))
            try padding(&source)
            if name == "Net/ThemeName" do
                themeLight = not value.toLower().contains("dark")

        case 2:
            discard try source.readNative'u64()

        default:
            fail Errors.InvalidFormatError{"unknown XSETTINGS value type"}
        }
    }

    // Some desktops also scale Xft/DPI for older clients, so the explicit window scale wins.
    if windowScale != 0 do
        result.scale = cast(f32, windowScale)
    result.prefersLight = themeLight and not preferDark
    return result
}

internal func wslDpiScale()->f32
{
    if Env.variable("WSL_INTEROP").isEmpty() do
        return 0

    const command = """
        Add-Type -Namespace SwagDpi -Name Monitor -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr value); [DllImport("user32.dll")] public static extern uint GetDpiForSystem();'
        [SwagDpi.Monitor]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
        [SwagDpi.Monitor]::GetDpiForSystem()
        """
    const arguments: [6]string = ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", command]
    let process = catch Env.runProcess("powershell.exe", arguments) { return 0 }
    if process.exitCode() != 0 do
        return 0

    var output = String.from(process.standardOutput())
    output.trim()
    let dpi = catch StrConv.toU32(output.toString()) { return 0 }
    if dpi < 48 or dpi > 768 do
        return 0
    return cast(f32, dpi) / 96
}

internal func preferences(context: *Context)->Preferences
{
    let connection   = unwrap context.connection
    if not context.wslDpiResolved
    {
        context.wslDpiResolved = true
        let scale = wslDpiScale()
        context.wslDpiScale = scale > 0 ? scale : 1
    }

    var result = Preferences{scale: context.wslDpiScale}
    let resourceName = expect atom(context, "RESOURCE_MANAGER")
    let resources    = catch readProperty(context, context.screen.root, resourceName) orelse Array'u8{}
    if not resources.isEmpty()
    {
        let text = Swag.makeString(unwrap resources.buffer, resources.count)
        for line in Tokenize.splitLines(text)
        {
            let pieces = Tokenize.split(line, ":", maxSplit: 1, removeEmpty: false)
            if pieces.count != 2 do
                continue
            var name = String.from(pieces[0])
            name.trim()
            if name != "Xft.dpi" do
                continue
            var value = String.from(pieces[1])
            value.trim()
            let dpi = catch StrConv.toF32(value) orelse 96
            if dpi >= 48 and dpi <= 768 do
                result.scale = dpi / 96
        }
    }

    let selection = expect atom(context, Format.toString("_XSETTINGS_S%", context.screenIndex))
    let reply     = context.xcb_get_selection_owner_reply(connection, context.xcb_get_selection_owner(connection, selection), null)
    if not reply do
        return result
    let owner = reply.owner
    Linux.free(reply)
    if context.settingsOwner != owner
    {
        context.settingsOwner = owner
        if owner != 0
        {
            let mask: u32 = (1 << 17) | (1 << 22)
            discard catch check(context, context.xcb_change_window_attributes_checked(connection, owner, 1 << 11, &mask))
        }
    }

    if owner != 0
    {
        let bytes = catch readProperty(context, owner, expect atom(context, "_XSETTINGS_SETTINGS")) orelse Array'u8{}
        result = catch parseSettings(bytes.toSlice(), result) orelse result
    }

    let theme = Env.variable("GTK_THEME")
    if not theme.isEmpty() do
        result.prefersLight = not theme.toLower().contains("dark")
    return result
}
