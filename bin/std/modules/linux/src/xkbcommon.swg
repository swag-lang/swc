#global if #os == Swag.TargetOs.Linux
#global export

// libxkbcommon 1.x and its X11 adapter. Opaque objects follow the upstream ref/unref ownership.
// Function pointers borrow their respective dynamically loaded libraries.

#[Swag.CallingConvention(.C)]
alias xkb_context_new_fn                     = func(u32)->*void?

#[Swag.CallingConvention(.C)]
alias xkb_context_unref_fn                   = func(*void)

#[Swag.CallingConvention(.C)]
alias xkb_keymap_unref_fn                    = func(*void)

#[Swag.CallingConvention(.C)]
alias xkb_state_unref_fn                     = func(*void)

#[Swag.CallingConvention(.C)]
alias xkb_state_update_mask_fn               = func(*void, u32, u32, u32, u32, u32, u32)->u32

#[Swag.CallingConvention(.C)]
alias xkb_state_key_get_one_sym_fn           = func(*void, u32)->u32

#[Swag.CallingConvention(.C)]
alias xkb_keymap_key_get_syms_by_level_fn    = func(*void, u32, u32, u32, *const [*]u32?)->s32

#[Swag.CallingConvention(.C)]
alias xkb_keysym_to_utf32_fn                 = func(u32)->u32

#[Swag.CallingConvention(.C)]
alias xkb_compose_table_new_from_locale_fn   = func(*void, const [*]u8, u32)->*void?

#[Swag.CallingConvention(.C)]
alias xkb_compose_table_unref_fn             = func(*void)

#[Swag.CallingConvention(.C)]
alias xkb_compose_state_new_fn               = func(*void, u32)->*void?

#[Swag.CallingConvention(.C)]
alias xkb_compose_state_unref_fn             = func(*void)

#[Swag.CallingConvention(.C)]
alias xkb_compose_state_feed_fn              = func(*void, u32)->u32

#[Swag.CallingConvention(.C)]
alias xkb_compose_state_get_status_fn        = func(*void)->u32

#[Swag.CallingConvention(.C)]
alias xkb_compose_state_get_utf8_fn          = func(*void, [*]u8?, u64)->s32

#[Swag.CallingConvention(.C)]
alias xkb_compose_state_reset_fn             = func(*void)

#[Swag.CallingConvention(.C)]
alias xkb_x11_setup_xkb_extension_fn         = func(*void, u16, u16, u32, *u16?, *u16?, *u8?, *u8?)->s32

#[Swag.CallingConvention(.C)]
alias xkb_x11_get_core_keyboard_device_id_fn = func(*void)->s32

#[Swag.CallingConvention(.C)]
alias xkb_x11_keymap_new_from_device_fn      = func(*void, *void, s32, u32)->*void?

#[Swag.CallingConvention(.C)]
alias xkb_x11_state_new_from_device_fn       = func(*void, *void, s32)->*void?

// libxcb-xkb 1.x: subscribe to core-keyboard map and device replacement notifications.
#[Swag.CallingConvention(.C)]
alias xcb_xkb_select_events_checked_fn       = func(*void, u16, u16, u16, u16, u16, u16, const *void?)->xcb_void_cookie_t

// Per-client detectable repeat omits synthetic KeyRelease/KeyPress pairs while a key is held.
alias xcb_xkb_per_client_flags_cookie_t = xcb_void_cookie_t

struct xcb_xkb_per_client_flags_reply_t
{
    public
    {
        response_type:   u8
        deviceID:        u8
        sequence:        u16
        length:          u32
        supported:       u32
        value:           u32
        autoCtrls:       u32
        autoCtrlsValues: u32
        pad0:            [8]u8
    }
}

#[Swag.CallingConvention(.C)]
alias xcb_xkb_per_client_flags_fn       = func(*void, u16, u32, u32, u32, u32, u32)->xcb_xkb_per_client_flags_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_xkb_per_client_flags_reply_fn = func(*void, xcb_xkb_per_client_flags_cookie_t, *(*xcb_generic_error_t?)?)->*xcb_xkb_per_client_flags_reply_t?

#assert(#sizeof(xcb_xkb_per_client_flags_cookie_t) == 4)
#assert(#sizeof(xcb_xkb_per_client_flags_reply_t) == 32)
#assert(#offsetof(xcb_xkb_per_client_flags_reply_t.supported) == 8)
