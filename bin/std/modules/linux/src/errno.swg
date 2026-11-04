#global if #os == Swag.TargetOs.Linux
#global export

const EPERM        = 1's32
const ENOENT       = 2's32
const ESRCH        = 3's32
const EINTR        = 4's32
const EIO          = 5's32
const EBADF        = 9's32
const ECHILD       = 10's32
const EAGAIN       = 11's32
const ENOMEM       = 12's32
const EACCES       = 13's32
const EBUSY        = 16's32
const EEXIST       = 17's32
const EXDEV        = 18's32
const ENODEV       = 19's32
const ENOTTY       = 25's32
const ENOTDIR      = 20's32
const EISDIR       = 21's32
const EINVAL       = 22's32
const ENOSPC       = 28's32
const EROFS        = 30's32
const ENOSYS       = 38's32
const EOVERFLOW    = 75's32
const EPIPE        = 32's32
const ERANGE       = 34's32
const ENAMETOOLONG = 36's32
const ENOTEMPTY    = 39's32

const ELOOP = 40's32

const ENOTSUP      = 95's32
const EADDRINUSE   = 98's32
const ECONNREFUSED = 111's32

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
