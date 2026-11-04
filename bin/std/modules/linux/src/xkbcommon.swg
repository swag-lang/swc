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
alias xkb_compose_state_get_one_sym_fn       = func(*void)->u32

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
