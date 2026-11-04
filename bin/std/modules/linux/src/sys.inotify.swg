#global if #os == Swag.TargetOs.Linux
#global export

const IN_ACCESS      = 0x00000001'u32
const IN_MODIFY      = 0x00000002'u32
const IN_ATTRIB      = 0x00000004'u32
const IN_MOVED_FROM  = 0x00000040'u32
const IN_MOVED_TO    = 0x00000080'u32
const IN_CREATE      = 0x00000100'u32
const IN_DELETE      = 0x00000200'u32
const IN_DELETE_SELF = 0x00000400'u32
const IN_MOVE_SELF   = 0x00000800'u32
const IN_UNMOUNT     = 0x00002000'u32
const IN_Q_OVERFLOW  = 0x00004000'u32
const IN_IGNORED     = 0x00008000'u32
const IN_ONLYDIR     = 0x01000000'u32
const IN_DONT_FOLLOW = 0x02000000'u32
const IN_EXCL_UNLINK = 0x04000000'u32
const IN_ISDIR       = 0x40000000'u32
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
