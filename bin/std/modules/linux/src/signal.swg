#global if #os == Swag.TargetOs.Linux
#global export

const SIGKILL     = 9's32
const SIGPIPE     = 13's32
const SIGTERM     = 15's32
const SIGCHLD     = 17's32
const SIG_BLOCK   = 0's32
const SIG_UNBLOCK = 1's32
const SIG_SETMASK = 2's32

// Opaque glibc x86-64 signal set; manipulate it through the native sigset functions.
struct sigset_t
{
    private storage: [16] u64
}

// Opaque glibc x86-64 signal information; optional when only the signal number is needed.
struct siginfo_t
{
    private storage: [16] u64
}

#assert(#sizeof(sigset_t) == 128)
#assert(#sizeof(siginfo_t) == 128)

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
{
    func sigemptyset(set: *sigset_t)->s32
    func sigaddset(set: *sigset_t, signal: s32)->s32
    func sigismember(set: const *sigset_t, signal: s32)->s32
    func sigpending(set: *sigset_t)->s32
    func sigtimedwait(set: const *sigset_t, info: *siginfo_t?, timeout: const *timespec?)->s32
    func kill(pid: s32, signal: s32)->s32
}
