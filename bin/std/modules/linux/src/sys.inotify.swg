#global if #os == Swag.TargetOs.Linux
#global public

const IN_ACCESS      = 0x00000001_u32
const IN_MODIFY      = 0x00000002_u32
const IN_ATTRIB      = 0x00000004_u32
const IN_MOVED_FROM  = 0x00000040_u32
const IN_MOVED_TO    = 0x00000080_u32
const IN_CREATE      = 0x00000100_u32
const IN_DELETE      = 0x00000200_u32
const IN_DELETE_SELF = 0x00000400_u32
const IN_MOVE_SELF   = 0x00000800_u32
const IN_UNMOUNT     = 0x00002000_u32
const IN_Q_OVERFLOW  = 0x00004000_u32
const IN_IGNORED     = 0x00008000_u32
const IN_ONLYDIR     = 0x01000000_u32
const IN_DONT_FOLLOW = 0x02000000_u32
const IN_EXCL_UNLINK = 0x04000000_u32
const IN_ISDIR       = 0x40000000_u32
const IN_NONBLOCK    = O_NONBLOCK
const IN_CLOEXEC     = O_CLOEXEC

// Fixed header followed by len bytes containing a zero-terminated name and padding.
struct inotify_event
{
    public
    {
        wd:     s32
        mask:   u32
        cookie: u32
        len:    u32
    }
}

#assert(#sizeof(inotify_event) == 16)
#assert(#offsetof(inotify_event.len) == 12)

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
{
    func inotify_init1(flags: s32)->s32
    func inotify_add_watch(fd: s32, pathname: const [*] u8, mask: u32)->s32
    func inotify_rm_watch(fd: s32, wd: s32)->s32
}
