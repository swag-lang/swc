#global if #os == Swag.TargetOs.Linux
#global export

const AF_PACKET = 17'u16

struct sockaddr
{
    public
    {
        sa_family: u16
        sa_data:   [14] u8
    }
}

#assert(#sizeof(sockaddr) == 16)

const AF_INET      = 2's32
const SOCK_STREAM  = 1's32
const SOCK_CLOEXEC = 0x80000's32
const MSG_NOSIGNAL = 0x4000's32
const SOL_SOCKET   = 1's32
const SO_ERROR     = 4's32
const SHUT_WR      = 1's32

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
{
    func socket(domain: s32, kind: s32, protocol: s32)->s32
    func connect(fd: s32, address: const *sockaddr, length: u32)->s32
    func bind(fd: s32, address: const *sockaddr, length: u32)->s32
    func listen(fd: s32, backlog: s32)->s32
    func accept4(fd: s32, address: *sockaddr?, length: *u32?, flags: s32)->s32
    func getsockname(fd: s32, address: *sockaddr, length: *u32)->s32
    func getsockopt(fd: s32, level: s32, option: s32, value: *void, length: *u32)->s32
    func recv(fd: s32, buffer: *void, size: u64, flags: s32)->s64
    func send(fd: s32, buffer: const *void, size: u64, flags: s32)->s64
    func shutdown(fd: s32, how: s32)->s32
}
