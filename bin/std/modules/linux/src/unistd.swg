#global if #os == Swag.TargetOs.Linux
#global export

const SEEK_SET = 0's32
const SEEK_CUR = 1's32
const SEEK_END = 2's32

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
{
    func getentropy(buffer: *void, length: u64)->s32
    func getpagesize()->s32
    func isatty(fd: s32)->s32
    func getpid()->s32
    func getcwd(buf: [*] u8?, size: u64)->[*] u8?
    func chdir(path: const [*] u8)->s32
    func unlinkat(dirfd: s32, pathname: const [*] u8, flags: s32)->s32
    func symlinkat(target: const [*] u8, newdirfd: s32, linkpath: const [*] u8)->s32
    func ftruncate(fd: s32, length: s64)->s32
    func pipe2(pipefd: [*] s32, flags: s32)->s32
    func read(fd: s32, buf: *void, count: u64)->s64
    func lseek(fd: s32, offset: s64, whence: s32)->s64
    func fsync(fd: s32)->s32
    func write(fd: s32, buf: const *void, count: u64)->s64
    func close(fd: s32)->s32
}
