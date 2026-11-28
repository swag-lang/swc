#global if #os == Swag.TargetOs.Linux
#global export

struct dirent
{
    public
    {
        d_ino:    u64
        d_off:    s64
        d_reclen: u16
        d_type:   u8
        d_name:   [256] u8
    }
}

#assert(#sizeof(dirent) == 280)

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
{
    func opendir(name: const [*] u8)->*void?
    func closedir(dirp: *void)->s32
    func readdir(dirp: *void)->*dirent?
    func rewinddir(dirp: *void)
    func dirfd(dirp: *void)->s32
}
