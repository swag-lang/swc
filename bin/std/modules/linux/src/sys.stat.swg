#global if #os == Swag.TargetOs.Linux
#global export

const UTIME_NOW  = 1_073_741_823's64
const UTIME_OMIT = 1_073_741_822's64

const S_IFMT  = 0xF000'u32
const S_IFREG = 0x8000'u32
const S_IFDIR = 0x4000'u32
const S_IFLNK = 0xA000'u32
const S_IFBLK = 0x6000'u32
const S_IFCHR = 0x2000'u32
const S_IWUSR = 0x80'u32
const S_IWGRP = 0x10'u32
const S_IWOTH = 0x2'u32

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
    func mkdirat(dirfd: s32, pathname: const [*] u8, mode: u32)->s32
    func chmod(pathname: const [*] u8, mode: u32)->s32
    func utimensat(dirfd: s32, pathname: const [*] u8, times: const [*] timespec?, flags: s32)->s32
    func statx(dirfd: s32, pathname: const [*] u8, flags: s32, mask: u32, statxbuf: *Structs.statx)->s32
    func fstat(fd: s32, statbuf: *stat)->s32
    func fstatat(dirfd: s32, pathname: const [*] u8, statbuf: *stat, flags: s32)->s32
}
