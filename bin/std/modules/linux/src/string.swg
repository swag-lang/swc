#global if #os == Swag.TargetOs.Linux
#global export

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
func explicit_bzero(s: *void, n: u64)

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
func strerror(errnum: s32)->[*] u8
