#global if #os == Swag.TargetOs.Linux
#global export

// MIT-SHM requests sent through libxcb.so.1; no extension library is needed.
// The descriptor and request vectors follow libxcb's xcbext ABI.
struct xcb_iovec_t
{
    public
    {
        base:   *void?
        length: u64
    }
}

struct xcb_protocol_request_t
{
    public
    {
        count:  u64
        ext:    *xcb_extension_t?
        opcode: u8
        isvoid: u8
    }
}

struct xcb_shm_attach_request_t
{
    public
    {
        major_opcode: u8
        minor_opcode: u8
        length:       u16
        segment:      u32
        shmid:        u32
        read_only:    u8
        pad0:         [3] u8
    }
}

struct xcb_shm_detach_request_t
{
    public
    {
        major_opcode: u8
        minor_opcode: u8
        length:       u16
        segment:      u32
    }
}

struct xcb_shm_get_image_request_t
{
    public
    {
        major_opcode: u8
        minor_opcode: u8
        length:       u16
        drawable:     u32
        x:            s16
        y:            s16
        width:        u16
        height:       u16
        plane_mask:   u32
        format:       u8
        pad0:         [3] u8
        segment:      u32
        offset:       u32
    }
}

// The first 12 bytes match xcb_get_image_reply_t; the size follows at offset 12.
struct xcb_shm_get_image_reply_t
{
    public
    {
        response_type: u8
        depth:         u8
        sequence:      u16
        length:        u32
        visual:        u32
        size:          u32
        pad0:          [16] u8
    }
}

#[Swag.CallingConvention(.C)]
alias xcb_send_request_fn = func(*void, s32, *xcb_iovec_t, const *xcb_protocol_request_t)->u32

#[Swag.CallingConvention(.C)]
alias xcb_wait_for_reply_fn = func(*void, u32, *(*xcb_generic_error_t?)?)->*xcb_get_image_reply_t?

#assert(#sizeof(xcb_iovec_t) == 16)
#assert(#sizeof(xcb_protocol_request_t) == 24)
#assert(#sizeof(xcb_shm_attach_request_t) == 16)
#assert(#sizeof(xcb_shm_detach_request_t) == 8)
#assert(#sizeof(xcb_shm_get_image_request_t) == 32)
#assert(#sizeof(xcb_shm_get_image_reply_t) == 32)
#assert(#offsetof(xcb_shm_get_image_reply_t.size) == #offsetof(xcb_get_image_reply_t.pad0))
