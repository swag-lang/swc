#global if #os == Swag.TargetOs.Linux
#global export

// X11 window management, input grabs and cursor resources. Function pointers borrow libxcb.
// Requests with replies allocate through libc; release replies and errors with Linux.free.

struct xcb_grab_pointer_reply_t
{
    public
    {
        response_type: u8
        status:        u8
        sequence:      u16
        length:        u32
        pad0:          [24]u8
    }
}

alias xcb_grab_pointer_cookie_t          = xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_create_colormap_checked_fn     = func(*void, u8, u32, u32, u32)->xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_free_colormap_checked_fn       = func(*void, u32)->xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_open_font_checked_fn           = func(*void, u32, u16, const [*]u8)->xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_close_font_checked_fn          = func(*void, u32)->xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_create_glyph_cursor_checked_fn = func(*void, u32, u32, u32, u16, u16, u16, u16, u16, u16, u16, u16)->xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_free_cursor_checked_fn         = func(*void, u32)->xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_grab_pointer_fn                = func(*void, u8, u32, u16, u8, u8, u32, u32, u32)->xcb_grab_pointer_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_grab_pointer_reply_fn          = func(*void, xcb_grab_pointer_cookie_t, *(*xcb_generic_error_t?)?)->*xcb_grab_pointer_reply_t?

#[Swag.CallingConvention(.C)]
alias xcb_ungrab_pointer_checked_fn      = func(*void, u32)->xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_grab_key_checked_fn            = func(*void, u8, u32, u16, u8, u8, u8)->xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_ungrab_key_checked_fn          = func(*void, u8, u32, u16)->xcb_void_cookie_t

#assert(#sizeof(xcb_grab_pointer_reply_t) == 32)

#[Swag.CallingConvention(.C)]
alias xcb_create_gc_checked_fn = func(*void, u32, u32, u32, const *void?)->xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_free_gc_checked_fn = func(*void, u32)->xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_put_image_checked_fn = func(*void, u8, u32, u32, u16, u16, s16, s16, u8, u8, u32, const [*]u8)->xcb_void_cookie_t
