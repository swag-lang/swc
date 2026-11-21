#global if #os == Swag.TargetOs.Linux
#global export

const IPPROTO_TCP = 6's32
const IPPROTO_UDP = 17's32
const TCP_NODELAY = 1's32
const IPPROTO_IP = 0's32
const IPPROTO_IPV6 = 41's32
const IP_ADD_MEMBERSHIP = 35's32
const IP_DROP_MEMBERSHIP = 36's32
const IPV6_JOIN_GROUP = 20's32
const IPV6_LEAVE_GROUP = 21's32

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

struct in6_addr
{
    public s6_addr: [16] u8
}

struct ip_mreq
{
    public
    {
        imr_multiaddr: in_addr
        imr_interface: in_addr
    }
}

struct ipv6_mreq
{
    public
    {
        ipv6mr_multiaddr: in6_addr
        ipv6mr_interface: u32
    }
}

struct sockaddr_in6
{
    public
    {
        sin6_family:   u16
        sin6_port:     u16
        sin6_flowinfo: u32
        sin6_addr:     in6_addr
        sin6_scope_id: u32
    }
}

#assert(#sizeof(in_addr) == 4)
#assert(#sizeof(sockaddr_in) == 16)
#assert(#offsetof(sockaddr_in.sin_addr) == 4)
#assert(#sizeof(in6_addr) == 16)
#assert(#sizeof(sockaddr_in6) == 28)
#assert(#offsetof(sockaddr_in6.sin6_addr) == 8)

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
{
    func htons(value: u16)->u16
    func ntohs(value: u16)->u16
    func htonl(value: u32)->u32
    func ntohl(value: u32)->u32
}
