#global if #os == Swag.TargetOs.Linux
#global export

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
func renameat(olddirfd: s32, oldpath: const [*] u8, newdirfd: s32, newpath: const [*] u8)->s32
