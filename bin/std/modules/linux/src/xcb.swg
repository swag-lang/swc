#global if #os == Swag.TargetOs.Linux
#global export

// Raw XCB/X11 protocol layouts and C function-pointer types, based on libxcb 1.17 headers.
// Load the optional libxcb.so.1 / libxcb-randr.so.0 libraries before resolving these functions.
// Setup/screen views borrow the connection. Replies, errors and polled events use libc free.
// Function pointers borrow their library; no function here loads a library or owns a resource.

struct xcb_void_cookie_t
{
    public sequence: u32
}

struct xcb_screen_t
{
    public
    {
        root:                  u32
        default_colormap:      u32
        white_pixel:           u32
        black_pixel:           u32
        current_input_masks:   u32
        width_in_pixels:       u16
        height_in_pixels:      u16
        width_in_millimeters:  u16
        height_in_millimeters: u16
        min_installed_maps:    u16
        max_installed_maps:    u16
        root_visual:           u32
        backing_stores:        u8
        save_unders:           u8
        root_depth:            u8
        allowed_depths_len:    u8
    }
}

struct xcb_screen_iterator_t
{
    public
    {
        data:  *xcb_screen_t?
        rem:   s32
        index: s32
    }
}

struct xcb_setup_t
{
    public
    {
        status:                      u8
        pad0:                        u8
        protocol_major_version:      u16
        protocol_minor_version:      u16
        length:                      u16
        release_number:              u32
        resource_id_base:            u32
        resource_id_mask:            u32
        motion_buffer_size:          u32
        vendor_len:                  u16
        maximum_request_length:      u16
        roots_len:                   u8
        pixmap_formats_len:          u8
        image_byte_order:            u8
        bitmap_format_bit_order:     u8
        bitmap_format_scanline_unit: u8
        bitmap_format_scanline_pad:  u8
        min_keycode:                 u8
        max_keycode:                 u8
        pad1:                        [4] u8
    }
}

struct xcb_expose_event_t
{
    public
    {
        response_type: u8
        pad0:          u8
        sequence:      u16
        window:        u32
        x:             u16
        y:             u16
        width:         u16
        height:        u16
        count:         u16
        pad1:          [2] u8
    }
}

struct xcb_configure_notify_event_t
{
    public
    {
        response_type:     u8
        pad0:              u8
        sequence:          u16
        event:             u32
        window:            u32
        above_sibling:     u32
        x:                 s16
        y:                 s16
        width:             u16
        height:            u16
        border_width:      u16
        override_redirect: u8
        pad1:              u8
    }
}

struct xcb_destroy_notify_event_t
{
    public
    {
        response_type: u8
        pad0:          u8
        sequence:      u16
        event:         u32
        window:        u32
    }
}

struct xcb_get_geometry_reply_t
{
    public
    {
        response_type: u8
        depth:         u8
        sequence:      u16
        length:        u32
        root:          u32
        x:             s16
        y:             s16
        width:         u16
        height:        u16
        border_width:  u16
        pad0:          [2] u8
    }
}

struct xcb_get_property_reply_t
{
    public
    {
        response_type: u8
        format:        u8
        sequence:      u16
        length:        u32
        type:          u32
        bytes_after:   u32
        value_len:     u32
        pad0:          [12] u8
    }
}

struct xcb_query_pointer_reply_t
{
    public
    {
        response_type: u8
        same_screen:   u8
        sequence:      u16
        length:        u32
        root:          u32
        child:         u32
        root_x:        s16
        root_y:        s16
        win_x:         s16
        win_y:         s16
        mask:          u16
        pad0:          [2] u8
    }
}

struct xcb_query_keymap_reply_t
{
    public
    {
        response_type: u8
        pad0:          u8
        sequence:      u16
        length:        u32
        keys:          [32] u8
    }
}

struct xcb_get_keyboard_mapping_reply_t
{
    public
    {
        response_type:       u8
        keysyms_per_keycode: u8
        sequence:            u16
        length:              u32
        pad0:                [24] u8
    }
}

struct xcb_intern_atom_reply_t
{
    public
    {
        response_type: u8
        pad0:          u8
        sequence:      u16
        length:        u32
        atom:          u32
    }
}

struct xcb_generic_event_t
{
    public
    {
        response_type: u8
        pad0:          u8
        sequence:      u16
        pad:           [7] u32
        full_sequence: u32
    }
}

struct xcb_generic_error_t
{
    public
    {
        response_type: u8
        error_code:    u8
        sequence:      u16
        resource_id:   u32
        minor_code:    u16
        major_code:    u8
        pad0:          u8
        pad:           [5] u32
        full_sequence: u32
    }
}

// The native client-message union is represented by its five 32-bit words.
struct xcb_client_message_event_t
{
    public
    {
        response_type: u8
        format:        u8
        sequence:      u16
        window:        u32
        type:          u32
        data:          [5] u32
    }
}

alias xcb_get_geometry_cookie_t                  = xcb_void_cookie_t

alias xcb_get_property_cookie_t                  = xcb_void_cookie_t

alias xcb_query_pointer_cookie_t                 = xcb_void_cookie_t

alias xcb_query_keymap_cookie_t                  = xcb_void_cookie_t

alias xcb_get_keyboard_mapping_cookie_t          = xcb_void_cookie_t

alias xcb_intern_atom_cookie_t                   = xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_connect_fn                             = func(const [*] u8?, *s32?)->*void?

#[Swag.CallingConvention(.C)]
alias xcb_disconnect_fn                          = func(*void)

#[Swag.CallingConvention(.C)]
alias xcb_connection_has_error_fn                = func(*void)->s32

#[Swag.CallingConvention(.C)]
alias xcb_get_setup_fn                           = func(*void)->const *xcb_setup_t

#[Swag.CallingConvention(.C)]
alias xcb_setup_roots_iterator_fn                = func(const *xcb_setup_t)->xcb_screen_iterator_t

#[Swag.CallingConvention(.C)]
alias xcb_screen_next_fn                         = func(*xcb_screen_iterator_t)

#[Swag.CallingConvention(.C)]
alias xcb_generate_id_fn                         = func(*void)->u32

#[Swag.CallingConvention(.C)]
alias xcb_request_check_fn                       = func(*void, xcb_void_cookie_t)->*xcb_generic_error_t?

#[Swag.CallingConvention(.C)]
alias xcb_flush_fn                               = func(*void)->s32

#[Swag.CallingConvention(.C)]
alias xcb_poll_for_event_fn                      = func(*void)->*xcb_generic_event_t?

#[Swag.CallingConvention(.C)]
alias xcb_create_window_checked_fn               = func(*void, u8, u32, u32, s16, s16, u16, u16, u16, u16, u32, u32, const *void?)->xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_destroy_window_checked_fn              = func(*void, u32)->xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_map_window_checked_fn                  = func(*void, u32)->xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_unmap_window_checked_fn                = func(*void, u32)->xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_configure_window_checked_fn            = func(*void, u32, u16, const *void?)->xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_change_window_attributes_checked_fn    = func(*void, u32, u32, const *void?)->xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_change_property_checked_fn             = func(*void, u8, u32, u32, u32, u8, u32, const *void?)->xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_intern_atom_fn                         = func(*void, u8, u16, const [*] u8)->xcb_intern_atom_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_intern_atom_reply_fn                   = func(*void, xcb_intern_atom_cookie_t, *(*xcb_generic_error_t?)?)->*xcb_intern_atom_reply_t?

#[Swag.CallingConvention(.C)]
alias xcb_get_geometry_fn                        = func(*void, u32)->xcb_get_geometry_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_get_geometry_reply_fn                  = func(*void, xcb_get_geometry_cookie_t, *(*xcb_generic_error_t?)?)->*xcb_get_geometry_reply_t?

#[Swag.CallingConvention(.C)]
alias xcb_get_property_fn                        = func(*void, u8, u32, u32, u32, u32, u32)->xcb_get_property_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_get_property_reply_fn                  = func(*void, xcb_get_property_cookie_t, *(*xcb_generic_error_t?)?)->*xcb_get_property_reply_t?

#[Swag.CallingConvention(.C)]
alias xcb_get_property_value_fn                  = func(const *xcb_get_property_reply_t)->*void

#[Swag.CallingConvention(.C)]
alias xcb_get_property_value_length_fn           = func(const *xcb_get_property_reply_t)->s32

#[Swag.CallingConvention(.C)]
alias xcb_query_pointer_fn                       = func(*void, u32)->xcb_query_pointer_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_query_pointer_reply_fn                 = func(*void, xcb_query_pointer_cookie_t, *(*xcb_generic_error_t?)?)->*xcb_query_pointer_reply_t?

#[Swag.CallingConvention(.C)]
alias xcb_query_keymap_fn                        = func(*void)->xcb_query_keymap_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_query_keymap_reply_fn                  = func(*void, xcb_query_keymap_cookie_t, *(*xcb_generic_error_t?)?)->*xcb_query_keymap_reply_t?

#[Swag.CallingConvention(.C)]
alias xcb_get_keyboard_mapping_fn                = func(*void, u8, u8)->xcb_get_keyboard_mapping_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_get_keyboard_mapping_reply_fn          = func(*void, xcb_get_keyboard_mapping_cookie_t, *(*xcb_generic_error_t?)?)->*xcb_get_keyboard_mapping_reply_t?

#[Swag.CallingConvention(.C)]
alias xcb_get_keyboard_mapping_keysyms_fn        = func(const *xcb_get_keyboard_mapping_reply_t)->[*] u32

#[Swag.CallingConvention(.C)]
alias xcb_get_keyboard_mapping_keysyms_length_fn = func(const *xcb_get_keyboard_mapping_reply_t)->s32

#[Swag.CallingConvention(.C)]
alias xcb_warp_pointer_checked_fn                = func(*void, u32, u32, s16, s16, u16, u16, s16, s16)->xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_clear_area_checked_fn                  = func(*void, u8, u32, s16, s16, u16, u16)->xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_send_event_checked_fn                  = func(*void, u8, u32, u32, const [*] u8)->xcb_void_cookie_t

#assert(#sizeof(xcb_void_cookie_t) == 4)

#assert(#sizeof(xcb_screen_t) == 40)

#assert(#sizeof(xcb_screen_iterator_t) == 16)

#assert(#sizeof(xcb_setup_t) == 40)

#assert(#sizeof(xcb_generic_event_t) == 36)

#assert(#sizeof(xcb_generic_error_t) == 36)

#assert(#sizeof(xcb_expose_event_t) == 20)

#assert(#sizeof(xcb_configure_notify_event_t) == 28)

#assert(#sizeof(xcb_destroy_notify_event_t) == 12)

#assert(#sizeof(xcb_client_message_event_t) == 32)

#assert(#sizeof(xcb_get_geometry_reply_t) == 24)

#assert(#sizeof(xcb_get_property_reply_t) == 32)

#assert(#sizeof(xcb_query_pointer_reply_t) == 28)

#assert(#sizeof(xcb_query_keymap_reply_t) == 40)

#assert(#sizeof(xcb_get_keyboard_mapping_reply_t) == 32)

#assert(#sizeof(xcb_intern_atom_reply_t) == 12)

#assert(#offsetof(xcb_screen_t.root_visual) == 32)

#assert(#offsetof(xcb_setup_t.min_keycode) == 34)

#assert(#offsetof(xcb_query_pointer_reply_t.mask) == 24)

#assert(#offsetof(xcb_client_message_event_t.data) == 12)

#assert(#offsetof(xcb_generic_error_t.full_sequence) == 32)

#assert(#offsetof(xcb_get_property_reply_t.value_len) == 16)

struct xcb_extension_t
{
    public
    {
        name:      const [*]u8?
        global_id: s32
    }
}

struct xcb_query_extension_reply_t
{
    public
    {
        response_type: u8
        pad0:          u8
        sequence:      u16
        length:        u32
        present:       u8
        major_opcode:  u8
        first_event:   u8
        first_error:   u8
    }
}

// The reply belongs to the connection; do not free it. The descriptor must remain loaded.
#[Swag.CallingConvention(.C)]
alias xcb_get_extension_data_fn = func(*void, *xcb_extension_t)->const *xcb_query_extension_reply_t?

#assert(#sizeof(xcb_extension_t) == 16)
#assert(#offsetof(xcb_extension_t.global_id) == 8)
#assert(#sizeof(xcb_query_extension_reply_t) == 12)
#assert(#offsetof(xcb_query_extension_reply_t.present) == 8)
