#global if WINDOWS

namespace WinFsp
{
    const CleanupDelete            = 0x01'u32
    const CleanupSetAllocationSize = 0x02'u32
    const CleanupSetArchiveBit     = 0x10'u32
    const CleanupSetLastAccessTime = 0x20'u32
    const CleanupSetLastWriteTime  = 0x40'u32
    const CleanupSetChangeTime     = 0x80'u32

    const StatusSuccess             = 0's32
    const StatusBufferOverflow      = cast #bit (s32) 0x80000005'u32
    const StatusInvalidParameter    = cast #bit (s32) 0xC000000D'u32
    const StatusAccessDenied        = cast #bit (s32) 0xC0000022'u32
    const StatusObjectNameNotFound  = cast #bit (s32) 0xC0000034'u32
    const StatusObjectNameCollision = cast #bit (s32) 0xC0000035'u32
    const StatusDiskFull            = cast #bit (s32) 0xC000007F'u32
    const StatusFileIsDirectory     = cast #bit (s32) 0xC00000BA'u32
    const StatusDirectoryNotEmpty   = cast #bit (s32) 0xC0000101'u32
    const StatusNotADirectory       = cast #bit (s32) 0xC0000103'u32
    const StatusIoDeviceError       = cast #bit (s32) 0xC0000185'u32

    func statusFromError(err: #null any, fallback = StatusIoDeviceError)->s32
    {
        switch err
        {
        case Error:
            switch (cast(Error) err).kind
            {
            case .InvalidInput,
                 .PasswordRequired,
                 .SizeTooSmall: return StatusInvalidParameter

            case .NotFound:          return StatusObjectNameNotFound
            case .AlreadyExists:     return StatusObjectNameCollision
            case .AccessDenied:      return StatusAccessDenied
            case .NotDirectory:      return StatusNotADirectory
            case .IsDirectory:       return StatusFileIsDirectory
            case .DirectoryNotEmpty: return StatusDirectoryNotEmpty
            case .DiskFull:          return StatusDiskFull
            }
        }

        return fallback
    }
}
