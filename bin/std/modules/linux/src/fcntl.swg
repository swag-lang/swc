#global if #os == Swag.TargetOs.Linux
#global export

const AT_FDCWD = -100's32

const O_RDONLY   = 0's32
const O_RDWR     = 2's32
const O_NONBLOCK = 0x800's32
const O_CLOEXEC  = 0x80000's32

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
func openat(dirfd: s32, pathname: const [*] u8, flags: s32, args: ...)->s32
