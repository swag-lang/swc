#global if #os == Swag.TargetOs.Linux
#global export

struct addrinfo
{
    public
    {
        ai_flags:     s32
        ai_family:    s32
        ai_socktype:  s32
        ai_protocol:  s32
        ai_addrlen:   u32
        ai_addr:      *sockaddr?
        ai_canonname: [*]u8?
        ai_next:      *addrinfo?
    }
}

const AF_UNSPEC = 0's32

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
{
    func getaddrinfo(node, service: const [*]u8?, hints: const *addrinfo?, result: *(*addrinfo?))->s32
    func freeaddrinfo(result: *addrinfo)
}
