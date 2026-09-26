#global if WINDOWS

using Core, Win32

namespace WinFsp
{
    alias NativeHandle = HANDLE

    alias NativeModule = HMODULE

    const InvalidHandle = cast(NativeHandle) cast #bit (u64) -1's64
    const GenericWrite  = 0x40000000'u32
    const ShareRead     = 0x00000001'u32
    const NormalFile    = 0x00000080'u32

    const WinFspDllName          = "winfsp-x64.dll"
    const WinFspDriverName       = "winfsp-x64.sys"
    const WinFspSxsName          = "swagvault"
    const WinFspNetName          = "WinFsp.Net"
    const WinFspGuardianArgument = "--winfsp-guardian"
    const WaitInfinite           = 0xFFFFFFFF'u32
    const ProcessSynchronize     = 0x00100000'u32
    const SddlRevisionOne        = 1'u32
    const MoveDelayUntilReboot   = 0x00000004'u32

    struct FspVolumeParams
    {
        version:                  u16
        sectorSize:               u16
        sectorsPerAllocationUnit: u16
        maxComponentLength:       u16
        volumeCreationTime:       u64
        volumeSerialNumber:       u32
        transactTimeout:          u32
        irpTimeout:               u32
        irpCapacity:              u32
        fileInfoTimeout:          u32
        flags:                    u32
        prefix:                   [192] u16
        fileSystemName:           [16] u16
        additionalFlags:          u32
        volumeInfoTimeout:        u32
        dirInfoTimeout:           u32
        securityTimeout:          u32
        streamInfoTimeout:        u32
        eaTimeout:                u32
        fsextControlCode:         u32
        reserved32:               [1] u32
        reserved64:               [2] u64
    }

    struct FspVolumeInfo
    {
        totalSize:         u64
        freeSize:          u64
        volumeLabelLength: u16
        volumeLabel:       [32] u16
    }

    struct FspDirInfo
    {
        size:             u16
        alignmentPadding: [6] u8
        fileInfo:         FileInfo
        padding:          [24] u8
        fileName:         [1] u16
    }

    struct FspFileSystem
    {
        version:          u16
        alignmentPadding: [6] u8
        userContext:      *void?
    }

    #assert(#sizeof(FspVolumeParams) == 504)
    #assert(#sizeof(FspVolumeInfo) == 88)
    #assert(#sizeof(FileInfo) == 72)
    #assert(#offsetof(FspDirInfo.fileName) == 104)
    #assert(#offsetof(FspFileSystem.userContext) == 8)

    #[Swag.CallingConvention(.C)]
    alias FspGetVolumeInfoFn     = func(*FspFileSystem, *FspVolumeInfo)->s32
    #[Swag.CallingConvention(.C)]
    alias FspSetVolumeLabelFn    = func(*FspFileSystem, [*] u16?, *FspVolumeInfo)->s32
    #[Swag.CallingConvention(.C)]
    alias FspGetSecurityByNameFn = func(*FspFileSystem, [*] u16?, *u32?, *void?, *u64?)->s32
    #[Swag.CallingConvention(.C)]
    alias FspCreateFn            = func(*FspFileSystem, [*] u16?, u32, u32, u32, *void?, u64, *(*void?), *FileInfo)->s32
    #[Swag.CallingConvention(.C)]
    alias FspOpenFn              = func(*FspFileSystem, [*] u16?, u32, u32, *(*void?), *FileInfo)->s32
    #[Swag.CallingConvention(.C)]
    alias FspOverwriteFn         = func(*FspFileSystem, *void?, u32, u8, u64, *FileInfo)->s32
    #[Swag.CallingConvention(.C)]
    alias FspCleanupFn           = func(*FspFileSystem, *void?, [*] u16?, u32)
    #[Swag.CallingConvention(.C)]
    alias FspCloseFn             = func(*FspFileSystem, *void?)
    #[Swag.CallingConvention(.C)]
    alias FspReadFn              = func(*FspFileSystem, *void?, *void?, u64, u32, *u32)->s32
    #[Swag.CallingConvention(.C)]
    alias FspWriteFn             = func(*FspFileSystem, *void?, *void?, u64, u32, u8, u8, *u32, *FileInfo)->s32
    #[Swag.CallingConvention(.C)]
    alias FspFlushFn             = func(*FspFileSystem, *void?, *FileInfo?)->s32
    #[Swag.CallingConvention(.C)]
    alias FspGetFileInfoFn       = func(*FspFileSystem, *void?, *FileInfo)->s32
    #[Swag.CallingConvention(.C)]
    alias FspSetBasicInfoFn      = func(*FspFileSystem, *void?, u32, u64, u64, u64, u64, *FileInfo)->s32
    #[Swag.CallingConvention(.C)]
    alias FspSetFileSizeFn       = func(*FspFileSystem, *void?, u64, u8, *FileInfo)->s32
    #[Swag.CallingConvention(.C)]
    alias FspCanDeleteFn         = func(*FspFileSystem, *void?, [*] u16?)->s32
    #[Swag.CallingConvention(.C)]
    alias FspRenameFn            = func(*FspFileSystem, *void?, [*] u16?, [*] u16?, u8)->s32
    #[Swag.CallingConvention(.C)]
    alias FspGetSecurityFn       = func(*FspFileSystem, *void?, *void?, *u64)->s32
    #[Swag.CallingConvention(.C)]
    alias FspSetSecurityFn       = func(*FspFileSystem, *void?, u32, *void?)->s32
    #[Swag.CallingConvention(.C)]
    alias FspReadDirectoryFn     = func(*FspFileSystem, *void?, [*] u16?, [*] u16?, *void?, u32, *u32)->s32
    #[Swag.CallingConvention(.C)]
    alias FspGetDirInfoByNameFn  = func(*FspFileSystem, *void?, [*] u16?, *FspDirInfo)->s32

    // The dispatch table WinFsp calls back through. Every slot starts null and receives its
    // operation while the table is built, which is also how an unimplemented operation stays
    // null and reads as unsupported.
    struct FspInterface
    {
        late
        {
            getVolumeInfo:     FspGetVolumeInfoFn
            setVolumeLabel:    FspSetVolumeLabelFn
            getSecurityByName: FspGetSecurityByNameFn
            create:            FspCreateFn
            open:              FspOpenFn
            overwrite:         FspOverwriteFn
            cleanup:           FspCleanupFn
            close:             FspCloseFn
            read:              FspReadFn
            write:             FspWriteFn
            flush:             FspFlushFn
            getFileInfo:       FspGetFileInfoFn
            setBasicInfo:      FspSetBasicInfoFn
            setFileSize:       FspSetFileSizeFn
            canDelete:         FspCanDeleteFn
            rename:            FspRenameFn
            getSecurity:       FspGetSecurityFn
            setSecurity:       FspSetSecurityFn
            readDirectory:     FspReadDirectoryFn
        }

        unused19To23: [5] (const *void?)

        late getDirInfoByName: FspGetDirInfoByNameFn

        unused25To63: [39] (const *void?)
    }

    #assert(#sizeof(FspInterface) == 64 * #sizeof(*void?))
    #assert(#offsetof(FspInterface.getDirInfoByName) == 24 * #sizeof(*void?))

    #[Swag.CallingConvention(.C)]
    alias FspFileSystemCreateFn           = func(const [*] u16?, const *FspVolumeParams, const *FspInterface, *(*FspFileSystem?))->s32
    #[Swag.CallingConvention(.C)]
    alias FspFileSystemDeleteFn           = func(*FspFileSystem)
    #[Swag.CallingConvention(.C)]
    alias FspFileSystemSetMountPointFn    = func(*FspFileSystem, const [*] u16?)->s32
    #[Swag.CallingConvention(.C)]
    alias FspFileSystemRemoveMountPointFn = func(*FspFileSystem)
    #[Swag.CallingConvention(.C)]
    alias FspFileSystemStartDispatcherFn  = func(*FspFileSystem, u32)->s32
    #[Swag.CallingConvention(.C)]
    alias FspFileSystemStopDispatcherFn   = func(*FspFileSystem)
    #[Swag.CallingConvention(.C)]
    alias FspFileSystemAddDirInfoFn       = func(*FspDirInfo?, *void?, u32, *u32)->u8
    #[Swag.CallingConvention(.C)]
    alias FspFileSystemSetGuardFn         = func(*FspFileSystem, s32)
    #[Swag.CallingConvention(.C)]
    alias FspSetSecurityDescriptorFn      = func(const *void?, u32, *void?, *(*void?))->s32
    #[Swag.CallingConvention(.C)]
    alias FspDeleteSecurityDescriptorFn   = func(*void?, const *void?)
    #[Swag.CallingConvention(.C)]
    alias WinFspRegistrationFn            = func()->s32
    #[Swag.CallingConvention(.C)]
    alias FspDebugLogSetHandleFn          = func(NativeHandle)
    #[Swag.CallingConvention(.C)]
    alias FspFsctlStartServiceFn          = func()->s32

    struct WinFspApi
    {
        module: NativeModule

        // The runtime entry points, resolved once when the library is loaded.

        late
        {
            fsCreate:              FspFileSystemCreateFn
            destroy:               FspFileSystemDeleteFn
            setMountPoint:         FspFileSystemSetMountPointFn
            removeMountPoint:      FspFileSystemRemoveMountPointFn
            startDispatcher:       FspFileSystemStartDispatcherFn
            stopDispatcher:        FspFileSystemStopDispatcherFn
            addDirInfo:            FspFileSystemAddDirInfoFn
            setGuard:              FspFileSystemSetGuardFn
            setSecurityDescriptor: FspSetSecurityDescriptorFn
        }

        setSecurityAddress: const *void?

        late
        {
            deleteSecurityDescriptor: FspDeleteSecurityDescriptorFn
            registerServer:           WinFspRegistrationFn
            unregisterServer:         WinFspRegistrationFn
            setDebugLogHandle:        FspDebugLogSetHandleFn
            startService:             FspFsctlStartServiceFn
        }

        runtimeRoot: String
        dllPath:     String

        // Mounts currently holding the runtime. The library, the portable driver registration
        // and the staged runtime tree are shared by every mount, so they are released when the
        // last one goes and not before. Mounts start and stop on the single worker the shell
        // schedules its operations on, so this needs no atomic.
        mountCount: u32

        portable:        bool
        registered:      bool
        guardianManaged: bool
        guardianProcess: bool
    }

    var g_WinFsp: WinFspApi

    func isElevated()->bool => IsUserAnAdmin() != 0

    func loadLibrary(path: string)->NativeModule
    {
        let path16 = Utf16.toZeroTerminated(path)
        return LoadLibraryW(path16.buffer)
    }

    func environmentValue(name: string)->String
    {
        var buffer: [32768] u8
        let count = GetEnvironmentVariableA(name.buffer, buffer.buffer, cast(u32) buffer.count)
        if not count or count >= buffer.count do
            return ""
        return Swag.makeString(buffer.buffer, count)
    }
}
