#global if #os == Swag.TargetOs.Linux
#global export

const IPPROTO_TCP = 6's32

struct in_addr
{
    public s_addr: u32
}

struct sockaddr_in
{
    public
    {
        sin_family: u16
        sin_port:   u16
        sin_addr:   in_addr
        sin_zero:   [8] u8
    }
}

#assert(#sizeof(in_addr) == 4)
#assert(#sizeof(sockaddr_in) == 16)
#assert(#offsetof(sockaddr_in.sin_addr) == 4)

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
{
    func htons(value: u16)->u16
    func ntohs(value: u16)->u16
    func htonl(value: u32)->u32
    func ntohl(value: u32)->u32
}
