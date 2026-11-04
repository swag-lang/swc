#global if #os == Swag.TargetOs.Linux
#global export

const FIONREAD = 0x541B'u64

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
func ioctl(fd: s32, request: u64, args: ...)->s32
