#global if #os == Swag.TargetOs.Linux
#global export

// XFixes 4 cursor requests; load libxcb-xfixes.so.0 and negotiate version 4 first.
// Replies and errors use libc free; function pointers borrow their dynamic library.

struct xcb_xfixes_query_version_reply_t
{
    public
    {
        response_type: u8
        pad0:          u8
        sequence:      u16
        length:        u32
        major_version: u32
        minor_version: u32
        pad1:          [16]u8
    }
}

alias xcb_xfixes_query_version_cookie_t = xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_xfixes_query_version_fn       = func(*void, u32, u32)->xcb_xfixes_query_version_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_xfixes_query_version_reply_fn = func(*void, xcb_xfixes_query_version_cookie_t, *(*xcb_generic_error_t?)?)->*xcb_xfixes_query_version_reply_t?

#[Swag.CallingConvention(.C)]
alias xcb_xfixes_hide_cursor_checked_fn = func(*void, u32)->xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_xfixes_show_cursor_checked_fn = func(*void, u32)->xcb_void_cookie_t

#assert(#sizeof(xcb_xfixes_query_version_cookie_t) == 4)
#assert(#sizeof(xcb_xfixes_query_version_reply_t) == 32)
