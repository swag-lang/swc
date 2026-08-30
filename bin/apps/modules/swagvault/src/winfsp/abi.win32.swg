#global if WINDOWS

#foreignlib("advapi32")
#foreignlib("kernel32")
#foreignlib("shell32")

using Core

namespace WinFsp
{
    alias NativeHandle = #null const [*] void

    alias NativeModule = #null const [*] void

    const InvalidHandle = cast(NativeHandle) cast #bit (u64) -1's64
    const GenericWrite  = 0x40000000'u32
    const ShareRead     = 0x00000001'u32
    const NormalFile    = 0x00000080'u32

    const WinFspDllName          = "winfsp-x64.dll"
    const WinFspDriverName       = "winfsp-x64.sys"
    const WinFspSxsName          = "swagvault"
    const WinFspDiskName         = "WinFsp.Disk"
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
        userContext:      #null *void
    }

    #assert(#sizeof(FspVolumeParams) == 504)
    #assert(#sizeof(FspVolumeInfo) == 88)
    #assert(#sizeof(FileInfo) == 72)
    #assert(#offsetof(FspDirInfo.fileName) == 104)
    #assert(#offsetof(FspFileSystem.userContext) == 8)

    alias FspGetVolumeInfoFn     = func(*FspFileSystem, *FspVolumeInfo)->s32
    alias FspSetVolumeLabelFn    = func(*FspFileSystem, #null [*] u16, *FspVolumeInfo)->s32
    alias FspGetSecurityByNameFn = func(*FspFileSystem, #null [*] u16, #null *u32, #null *void, #null *u64)->s32
    alias FspCreateFn            = func(*FspFileSystem, #null [*] u16, u32, u32, u32, #null *void, u64, *#null *void, *FileInfo)->s32
    alias FspOpenFn              = func(*FspFileSystem, #null [*] u16, u32, u32, *#null *void, *FileInfo)->s32
    alias FspOverwriteFn         = func(*FspFileSystem, #null *void, u32, u8, u64, *FileInfo)->s32
    alias FspCleanupFn           = func(*FspFileSystem, #null *void, #null [*] u16, u32)
    alias FspCloseFn             = func(*FspFileSystem, #null *void)
    alias FspReadFn              = func(*FspFileSystem, #null *void, #null *void, u64, u32, *u32)->s32
    alias FspWriteFn             = func(*FspFileSystem, #null *void, #null *void, u64, u32, u8, u8, *u32, *FileInfo)->s32
    alias FspFlushFn             = func(*FspFileSystem, #null *void, #null *FileInfo)->s32
    alias FspGetFileInfoFn       = func(*FspFileSystem, #null *void, *FileInfo)->s32
    alias FspSetBasicInfoFn      = func(*FspFileSystem, #null *void, u32, u64, u64, u64, u64, *FileInfo)->s32
    alias FspSetFileSizeFn       = func(*FspFileSystem, #null *void, u64, u8, *FileInfo)->s32
    alias FspCanDeleteFn         = func(*FspFileSystem, #null *void, #null [*] u16)->s32
    alias FspRenameFn            = func(*FspFileSystem, #null *void, #null [*] u16, #null [*] u16, u8)->s32
    alias FspGetSecurityFn       = func(*FspFileSystem, #null *void, #null *void, *u64)->s32
    alias FspSetSecurityFn       = func(*FspFileSystem, #null *void, u32, #null *void)->s32
    alias FspReadDirectoryFn     = func(*FspFileSystem, #null *void, #null [*] u16, #null [*] u16, #null *void, u32, *u32)->s32
    alias FspGetDirInfoByNameFn  = func(*FspFileSystem, #null *void, #null [*] u16, *FspDirInfo)->s32

    struct FspInterface
    {
        getVolumeInfo:     FspGetVolumeInfoFn     = undefined
        setVolumeLabel:    FspSetVolumeLabelFn    = undefined
        getSecurityByName: FspGetSecurityByNameFn = undefined
        create:            FspCreateFn            = undefined
        open:              FspOpenFn              = undefined
        overwrite:         FspOverwriteFn         = undefined
        cleanup:           FspCleanupFn           = undefined
        close:             FspCloseFn             = undefined
        read:              FspReadFn              = undefined
        write:             FspWriteFn             = undefined
        flush:             FspFlushFn             = undefined
        getFileInfo:       FspGetFileInfoFn       = undefined
        setBasicInfo:      FspSetBasicInfoFn      = undefined
        setFileSize:       FspSetFileSizeFn       = undefined
        canDelete:         FspCanDeleteFn         = undefined
        rename:            FspRenameFn            = undefined
        getSecurity:       FspGetSecurityFn       = undefined
        setSecurity:       FspSetSecurityFn       = undefined
        readDirectory:     FspReadDirectoryFn     = undefined
        unused19To23:      [5] #null const *void
        getDirInfoByName:  FspGetDirInfoByNameFn  = undefined
        unused25To63:      [39] #null const *void
    }

    #assert(#sizeof(FspInterface) == 64 * #sizeof(#null *void))
    #assert(#offsetof(FspInterface.getDirInfoByName) == 24 * #sizeof(#null *void))

    alias FspFileSystemCreateFn           = func(#null const [*] u16, const *FspVolumeParams, const *FspInterface, *#null *FspFileSystem)->s32
    alias FspFileSystemDeleteFn           = func(*FspFileSystem)
    alias FspFileSystemSetMountPointFn    = func(*FspFileSystem, #null const [*] u16)->s32
    alias FspFileSystemRemoveMountPointFn = func(*FspFileSystem)
    alias FspFileSystemStartDispatcherFn  = func(*FspFileSystem, u32)->s32
    alias FspFileSystemStopDispatcherFn   = func(*FspFileSystem)
    alias FspFileSystemAddDirInfoFn       = func(#null *FspDirInfo, #null *void, u32, *u32)->u8
    alias FspFileSystemSetGuardFn         = func(*FspFileSystem, s32)
    alias FspSetSecurityDescriptorFn      = func(#null const *void, u32, #null *void, *#null *void)->s32
    alias FspDeleteSecurityDescriptorFn   = func(#null *void, #null const *void)
    alias WinFspRegistrationFn            = func()->s32
    alias FspDebugLogSetHandleFn          = func(NativeHandle)
    alias FspFsctlStartServiceFn          = func()->s32

    struct WinFspApi
    {
        module:                   NativeModule
        fsCreate:                 FspFileSystemCreateFn           = undefined
        destroy:                  FspFileSystemDeleteFn           = undefined
        setMountPoint:            FspFileSystemSetMountPointFn    = undefined
        removeMountPoint:         FspFileSystemRemoveMountPointFn = undefined
        startDispatcher:          FspFileSystemStartDispatcherFn  = undefined
        stopDispatcher:           FspFileSystemStopDispatcherFn   = undefined
        addDirInfo:               FspFileSystemAddDirInfoFn       = undefined
        setGuard:                 FspFileSystemSetGuardFn         = undefined
        setSecurityDescriptor:    FspSetSecurityDescriptorFn      = undefined
        setSecurityAddress:       #null const *void
        deleteSecurityDescriptor: FspDeleteSecurityDescriptorFn   = undefined
        registerServer:           WinFspRegistrationFn            = undefined
        unregisterServer:         WinFspRegistrationFn            = undefined
        setDebugLogHandle:        FspDebugLogSetHandleFn          = undefined
        startService:             FspFsctlStartServiceFn          = undefined
        runtimeRoot:              String
        dllPath:                  String

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

    #[Swag.Foreign("kernel32", callconv: Swag.CallConv.C)]
    {
        func LoadLibraryW(name: #null const [*] u16)->NativeModule
        func GetProcAddress(module: NativeModule, name: const [*] u8)->#null const *void
        func FreeLibrary(module: NativeModule)->s32
        func GetEnvironmentVariableA(name: const [*] u8, value: [*] u8, capacity: u32)->u32
        func GetLastError()->u32
        func CreateFileW(fileName: #null const [*] u16, access, share: u32, security: #null *void, disposition, flags: u32, templateFile: NativeHandle)->NativeHandle
        func CloseHandle(handle: NativeHandle)->s32
        func OpenProcess(access: u32, inheritHandle: s32, processId: u32)->NativeHandle
        func WaitForSingleObject(handle: NativeHandle, milliseconds: u32)->u32
        func MoveFileExW(existing, replacement: #null const [*] u16, flags: u32)->s32
        func RemoveDirectoryW(path: #null const [*] u16)->s32
        func LocalFree(memory: #null *void)->#null *void
    }

    #[Swag.Foreign("advapi32", callconv: Swag.CallConv.C)]
    {
        func ConvertStringSecurityDescriptorToSecurityDescriptorW(text: #null const [*] u16, revision: u32, descriptor: *#null *void, size: #null *u32)->s32
        func GetSecurityDescriptorLength(descriptor: #null const *void)->u32
    }

    #[Swag.Foreign("shell32", callconv: Swag.CallConv.C)]
    {
        func IsUserAnAdmin()->s32
        func ShellExecuteW(window: #null *void, operation, file, parameters, directory: #null const [*] u16, show: s32)->#null const *void
    }

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
        if !count or count >= buffer.count do
            return ""
        return Swag.makeString(buffer.buffer, count)
    }
}
