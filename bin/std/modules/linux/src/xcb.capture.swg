#global if #os == Swag.TargetOs.Linux
#global export

// XCB image, visual and window-query layouts from libxcb 1.17 and XFixes headers.
// Function pointers borrow the loaded library; reply/error buffers use libc free.

struct xcb_format_t
{
    public
    {
        depth:          u8
        bits_per_pixel: u8
        scanline_pad:   u8
        pad0:           [5] u8
    }
}

struct xcb_visualtype_t
{
    public
    {
        visual_id:          u32
        _class:             u8
        bits_per_rgb_value: u8
        colormap_entries:   u16
        red_mask:           u32
        green_mask:         u32
        blue_mask:          u32
        pad0:               [4] u8
    }
}

struct xcb_depth_t
{
    public
    {
        depth:       u8
        pad0:        u8
        visuals_len: u16
        pad1:        [4] u8
    }
}

struct xcb_get_window_attributes_reply_t
{
    public
    {
        response_type:         u8
        backing_store:         u8
        sequence:              u16
        length:                u32
        visual:                u32
        _class:                u16
        bit_gravity:           u8
        win_gravity:           u8
        backing_planes:        u32
        backing_pixel:         u32
        save_under:            u8
        map_is_installed:      u8
        map_state:             u8
        override_redirect:     u8
        colormap:              u32
        all_event_masks:       u32
        your_event_mask:       u32
        do_not_propagate_mask: u16
        pad0:                  [2] u8
    }
}

struct xcb_query_tree_reply_t
{
    public
    {
        response_type: u8
        pad0:          u8
        sequence:      u16
        length:        u32
        root:          u32
        parent:        u32
        children_len:  u16
        pad1:          [14] u8
    }
}

struct xcb_translate_coordinates_reply_t
{
    public
    {
        response_type: u8
        same_screen:   u8
        sequence:      u16
        length:        u32
        child:         u32
        dst_x:         s16
        dst_y:         s16
    }
}

struct xcb_get_image_reply_t
{
    public
    {
        response_type: u8
        depth:         u8
        sequence:      u16
        length:        u32
        visual:        u32
        pad0:          [20] u8
    }
}

struct xcb_xfixes_get_cursor_image_reply_t
{
    public
    {
        response_type: u8
        pad0:          u8
        sequence:      u16
        length:        u32
        x:             s16
        y:             s16
        width:         u16
        height:        u16
        xhot:          u16
        yhot:          u16
        cursor_serial: u32
        pad1:          [8] u8
    }
}

struct xcb_format_iterator_t
{
    public
    {
        data:  *xcb_format_t?
        rem:   s32
        index: s32
    }
}

struct xcb_depth_iterator_t
{
    public
    {
        data:  *xcb_depth_t?
        rem:   s32
        index: s32
    }
}

struct xcb_visualtype_iterator_t
{
    public
    {
        data:  *xcb_visualtype_t?
        rem:   s32
        index: s32
    }
}

alias xcb_get_image_cookie_t                             = xcb_void_cookie_t
alias xcb_query_tree_cookie_t                            = xcb_void_cookie_t
alias xcb_get_window_attributes_cookie_t                 = xcb_void_cookie_t
alias xcb_translate_coordinates_cookie_t                 = xcb_void_cookie_t
alias xcb_xfixes_get_cursor_image_cookie_t               = xcb_void_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_get_image_fn                                   = func(*void, u8, u32, s16, s16, u16, u16, u32)->xcb_get_image_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_get_image_reply_fn                             = func(*void, xcb_get_image_cookie_t, *(*xcb_generic_error_t?)?)->*xcb_get_image_reply_t?

#[Swag.CallingConvention(.C)]
alias xcb_query_tree_fn                                  = func(*void, u32)->xcb_query_tree_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_query_tree_reply_fn                            = func(*void, xcb_query_tree_cookie_t, *(*xcb_generic_error_t?)?)->*xcb_query_tree_reply_t?

#[Swag.CallingConvention(.C)]
alias xcb_get_window_attributes_fn                       = func(*void, u32)->xcb_get_window_attributes_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_get_window_attributes_reply_fn                 = func(*void, xcb_get_window_attributes_cookie_t, *(*xcb_generic_error_t?)?)->*xcb_get_window_attributes_reply_t?

#[Swag.CallingConvention(.C)]
alias xcb_translate_coordinates_fn                       = func(*void, u32, u32, s16, s16)->xcb_translate_coordinates_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_translate_coordinates_reply_fn                 = func(*void, xcb_translate_coordinates_cookie_t, *(*xcb_generic_error_t?)?)->*xcb_translate_coordinates_reply_t?

#[Swag.CallingConvention(.C)]
alias xcb_xfixes_get_cursor_image_fn                     = func(*void)->xcb_xfixes_get_cursor_image_cookie_t

#[Swag.CallingConvention(.C)]
alias xcb_xfixes_get_cursor_image_reply_fn               = func(*void, xcb_xfixes_get_cursor_image_cookie_t, *(*xcb_generic_error_t?)?)->*xcb_xfixes_get_cursor_image_reply_t?

#[Swag.CallingConvention(.C)]
alias xcb_get_image_data_fn                              = func(const *xcb_get_image_reply_t)->[*] u8

#[Swag.CallingConvention(.C)]
alias xcb_get_image_data_length_fn                       = func(const *xcb_get_image_reply_t)->s32

#[Swag.CallingConvention(.C)]
alias xcb_query_tree_children_fn                         = func(const *xcb_query_tree_reply_t)->[*] u32

#[Swag.CallingConvention(.C)]
alias xcb_query_tree_children_length_fn                  = func(const *xcb_query_tree_reply_t)->s32

#[Swag.CallingConvention(.C)]
alias xcb_setup_pixmap_formats_iterator_fn               = func(const *xcb_setup_t)->xcb_format_iterator_t

#[Swag.CallingConvention(.C)]
alias xcb_format_next_fn                                 = func(*xcb_format_iterator_t)

#[Swag.CallingConvention(.C)]
alias xcb_screen_allowed_depths_iterator_fn              = func(const *xcb_screen_t)->xcb_depth_iterator_t

#[Swag.CallingConvention(.C)]
alias xcb_depth_next_fn                                  = func(*xcb_depth_iterator_t)

#[Swag.CallingConvention(.C)]
alias xcb_depth_visuals_iterator_fn                      = func(const *xcb_depth_t)->xcb_visualtype_iterator_t

#[Swag.CallingConvention(.C)]
alias xcb_visualtype_next_fn                             = func(*xcb_visualtype_iterator_t)

#[Swag.CallingConvention(.C)]
alias xcb_xfixes_get_cursor_image_cursor_image_fn        = func(const *xcb_xfixes_get_cursor_image_reply_t)->[*] u32

#[Swag.CallingConvention(.C)]
alias xcb_xfixes_get_cursor_image_cursor_image_length_fn = func(const *xcb_xfixes_get_cursor_image_reply_t)->s32

#assert(#sizeof(xcb_format_t) == 8)
#assert(#sizeof(xcb_visualtype_t) == 24)
#assert(#sizeof(xcb_depth_t) == 8)
#assert(#sizeof(xcb_get_window_attributes_reply_t) == 44)
#assert(#sizeof(xcb_query_tree_reply_t) == 32)
#assert(#sizeof(xcb_translate_coordinates_reply_t) == 16)
#assert(#sizeof(xcb_get_image_reply_t) == 32)
#assert(#sizeof(xcb_xfixes_get_cursor_image_reply_t) == 32)
#assert(#sizeof(xcb_format_iterator_t) == 16)
#assert(#sizeof(xcb_depth_iterator_t) == 16)
#assert(#sizeof(xcb_visualtype_iterator_t) == 16)
