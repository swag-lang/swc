#global if #os == Swag.TargetOs.Linux
#global public

const IFF_LOOPBACK = 8_u32

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
func if_nametoindex(ifname: const [*] u8)->u32
