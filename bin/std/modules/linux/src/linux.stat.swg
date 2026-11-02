#global if #os == Swag.TargetOs.Linux
#global export

const STATX_TYPE            = 0x1'u32
const STATX_MODE            = 0x2'u32
const STATX_BASIC_STATS     = 0x7FF'u32
const STATX_BTIME           = 0x800'u32
const STATX_ATIME           = 0x20'u32
const STATX_MTIME           = 0x40'u32
const STATX_ATTR_COMPRESSED = 0x4'u64
const STATX_ATTR_ENCRYPTED  = 0x800'u64

struct statx_timestamp
{
    public tv_sec:    s64
    public tv_nsec:   u32
    private reserved: s32
}

// C structure tags that share their name with a native function.
namespace Structs
{
    struct statx
    {
        public
        {
            stx_mask:       u32
            stx_blksize:    u32
            stx_attributes: u64
            stx_nlink:      u32
            stx_uid:        u32
            stx_gid:        u32
            stx_mode:       u16
        }

        private spare0: u16

        public
        {
            stx_ino:                       u64
            stx_size:                      u64
            stx_blocks:                    u64
            stx_attributes_mask:           u64
            stx_atime:                     statx_timestamp
            stx_btime:                     statx_timestamp
            stx_ctime:                     statx_timestamp
            stx_mtime:                     statx_timestamp
            stx_rdev_major:                u32
            stx_rdev_minor:                u32
            stx_dev_major:                 u32
            stx_dev_minor:                 u32
            stx_mnt_id:                    u64
            stx_dio_mem_align:             u32
            stx_dio_offset_align:          u32
            stx_subvol:                    u64
            stx_atomic_write_unit_min:     u32
            stx_atomic_write_unit_max:     u32
            stx_atomic_write_segments_max: u32
        }

        private spare1: u32
        private spare3: [9] u64
    }
}

#assert(#sizeof(statx_timestamp) == 16)
#assert(#sizeof(Structs.statx) == 256)
#assert(#offsetof(Structs.statx.stx_atime) == 0x40)
#assert(#offsetof(Structs.statx.stx_btime) == 0x50)
#assert(#offsetof(Structs.statx.stx_mnt_id) == 0x90)
