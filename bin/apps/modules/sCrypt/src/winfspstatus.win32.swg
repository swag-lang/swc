#global if WINDOWS

namespace SCrypt
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
}

namespace SCrypt.Platform
{
    func statusFromError(err: #null any, fallback = SCrypt.StatusIoDeviceError)->s32
    {
        switch err
        {
        case SCrypt.Error:
            switch (cast(SCrypt.Error) err).kind
            {
            case .InvalidInput:      return SCrypt.StatusInvalidParameter
            case .NotFound:          return SCrypt.StatusObjectNameNotFound
            case .AlreadyExists:     return SCrypt.StatusObjectNameCollision
            case .AccessDenied:      return SCrypt.StatusAccessDenied
            case .NotDirectory:      return SCrypt.StatusNotADirectory
            case .IsDirectory:       return SCrypt.StatusFileIsDirectory
            case .DirectoryNotEmpty: return SCrypt.StatusDirectoryNotEmpty
            case .DiskFull:          return SCrypt.StatusDiskFull
            }
        }
        return fallback
    }
}
