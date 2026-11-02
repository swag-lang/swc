#global if #os == Swag.TargetOs.Linux
#global export

const POLLIN   = 0x001's16
const POLLOUT  = 0x004's16
const POLLERR  = 0x008's16
const POLLHUP  = 0x010's16
const POLLNVAL = 0x020's16

struct pollfd
{
    public
    {
        fd:      s32
        events:  s16
        revents: s16
    }
}

#assert(#sizeof(pollfd) == 8)
#assert(#offsetof(pollfd.revents) == 6)

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
func poll(fds: [*] pollfd, nfds: u64, timeout: s32)->s32
