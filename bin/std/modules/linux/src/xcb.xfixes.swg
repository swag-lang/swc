#global if #os == Swag.TargetOs.Linux
#global export

// XFixes 4 cursor requests; load libxcb-xfixes.so.0 and negotiate version 4 first.
// Replies and errors use libc free; function pointers borrow their dynamic library.

#[Swag.CallingConvention(.C)]
alias xcb_xfixes_hide_cursor_checked_fn = func(*void, u32)->xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_xfixes_show_cursor_checked_fn = func(*void, u32)->xcb_void_cookie_t
