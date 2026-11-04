#global if #os == Swag.TargetOs.Linux
#global export

struct statvfs
{
    public
    {
        f_bsize:   u64
        f_frsize:  u64
        f_blocks:  u64
        f_bfree:   u64
        f_bavail:  u64
        f_files:   u64
        f_ffree:   u64
        f_favail:  u64
        f_fsid:    u64
        f_flag:    u64
        f_namemax: u64
        f_type:    u32
        spare:     [5]s32
    }
}

#assert(#sizeof(statvfs) == 112)
#assert(#offsetof(statvfs.f_frsize) == 8)
#assert(#offsetof(statvfs.f_bavail) == 32)
#assert(#offsetof(statvfs.f_type) == 88)

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
func fstatvfs(fd: s32, buffer: *statvfs)->s32
