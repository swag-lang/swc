#global if #os == Swag.TargetOs.Linux
#global export

const XCB_CLIENT_MESSAGE     = 33'u8
const XCB_PROPERTY_NOTIFY    = 28'u8
const XCB_SELECTION_CLEAR    = 29'u8
const XCB_SELECTION_REQUEST  = 30'u8
const XCB_SELECTION_NOTIFY   = 31'u8
const XCB_PROPERTY_NEW_VALUE = 0'u8
const XCB_PROPERTY_DELETE    = 1'u8

struct xcb_property_notify_event_t
{
    public
    {
        response_type: u8
        pad0:          u8
        sequence:      u16
        window:        u32
        atom:          u32
        time:          u32
        state:         u8
        pad1:          [3] u8
    }
}

struct xcb_selection_clear_event_t
{
    public
    {
        response_type: u8
        pad0:          u8
        sequence:      u16
        time:          u32
        owner:         u32
        selection:     u32
    }
}

struct xcb_selection_request_event_t
{
    public
    {
        response_type: u8
        pad0:          u8
        sequence:      u16
        time:          u32
        owner:         u32
        requestor:     u32
        selection:     u32
        target:        u32
        property:      u32
    }
}

struct xcb_selection_notify_event_t
{
    public
    {
        response_type: u8
        pad0:          u8
        sequence:      u16
        time:          u32
        requestor:     u32
        selection:     u32
        target:        u32
        property:      u32
    }
}

struct xcb_get_selection_owner_reply_t
{
    public
    {
        response_type: u8
        pad0:          u8
        sequence:      u16
        length:        u32
        owner:         u32
    }
}

alias xcb_get_selection_owner_cookie_t   = xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_set_selection_owner_checked_fn = func(*void, u32, u32, u32)->xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_get_selection_owner_fn         = func(*void, u32)->xcb_get_selection_owner_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_get_selection_owner_reply_fn   = func(*void, xcb_get_selection_owner_cookie_t, *(*xcb_generic_error_t?)?)->*xcb_get_selection_owner_reply_t?

#[Swag.CallingConvention(.C)]
alias xcb_convert_selection_checked_fn   = func(*void, u32, u32, u32, u32, u32)->xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_delete_property_checked_fn     = func(*void, u32, u32)->xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_get_file_descriptor_fn         = func(*void)->s32

#assert(#sizeof(xcb_property_notify_event_t) == 20)
#assert(#sizeof(xcb_selection_clear_event_t) == 16)
#assert(#sizeof(xcb_selection_request_event_t) == 28)
#assert(#sizeof(xcb_selection_notify_event_t) == 24)
#assert(#sizeof(xcb_get_selection_owner_reply_t) == 12)

// Xcursor image layout for XDND pointer thumbnails.
//
// The loaders borrow optional libX11/libXcursor handles; image and cursor resources
// have explicit destructors.
struct XcursorImage
{
    public
    {
        version: u32
        size:    u32
        width:   u32
        height:  u32
        xhot:    u32
        yhot:    u32
        delay:   u32
        pixels:  [*]u32
    }
}

#[Swag.CallingConvention(.C)]
alias XOpenDisplay_fn           = func(const [*]u8?)->*void?
#[Swag.CallingConvention(.C)]
alias XCloseDisplay_fn          = func(*void)->s32
#[Swag.CallingConvention(.C)]
alias XSync_fn                  = func(*void, s32)->s32
#[Swag.CallingConvention(.C)]
alias XFreeCursor_fn            = func(*void, u64)->s32
#[Swag.CallingConvention(.C)]
alias XcursorImageCreate_fn     = func(s32, s32)->*XcursorImage?
#[Swag.CallingConvention(.C)]
alias XcursorImageDestroy_fn    = func(*XcursorImage)->void
#[Swag.CallingConvention(.C)]
alias XcursorImageLoadCursor_fn = func(*void, const *XcursorImage)->u64
#[Swag.CallingConvention(.C)]
alias xcb_change_active_pointer_grab_checked_fn = func(*void, u32, u32, u16)->xcb_void_cookie_t

#assert(#sizeof(XcursorImage) == 40)
#assert(#offsetof(XcursorImage.pixels) == 32)
