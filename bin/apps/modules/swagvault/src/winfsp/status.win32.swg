#global if WINDOWS

namespace WinFsp
{
    const CleanupDelete            = 0x01_u32
    const CleanupSetAllocationSize = 0x02_u32
    const CleanupSetArchiveBit     = 0x10_u32
    const CleanupSetLastAccessTime = 0x20_u32
    const CleanupSetLastWriteTime  = 0x40_u32
    const CleanupSetChangeTime     = 0x80_u32

    const StatusSuccess             = 0_s32
    const StatusDeviceBusy          = cast #bit (s32, 0x80000011_u32)
    const StatusBufferOverflow      = cast #bit (s32, 0x80000005_u32)
    const StatusInvalidParameter    = cast #bit (s32, 0xC000000D_u32)
    const StatusAccessDenied        = cast #bit (s32, 0xC0000022_u32)
    const StatusObjectNameNotFound  = cast #bit (s32, 0xC0000034_u32)
    const StatusObjectNameCollision = cast #bit (s32, 0xC0000035_u32)
    const StatusDiskFull            = cast #bit (s32, 0xC000007F_u32)
    const StatusFileIsDirectory     = cast #bit (s32, 0xC00000BA_u32)
    const StatusMediaWriteProtected = cast #bit (s32, 0xC00000A2_u32)
    const StatusDirectoryNotEmpty   = cast #bit (s32, 0xC0000101_u32)
    const StatusNotADirectory       = cast #bit (s32, 0xC0000103_u32)
    const StatusIoDeviceError       = cast #bit (s32, 0xC0000185_u32)

    // HRESULT and NTSTATUS values use the high bit to mark failure. Formatting
    // that signed ABI value as hexadecimal must preserve its bits rather than
    // perform a checked numeric conversion to an unsigned integer.
    func statusBits(status: s32)->u32 => cast #bit (u32, status)

    // The NTSTATUS Windows expects for a failure, or `fallback` when it has no closer match.
    func statusFromError(err: any?, fallback = StatusIoDeviceError)->s32
    {
        if err is Error as error
        {
            switch error.kind
            {
            case .InvalidInput,
                 .PasswordRequired,
                 .SizeTooSmall,
                 .SparseContainer:
                return StatusInvalidParameter

            case .NotFound:          return StatusObjectNameNotFound
            case .AlreadyExists:     return StatusObjectNameCollision
            case .AccessDenied:      return StatusAccessDenied
            case .Busy:              return StatusDeviceBusy
            case .HiddenProtected:   return StatusMediaWriteProtected
            case .WriteProtected:    return StatusMediaWriteProtected
            case .NotDirectory:      return StatusNotADirectory
            case .IsDirectory:       return StatusFileIsDirectory
            case .DirectoryNotEmpty: return StatusDirectoryNotEmpty
            case .DiskFull:          return StatusDiskFull
            default:                 break
            }
        }

        return fallback
    }
}
