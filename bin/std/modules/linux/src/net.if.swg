#global if #os == Swag.TargetOs.Linux
#global export

const IFF_LOOPBACK = 8'u32

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
func if_nametoindex(ifname: const [*] u8)->u32
