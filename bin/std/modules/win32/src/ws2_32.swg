#global export

#foreignlib("ws2_32")
using Swag

alias SOCKET = u64

const INVALID_SOCKET     = Swag.U64.Max
const SOCKET_ERROR       = -1
const AF_INET            = 2
const SOCK_STREAM        = 1
const IPPROTO_TCP        = 6
const WSAVERNOTSUPPORTED = 10092

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
    func recv(handle: SOCKET, buffer: [*] u8, length, flags: s32)->s32
    func send(handle: SOCKET, buffer: const [*] u8, length, flags: s32)->s32
    func htons(value: u16)->u16
    func ntohs(value: u16)->u16
}
