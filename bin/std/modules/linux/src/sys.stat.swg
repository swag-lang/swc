#global if #os == Swag.TargetOs.Linux
#global export

const S_IFMT  = 0xF000'u32
const S_IFREG = 0x8000'u32
const S_IFDIR = 0x4000'u32
const S_IFLNK = 0xA000'u32

struct stat
{
    public
    {
        st_dev:   u64
        st_ino:   u64
        st_nlink: u64
        st_mode:  u32
        st_uid:   u32
        st_gid:   u32
    }

    private padding: s32

    public
    {
        st_rdev:    u64
        st_size:    s64
        st_blksize: s64
        st_blocks:  s64
        st_atim:    timespec
        st_mtim:    timespec
        st_ctim:    timespec
    }

    private reserved: [3] s64
}

#assert(#sizeof(stat) == 144)

#[Swag.Foreign(module: "libc.so.6", link: "c", callconv: .C)]
{
    func fstat(fd: s32, statbuf: *stat)->s32
    func fstatat(dirfd: s32, pathname: const [*] u8, statbuf: *stat, flags: s32)->s32
}
