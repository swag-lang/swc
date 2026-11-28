#global if #os == Swag.TargetOs.Linux
#global export

struct ifaddrs
{
    public
    {
        ifa_next:    *ifaddrs?
        ifa_name:    [*] u8?
        ifa_flags:   u32
        ifa_addr:    *sockaddr?
        ifa_netmask: *sockaddr?
        ifa_ifu:     union
        {
            ifu_broadaddr: *sockaddr?
            ifu_dstaddr:   *sockaddr?
        }
        ifa_data: *void?
    }
}

#assert(#sizeof(ifaddrs) == 56)
#assert(#offsetof(ifaddrs.ifa_addr) == 24)
#assert(#offsetof(ifaddrs.ifa_data) == 48)

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
{
    func getifaddrs(ifap: *(*ifaddrs?))->s32
    func freeifaddrs(ifa: *ifaddrs)
}
