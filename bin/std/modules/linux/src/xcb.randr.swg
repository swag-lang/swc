#global if #os == Swag.TargetOs.Linux
#global export

// RandR 1.5 monitor queries; load libxcb-randr.so.0 and negotiate the version first.
// Replies and errors use libc free; function pointers borrow their dynamic library.

struct xcb_randr_monitor_info_t
{
    public
    {
        name:                  u32
        primary:               u8
        automatic:             u8
        nOutput:               u16
        x:                     s16
        y:                     s16
        width:                 u16
        height:                u16
        width_in_millimeters:  u32
        height_in_millimeters: u32
    }
}

struct xcb_randr_get_monitors_reply_t
{
    public
    {
        response_type: u8
        pad0:          u8
        sequence:      u16
        length:        u32
        timestamp:     u32
        nMonitors:     u32
        nOutputs:      u32
        pad1:          [12] u8
    }
}

struct xcb_randr_monitor_info_iterator_t
{
    public
    {
        data:  *xcb_randr_monitor_info_t?
        rem:   s32
        index: s32
    }
}

struct xcb_randr_query_version_reply_t
{
    public
    {
        response_type: u8
        pad0:          u8
        sequence:      u16
        length:        u32
        major_version: u32
        minor_version: u32
        pad1:          [16] u8
    }
}

alias xcb_randr_get_monitors_cookie_t  = xcb_void_cookie_t

alias xcb_randr_query_version_cookie_t = xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_randr_query_version_fn       = func(*void, u32, u32)->xcb_randr_query_version_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_randr_query_version_reply_fn = func(*void, xcb_randr_query_version_cookie_t, *(*xcb_generic_error_t?)?)->*xcb_randr_query_version_reply_t?

#[Swag.CallingConvention(.C)]
alias xcb_randr_get_monitors_fn        = func(*void, u32, u8)->xcb_randr_get_monitors_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_randr_get_monitors_reply_fn  = func(*void, xcb_randr_get_monitors_cookie_t, *(*xcb_generic_error_t?)?)->*xcb_randr_get_monitors_reply_t?

#[Swag.CallingConvention(.C)]
alias xcb_randr_get_monitors_monitors_iterator_fn = func(const *xcb_randr_get_monitors_reply_t)->xcb_randr_monitor_info_iterator_t

#[Swag.CallingConvention(.C)]
alias xcb_randr_monitor_info_next_fn   = func(*xcb_randr_monitor_info_iterator_t)

#assert(#sizeof(xcb_randr_monitor_info_t) == 24)

#assert(#sizeof(xcb_randr_get_monitors_reply_t) == 32)

#assert(#sizeof(xcb_randr_monitor_info_iterator_t) == 16)
