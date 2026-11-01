#global if #os == Swag.TargetOs.Linux
#global export

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
{
    func getpagesize()->s32
    func ftruncate(fd: s32, length: s64)->s32
    func pipe2(pipefd: [*] s32, flags: s32)->s32
    func write(fd: s32, buf: const *void, count: u64)->s64
    func close(fd: s32)->s32
}
