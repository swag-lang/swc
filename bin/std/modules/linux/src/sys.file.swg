#global if #os == Swag.TargetOs.Linux
#global export

const LOCK_SH = 1's32
const LOCK_EX = 2's32
const LOCK_NB = 4's32
const LOCK_UN = 8's32

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
func flock(fd: s32, operation: s32)->s32
