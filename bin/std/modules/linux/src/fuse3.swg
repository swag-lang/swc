#global if #os == Swag.TargetOs.Linux
#global export

// High-level libfuse 3 ABI, from the upstream 3.17.2 headers.
// The optional library is loaded by its owner; these aliases do not acquire a mount.
// File-info members used by the adapter belong to the stable libfuse 3 prefix.
struct fuse_args
{
    public
    {
        argc:      s32
        argv:      [*](*u8?)?
        allocated: s32
    }
}

struct fuse_file_info
{
    public
    {
        flags:        s32
        flags_bits:   u32
        padding2:     u32
        padding3:     u32
        fh:           u64
        lock_owner:   u64
        poll_events:  u32
        backing_id:   s32
        compat_flags: u64
        reserved:     [2]u64
    }
}

struct fuse_context
{
    public
    {
        fuse:         *void?
        uid:          u32
        gid:          u32
        pid:          s32
        private_data: *void?
        umask:        u32
    }
}

#[Swag.CallingConvention(.C)]
alias fuse_getattr_fn       = func(const [*]u8, *stat, *fuse_file_info?)->s32

#[Swag.CallingConvention(.C)]
alias fuse_path_fn          = func(const [*]u8)->s32

#[Swag.CallingConvention(.C)]
alias fuse_mkdir_fn         = func(const [*]u8, u32)->s32

#[Swag.CallingConvention(.C)]
alias fuse_rename_fn        = func(const [*]u8, const [*]u8, u32)->s32

#[Swag.CallingConvention(.C)]
alias fuse_chmod_fn         = func(const [*]u8?, u32, *fuse_file_info?)->s32

#[Swag.CallingConvention(.C)]
alias fuse_chown_fn         = func(const [*]u8?, u32, u32, *fuse_file_info?)->s32

#[Swag.CallingConvention(.C)]
alias fuse_truncate_fn      = func(const [*]u8?, s64, *fuse_file_info?)->s32

#[Swag.CallingConvention(.C)]
alias fuse_open_fn          = func(const [*]u8, *fuse_file_info)->s32

#[Swag.CallingConvention(.C)]
alias fuse_read_fn          = func(const [*]u8?, [*]u8, u64, s64, *fuse_file_info)->s32

#[Swag.CallingConvention(.C)]
alias fuse_write_fn         = func(const [*]u8?, const [*]u8, u64, s64, *fuse_file_info)->s32

#[Swag.CallingConvention(.C)]
alias fuse_statfs_fn        = func(const [*]u8, *statvfs)->s32

#[Swag.CallingConvention(.C)]
alias fuse_flush_fn         = func(const [*]u8?, *fuse_file_info)->s32

#[Swag.CallingConvention(.C)]
alias fuse_fsync_fn         = func(const [*]u8?, s32, *fuse_file_info)->s32

#[Swag.CallingConvention(.C)]
alias fuse_fill_dir_fn      = func(*void, const [*]u8, const *stat?, s64, s32)->s32

#[Swag.CallingConvention(.C)]
alias fuse_readdir_fn       = func(const [*]u8, *void, fuse_fill_dir_fn, s64, *fuse_file_info, s32)->s32

#[Swag.CallingConvention(.C)]
alias fuse_access_fn        = func(const [*]u8, s32)->s32

#[Swag.CallingConvention(.C)]
alias fuse_create_fn        = func(const [*]u8, u32, *fuse_file_info)->s32

#[Swag.CallingConvention(.C)]
alias fuse_utimens_fn       = func(const [*]u8?, const [*]timespec?, *fuse_file_info?)->s32

#[Swag.CallingConvention(.C)]
alias fuse_new_fn           = func(*fuse_args, const *fuse_operations, u64, *void?)->*void?

#[Swag.CallingConvention(.C)]
alias fuse_mount_fn         = func(*void, const [*]u8)->s32

#[Swag.CallingConvention(.C)]
alias fuse_void_fn          = func(*void)

#[Swag.CallingConvention(.C)]
alias fuse_loop_fn          = func(*void)->s32

#[Swag.CallingConvention(.C)]
alias fuse_get_context_fn   = func()->*fuse_context

#[Swag.CallingConvention(.C)]
alias fuse_opt_free_args_fn = func(*fuse_args)

#[Swag.CallingConvention(.C)]
alias fuse_init_fn          = func(*void, *void)->*void?

struct fuse_operations
{
    public
    {
        getattr:         fuse_getattr_fn?
        readlink:        *void?
        mknod:           *void?
        mkdir:           fuse_mkdir_fn?
        unlink:          fuse_path_fn?
        rmdir:           fuse_path_fn?
        symlink:         *void?
        rename:          fuse_rename_fn?
        link:            *void?
        chmod:           fuse_chmod_fn?
        chown:           fuse_chown_fn?
        truncate:        fuse_truncate_fn?
        open:            fuse_open_fn?
        read:            fuse_read_fn?
        write:           fuse_write_fn?
        statfs:          fuse_statfs_fn?
        flush:           fuse_flush_fn?
        release:         fuse_flush_fn?
        fsync:           fuse_fsync_fn?
        setxattr:        *void?
        getxattr:        *void?
        listxattr:       *void?
        removexattr:     *void?
        opendir:         fuse_open_fn?
        readdir:         fuse_readdir_fn?
        releasedir:      fuse_flush_fn?
        fsyncdir:        fuse_fsync_fn?
        init:            fuse_init_fn?
        destroy:         *void?
        access:          fuse_access_fn?
        create:          fuse_create_fn?
        lock:            *void?
        utimens:         fuse_utimens_fn?
        bmap:            *void?
        ioctl:           *void?
        poll:            *void?
        write_buf:       *void?
        read_buf:        *void?
        flock:           *void?
        fallocate:       *void?
        copy_file_range: *void?
        lseek:           *void?
    }
}

#assert(#sizeof(fuse_args) == 24)
#assert(#sizeof(fuse_file_info) == 64)
#assert(#offsetof(fuse_file_info.fh) == 16)
#assert(#sizeof(fuse_context) == 40)
#assert(#offsetof(fuse_context.private_data) == 24)
#assert(#sizeof(fuse_operations) == 336)
#assert(#offsetof(fuse_operations.create) == 240)
