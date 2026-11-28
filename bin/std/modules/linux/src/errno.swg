#global if #os == Swag.TargetOs.Linux
#global export

const EPERM        = 1_s32
const ENOENT       = 2_s32
const ESRCH        = 3_s32
const EINTR        = 4_s32
const EIO          = 5_s32
const EBADF        = 9_s32
const ECHILD       = 10_s32
const EAGAIN       = 11_s32
const ENOMEM       = 12_s32
const EACCES       = 13_s32
const EBUSY        = 16_s32
const EEXIST       = 17_s32
const EXDEV        = 18_s32
const ENODEV       = 19_s32
const ENOTTY       = 25_s32
const ENOTDIR      = 20_s32
const EISDIR       = 21_s32
const EINVAL       = 22_s32
const ENOSPC       = 28_s32
const EROFS        = 30_s32
const ENOSYS       = 38_s32
const EOVERFLOW    = 75_s32
const EPIPE        = 32_s32
const ERANGE       = 34_s32
const ENAMETOOLONG = 36_s32
const ENOTEMPTY    = 39_s32

const ELOOP = 40_s32

const ENOTSUP      = 95_s32
const EADDRINUSE   = 98_s32
const ETIMEDOUT    = 110_s32
const ECONNREFUSED = 111_s32

// Returns the address of the calling thread's native errno value.
//
// The foreign symbol is `__errno_location`; its leading underscores are reserved in Swag.
#[Swag.Foreign(module: "libc.so.6", function: "__errno_location", link: "c", callconv: .C)]
func errnoLocation()->*s32

// Reads the calling thread's native errno value; Swag exposes the C macro as a function.
#[Swag.Inline]
func errno()->s32 => errnoLocation()[]

// Replaces the calling thread's native errno value before an operation whose null result is ambiguous.
#[Swag.Inline]
func errno(value: s32)
{
    errnoLocation()[] = value
}
