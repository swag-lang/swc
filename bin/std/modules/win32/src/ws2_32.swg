#global export

#foreignlib("ws2_32")
using Swag

alias SOCKET = u64

const INVALID_SOCKET     = Swag.U64.Max
const SOCKET_ERROR       = -1
const AF_INET            = 2
const AF_INET6           = 23
const AF_UNSPEC          = 0
const SOCK_STREAM        = 1
const SOCK_DGRAM         = 2
const SD_SEND             = 1
const SOL_SOCKET          = 0xFFFF
const SO_KEEPALIVE        = 0x0008
const SO_RCVTIMEO         = 0x1006
const IPPROTO_TCP        = 6
const IPPROTO_UDP        = 17
const TCP_NODELAY        = 1
const IPPROTO_IP         = 0
const IPPROTO_IPV6       = 41
const SO_BROADCAST       = 0x20
const IP_ADD_MEMBERSHIP  = 12
const IP_DROP_MEMBERSHIP = 13
const IPV6_JOIN_GROUP    = 12
const IPV6_LEAVE_GROUP   = 13
const AI_PASSIVE         = 1
const AI_NUMERICHOST     = 4
const AI_NUMERICSERV     = 8
const WSAVERNOTSUPPORTED = 10092
const WSAEMSGSIZE         = 10040

struct WSADATA
{
    public
    {
        wVersion:       WORD
        wHighVersion:   WORD
        iMaxSockets:    WORD
        iMaxUdpDg:      WORD
        lpVendorInfo:   [*] u8?
        szDescription:  [257] u8
        szSystemStatus: [129] u8
    }
}

struct IN_ADDR
{
    public S_un: union
    {
        S_un_b: struct { s_b1, s_b2, s_b3, s_b4: u8 }
        S_un_w: struct { s_w1, s_w2: u16 }
        S_addr: u32
    }
}

struct SOCKADDR
{
    public
    {
        sa_family: u16
        sa_data:   [14] u8
    }
}

struct SOCKADDR_IN
{
    public
    {
        sin_family: u16
        sin_port:   u16
        sin_addr:   IN_ADDR
        sin_zero:   [8] u8
    }
}

struct IN6_ADDR
{
    public u6_addr: union
    {
        Byte: [16] u8
        Word: [8] u16
    }
}

struct SOCKADDR_IN6
{
    public
    {
        sin6_family:   u16
        sin6_port:     u16
        sin6_flowinfo: u32
        sin6_addr:     IN6_ADDR
        sin6_scope_id: u32
    }
}

struct IP_MREQ
{
    public
    {
        imr_multiaddr: IN_ADDR
        imr_interface: IN_ADDR
    }
}

struct IPV6_MREQ
{
    public
    {
        ipv6mr_multiaddr: IN6_ADDR
        ipv6mr_interface: u32
    }
}

#assert(#sizeof(IP_MREQ) == 8)
#assert(#sizeof(IPV6_MREQ) == 20)

struct ADDRINFOA
{
    public
    {
        ai_flags:     s32
        ai_family:    s32
        ai_socktype:  s32
        ai_protocol:  s32
        ai_addrlen:   u64
        ai_addr:      *SOCKADDR?
        ai_canonname: [*]u8?
        ai_next:      *ADDRINFOA?
    }
}

#assert(#sizeof(IN6_ADDR) == 16)
#assert(#sizeof(SOCKADDR_IN6) == 28)
#assert(#sizeof(ADDRINFOA) == 48)

#[Foreign("ws2_32", callconv: Swag.CallConv.C)]
{
    func WSAStartup(version: WORD, data: *WSADATA)->s32
    func WSACleanup()->s32
    func WSAGetLastError()->s32
    func socket(af, type, protocol: s32)->SOCKET
    func closesocket(handle: SOCKET)->s32
    func connect(handle: SOCKET, address: const *SOCKADDR, length: s32)->s32
    func bind(handle: SOCKET, address: const *SOCKADDR, length: s32)->s32
    func listen(handle: SOCKET, backlog: s32)->s32
    func accept(handle: SOCKET, address: *SOCKADDR?, length: *s32?)->SOCKET
    func getsockname(handle: SOCKET, address: *SOCKADDR, length: *s32)->s32
    func setsockopt(handle: SOCKET, level, option: s32, value: const *u8, length: s32)->s32
    func recv(handle: SOCKET, buffer: [*] u8, length, flags: s32)->s32
    func send(handle: SOCKET, buffer: const [*] u8, length, flags: s32)->s32
    func shutdown(handle: SOCKET, how: s32)->s32
    func recvfrom(handle: SOCKET, buffer: [*] u8, length, flags: s32, address: *SOCKADDR?, addressLength: *s32?)->s32
    func sendto(handle: SOCKET, buffer: const [*] u8, length, flags: s32, address: const *SOCKADDR, addressLength: s32)->s32
    func getaddrinfo(node, service: const [*]u8?, hints: const *ADDRINFOA?, result: *(*ADDRINFOA?))->s32
    func freeaddrinfo(result: *ADDRINFOA)
    func htons(value: u16)->u16
    func ntohs(value: u16)->u16
    func htonl(value: u32)->u32
}
