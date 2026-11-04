#global if #os == Swag.TargetOs.Linux
#global export

const POSIX_SPAWN_RESETIDS   = 0x01's16
const POSIX_SPAWN_SETPGROUP  = 0x02's16
const POSIX_SPAWN_SETSIGDEF  = 0x04's16
const POSIX_SPAWN_SETSIGMASK = 0x08's16
const POSIX_SPAWN_SETSID     = 0x80's16

// Opaque glibc x86-64 spawn attributes, initialized and destroyed by the native API.
struct posix_spawnattr_t
{
    private storage: [42] u64
}

// Opaque glibc x86-64 file-action list; destroy it after every successful initialization.
struct posix_spawn_file_actions_t
{
    private storage: [10] u64
}

#assert(#sizeof(posix_spawnattr_t) == 336)
#assert(#sizeof(posix_spawn_file_actions_t) == 80)

// These functions return an error number directly rather than reporting failure through errno.
#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
{
    func posix_spawn(pid: *s32?, path: const [*] u8, file_actions: const *posix_spawn_file_actions_t?, attrp: const *posix_spawnattr_t?, argv: const [*] ([*] u8?), envp: const [*] ([*] u8?)?)->s32
    func posix_spawnp(pid: *s32?, file: const [*] u8, file_actions: const *posix_spawn_file_actions_t?, attrp: const *posix_spawnattr_t?, argv: const [*] ([*] u8?), envp: const [*] ([*] u8?)?)->s32
    func posix_spawn_file_actions_init(file_actions: *posix_spawn_file_actions_t)->s32
    func posix_spawn_file_actions_destroy(file_actions: *posix_spawn_file_actions_t)->s32
    func posix_spawn_file_actions_addclose(file_actions: *posix_spawn_file_actions_t, fd: s32)->s32
    func posix_spawn_file_actions_adddup2(file_actions: *posix_spawn_file_actions_t, fd, newfd: s32)->s32
    func posix_spawn_file_actions_addopen(file_actions: *posix_spawn_file_actions_t, fd: s32, path: const [*] u8, oflag: s32, mode: u32)->s32
    func posix_spawn_file_actions_addchdir_np(file_actions: *posix_spawn_file_actions_t, path: const [*] u8)->s32
    func posix_spawnattr_init(attributes: *posix_spawnattr_t)->s32
    func posix_spawnattr_destroy(attributes: *posix_spawnattr_t)->s32
    func posix_spawnattr_setflags(attributes: *posix_spawnattr_t, flags: s16)->s32
    func posix_spawnattr_setsigdefault(attributes: *posix_spawnattr_t, sigdefault: const *sigset_t)->s32
    func posix_spawnattr_setsigmask(attributes: *posix_spawnattr_t, sigmask: const *sigset_t)->s32
    func posix_spawnattr_setpgroup(attributes: *posix_spawnattr_t, pgroup: s32)->s32
}
