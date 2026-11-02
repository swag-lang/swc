#global if #os == Swag.TargetOs.Linux
#global export

const AT_FDCWD            = -100's32
const AT_SYMLINK_NOFOLLOW = 0x100's32
const AT_REMOVEDIR        = 0x200's32
const AT_EMPTY_PATH       = 0x1000's32
const F_DUPFD_CLOEXEC     = 1030's32
const F_GETFD             = 1's32
const F_GETFL             = 3's32
const F_SETFL             = 4's32
const FD_CLOEXEC          = 1's32

const O_RDONLY    = 0's32
const O_WRONLY    = 1's32
const O_CREAT     = 0x40's32
const O_EXCL      = 0x80's32
const O_NOCTTY    = 0x100's32
const O_TRUNC     = 0x200's32
const O_RDWR      = 2's32
const O_NONBLOCK  = 0x800's32
const O_DIRECTORY = 0x10000's32
const O_CLOEXEC   = 0x80000's32
const O_PATH      = 0x200000's32

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
func openat(dirfd: s32, pathname: const [*] u8, flags: s32, args: ...)->s32

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
func fcntl(fd: s32, cmd: s32, args: ...)->s32
