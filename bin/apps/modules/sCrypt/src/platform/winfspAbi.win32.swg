#global if WINDOWS

#foreignlib("advapi32")
#foreignlib("kernel32")
#foreignlib("shell32")

using Core

namespace SCrypt.Platform
{
    alias NativeHandle = #null const [*] void

    alias NativeModule = #null const [*] void

    const InvalidHandle = cast(NativeHandle) cast #bit (u64) -1's64
    const GenericWrite  = 0x40000000'u32
    const ShareRead     = 0x00000001'u32
    const NormalFile    = 0x00000080'u32

    const WinFspDllName    = "winfsp-x64.dll"
    const WinFspDriverName = "winfsp-x64.sys"
    const WinFspSxsName    = "sCrypt"
    const WinFspDiskName   = "WinFsp.Disk"
    const WinFspGuardianArgument = "--winfsp-guardian"
    const WaitInfinite     = 0xFFFFFFFF'u32
    const ProcessSynchronize = 0x00100000'u32
    const SddlRevisionOne  = 1'u32
    const MoveDelayUntilReboot = 0x00000004'u32

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

    alias FspGetVolumeInfoFn = func(*FspFileSystem, *FspVolumeInfo)->s32
    alias FspSetVolumeLabelFn = func(*FspFileSystem, #null [*] u16, *FspVolumeInfo)->s32
    alias FspGetSecurityByNameFn = func(*FspFileSystem, #null [*] u16, #null *u32,
                                        #null *void, #null *u64)->s32
    alias FspCreateFn = func(*FspFileSystem, #null [*] u16, u32, u32, u32, #null *void, u64,
                             *#null *void, *FileInfo)->s32
    alias FspOpenFn = func(*FspFileSystem, #null [*] u16, u32, u32,
                           *#null *void, *FileInfo)->s32
    alias FspOverwriteFn = func(*FspFileSystem, #null *void, u32, u8, u64, *FileInfo)->s32
    alias FspCleanupFn = func(*FspFileSystem, #null *void, #null [*] u16, u32)
    alias FspCloseFn = func(*FspFileSystem, #null *void)
    alias FspReadFn = func(*FspFileSystem, #null *void, #null *void, u64, u32, *u32)->s32
    alias FspWriteFn = func(*FspFileSystem, #null *void, #null *void, u64, u32,
                            u8, u8, *u32, *FileInfo)->s32
    alias FspFlushFn = func(*FspFileSystem, #null *void, #null *FileInfo)->s32
    alias FspGetFileInfoFn = func(*FspFileSystem, #null *void, *FileInfo)->s32
    alias FspSetBasicInfoFn = func(*FspFileSystem, #null *void, u32,
                                   u64, u64, u64, u64, *FileInfo)->s32
    alias FspSetFileSizeFn = func(*FspFileSystem, #null *void, u64, u8, *FileInfo)->s32
    alias FspCanDeleteFn = func(*FspFileSystem, #null *void, #null [*] u16)->s32
    alias FspRenameFn = func(*FspFileSystem, #null *void, #null [*] u16,
                             #null [*] u16, u8)->s32
    alias FspGetSecurityFn = func(*FspFileSystem, #null *void, #null *void, *u64)->s32
    alias FspSetSecurityFn = func(*FspFileSystem, #null *void, u32, #null *void)->s32
    alias FspReadDirectoryFn = func(*FspFileSystem, #null *void, #null [*] u16,
                                    #null [*] u16, #null *void, u32, *u32)->s32
    alias FspGetDirInfoByNameFn = func(*FspFileSystem, #null *void,
                                       #null [*] u16, *FspDirInfo)->s32

    struct FspInterface
    {
        getVolumeInfo:     FspGetVolumeInfoFn = undefined
        setVolumeLabel:    FspSetVolumeLabelFn = undefined
        getSecurityByName: FspGetSecurityByNameFn = undefined
        create:            FspCreateFn = undefined
        open:              FspOpenFn = undefined
        overwrite:         FspOverwriteFn = undefined
        cleanup:           FspCleanupFn = undefined
        close:             FspCloseFn = undefined
        read:              FspReadFn = undefined
        write:             FspWriteFn = undefined
        flush:             FspFlushFn = undefined
        getFileInfo:       FspGetFileInfoFn = undefined
        setBasicInfo:      FspSetBasicInfoFn = undefined
        setFileSize:       FspSetFileSizeFn = undefined
        canDelete:         FspCanDeleteFn = undefined
        rename:            FspRenameFn = undefined
        getSecurity:       FspGetSecurityFn = undefined
        setSecurity:       FspSetSecurityFn = undefined
        readDirectory:     FspReadDirectoryFn = undefined
        unused19To23:      [5] #null const *void
        getDirInfoByName:  FspGetDirInfoByNameFn = undefined
        unused25To63:      [39] #null const *void
    }

    #assert(#sizeof(FspInterface) == 64 * #sizeof(#null *void))
    #assert(#offsetof(FspInterface.getDirInfoByName) == 24 * #sizeof(#null *void))

    alias FspFileSystemCreateFn = func(#null const [*] u16, const *FspVolumeParams,
                                        const *FspInterface, *#null *FspFileSystem)->s32
    alias FspFileSystemDeleteFn = func(*FspFileSystem)
    alias FspFileSystemSetMountPointFn = func(*FspFileSystem, #null const [*] u16)->s32
    alias FspFileSystemRemoveMountPointFn = func(*FspFileSystem)
    alias FspFileSystemStartDispatcherFn = func(*FspFileSystem, u32)->s32
    alias FspFileSystemStopDispatcherFn = func(*FspFileSystem)
    alias FspFileSystemAddDirInfoFn = func(#null *FspDirInfo, #null *void, u32, *u32)->u8
    alias FspFileSystemSetGuardFn = func(*FspFileSystem, s32)
    alias FspSetSecurityDescriptorFn = func(#null const *void, u32, #null *void, *#null *void)->s32
    alias FspDeleteSecurityDescriptorFn = func(#null *void, #null const *void)
    alias WinFspRegistrationFn = func()->s32
    alias FspDebugLogSetHandleFn = func(NativeHandle)
    alias FspFsctlStartServiceFn = func()->s32

    struct WinFspApi
    {
        module:                   NativeModule
        fsCreate:                 FspFileSystemCreateFn = undefined
        destroy:                  FspFileSystemDeleteFn = undefined
        setMountPoint:            FspFileSystemSetMountPointFn = undefined
        removeMountPoint:         FspFileSystemRemoveMountPointFn = undefined
        startDispatcher:          FspFileSystemStartDispatcherFn = undefined
        stopDispatcher:           FspFileSystemStopDispatcherFn = undefined
        addDirInfo:               FspFileSystemAddDirInfoFn = undefined
        setGuard:                 FspFileSystemSetGuardFn = undefined
        setSecurityDescriptor:    FspSetSecurityDescriptorFn = undefined
        setSecurityAddress:       #null const *void
        deleteSecurityDescriptor: FspDeleteSecurityDescriptorFn = undefined
        registerServer:           WinFspRegistrationFn = undefined
        unregisterServer:         WinFspRegistrationFn = undefined
        setDebugLogHandle:        FspDebugLogSetHandleFn = undefined
        startService:             FspFsctlStartServiceFn = undefined
        runtimeRoot:              String
        dllPath:                  String
        portable:                 bool
        registered:               bool
        guardianManaged:          bool
        guardianProcess:          bool
    }

    var g_WinFsp: WinFspApi

    #[Swag.Foreign("kernel32")]
    {
        func LoadLibraryW(name: #null const [*] u16)->NativeModule
        func GetProcAddress(module: NativeModule, name: const [*] u8)->#null const *void
        func FreeLibrary(module: NativeModule)->s32
        func GetEnvironmentVariableA(name: const [*] u8, value: [*] u8, capacity: u32)->u32
        func GetLastError()->u32
        func CreateFileW(fileName: #null const [*] u16, access, share: u32, security: #null *void,
                         disposition, flags: u32, templateFile: NativeHandle)->NativeHandle
        func CloseHandle(handle: NativeHandle)->s32
        func OpenProcess(access: u32, inheritHandle: s32, processId: u32)->NativeHandle
        func WaitForSingleObject(handle: NativeHandle, milliseconds: u32)->u32
        func MoveFileExW(existing, replacement: #null const [*] u16, flags: u32)->s32
        func RemoveDirectoryW(path: #null const [*] u16)->s32
        func LocalFree(memory: #null *void)->#null *void
    }

    #[Swag.Foreign("advapi32")]
    {
        func ConvertStringSecurityDescriptorToSecurityDescriptorW(
            text: #null const [*] u16, revision: u32, descriptor: *#null *void, size: #null *u32)->s32
        func GetSecurityDescriptorLength(descriptor: #null const *void)->u32
    }

    #[Swag.Foreign("shell32")]
    {
        func IsUserAnAdmin()->s32
        func ShellExecuteW(window: #null *void, operation, file, parameters,
                           directory: #null const [*] u16, show: s32)->#null const *void
    }

    func isElevated()->bool => IsUserAnAdmin() != 0

    func loadLibrary(path: string)->NativeModule
    {
        let path16 = Utf16.toZeroTerminated(path)
        return LoadLibraryW(@dataof(path16))
    }

    func environmentValue(name: string)->String
    {
        var buffer: [32768] u8
        let count = GetEnvironmentVariableA(@dataof(name), @dataof(buffer), cast(u32) @countof(buffer))
        if !count or count >= @countof(buffer) do
            return ""
        return @mkstring(@dataof(buffer), count)
    }

    func isPortableGuardianInvocation()->bool
    {
        let args = Env.arguments()
        return @countof(args) >= 2 and args[1] == WinFspGuardianArgument
    }

    func guardianErrorText(err: #null any)->string
    {
        switch err
        {
        case SCrypt.Error:
            return (cast(SCrypt.Error) err).message orelse "The portable WinFsp runtime failed."
        case Swag.SystemError:
            return (cast(Swag.SystemError) err).message orelse "Windows rejected the WinFsp helper."
        }
        return "The portable WinFsp helper failed."
    }

    func writeGuardianStatus(path, status: string) fail
    {
        discard File.writeAllBytes(path,
            @mkslice(cast(const [*] u8) @dataof(status), @countof(status)))
    }

    func startPortableGuardian(statusPath: string) fail
    {
        g_WinFsp.guardianProcess = true
        try loadWinFsp()
        try registerPortableWinFsp()
        try writeGuardianStatus(statusPath, Format.toString("READY\n%", g_WinFsp.dllPath))
    }

    func runPortableGuardian()->u32
    {
        let args = Env.arguments()
        if @countof(args) < 4 or args[1] != WinFspGuardianArgument or !isElevated() do
            return 2

        let parsed = catch StrConv.parseU32(args[2]) as parseError
        let statusPath = args[3]
        if parseError != null or parsed.ovf or parsed.eat != @countof(args[2]) do
            return 2

        let parent = OpenProcess(ProcessSynchronize, 0, parsed.value)
        if !parent
        {
            discard catch writeGuardianStatus(statusPath,
                "ERROR\nThe WinFsp helper could not monitor the sCrypt process.")
            return 1
        }

        discard catch startPortableGuardian(statusPath) as startError
        if startError != null
        {
            discard catch writeGuardianStatus(statusPath,
                Format.toString("ERROR\n%", guardianErrorText(startError)))
            unloadWinFsp()
            discard CloseHandle(parent)
            return 1
        }

        discard WaitForSingleObject(parent, WaitInfinite)
        discard CloseHandle(parent)
        unloadWinFsp()
        let communicationRoot = Path.directoryName(statusPath) orelse ""
        if @countof(communicationRoot) do
            removeRuntimeTree(communicationRoot)
        return 0
    }

    func ensurePortableGuardian() fail
    {
        if g_WinFsp.guardianManaged do
            return
        if isElevated() do
            SCrypt.failWith(
                "Launch sCrypt normally, not with 'Run as administrator', so Windows Explorer can see the mounted drive.")

        let temp = Env.getSpecialDirectory(.Temp)
        if temp.isEmpty() do
            SCrypt.failWith("Windows did not provide a usable temporary directory.")

        let communicationRoot = Path.combine(temp,
            Format.toString("sCrypt-Guardian-%-%", Env.Process.currentProcessId(), Guid64.random()))
        Directory.create(communicationRoot)
        let statusPath = Path.combine(communicationRoot, "status.txt")
        let parameters = Format.toString("% % \"%\"", WinFspGuardianArgument,
                                         Env.Process.currentProcessId(), statusPath)
        let executablePath = try Env.Process.currentExecutablePath()
        let executable16 = Utf16.toZeroTerminated(executablePath)
        let operation16 = Utf16.toZeroTerminated("runas")
        let parameters16 = Utf16.toZeroTerminated(parameters)
        let directory16 = Utf16.toZeroTerminated(Path.directoryName(executablePath) orelse "")
        let launch = ShellExecuteW(null, @dataof(operation16), @dataof(executable16),
                                   @dataof(parameters16), @dataof(directory16), 0)
        if cast(u64) launch <= 32
        {
            removeRuntimeTree(communicationRoot)
            SCrypt.failWith(Format.toString(
                "Windows could not start the portable WinFsp helper (ShellExecute code %, Windows error %).",
                cast(u64) launch, GetLastError()))
        }

        for [attempt] in 1200
        {
            discard attempt
            var status = catch File.readAllText(statusPath) as readError
            if readError == null
            {
                status.trim()
                if status.startsWith("READY\n") and @countof(status) > @countof("READY\n")
                {
                    g_WinFsp.dllPath = @mkstring(@dataof(status) + @countof("READY\n"),
                                                 @countof(status) - @countof("READY\n"))
                    g_WinFsp.guardianManaged = true
                    return
                }
                if status.startsWith("ERROR\n")
                {
                    let prefixCount = @countof("ERROR\n")
                    let detail = @countof(status) > prefixCount ?
                        @mkstring(@dataof(status) + prefixCount, @countof(status) - prefixCount) :
                        "The portable WinFsp helper failed."
                    SCrypt.failWith(detail)
                }
            }
            Threading.Thread.sleep(50'ms)
        }
        SCrypt.failWith("The portable WinFsp helper did not become ready in time.")
    }

    func removeRuntimeTree(path: string)
    {
        if !Directory.exists(path) do
            return

        var options: Directory.EnumerationOptions
        var entries = catch Directory.enumerate(path, options) as enumError
        if enumError == null
        {
            for entry in entries
            {
                if entry.isDirectory() do
                    removeRuntimeTree(entry.fullname)
                else
                {
                    discard catch File.delete(entry.fullname) as deleteError
                    if deleteError != null
                    {
                        let entry16 = Utf16.toZeroTerminated(entry.fullname)
                        discard MoveFileExW(@dataof(entry16), null, MoveDelayUntilReboot)
                    }
                }
            }
        }

        let path16 = Utf16.toZeroTerminated(path)
        if !RemoveDirectoryW(@dataof(path16)) do
            discard MoveFileExW(@dataof(path16), null, MoveDelayUntilReboot)
    }

    func stagePortableWinFsp()->String fail
    {
        let executablePath = try Env.Process.currentExecutablePath()
        let executableDirectory = Path.directoryName(executablePath) orelse ""
        let sourceDll = Path.combine(executableDirectory, WinFspDllName)
        let sourceDriver = Path.combine(executableDirectory, WinFspDriverName)
        if !File.exists(sourceDll) or !File.exists(sourceDriver) do
            SCrypt.failWith("The signed portable WinFsp runtime is incomplete.")

        let temp = Env.getSpecialDirectory(.Temp)
        if temp.isEmpty() do
            SCrypt.failWith("Windows did not provide a usable temporary directory.")

        var root = Path.combine(temp, Format.toString("sCrypt-WinFsp-%-%",
            Env.Process.currentProcessId(), Time.Timestamp.utcNow().ticks))
        Directory.create(root)

        let bin = Path.combine(root, "bin")
        Directory.create(bin)
        let dll = Path.combine(bin, WinFspDllName)
        let driver = Path.combine(bin, WinFspDriverName)
        discard catch File.duplicate(dll, sourceDll) as dllError
        discard catch File.duplicate(driver, sourceDriver) as driverError
        if dllError != null or driverError != null or !File.exists(dll) or !File.exists(driver)
        {
            removeRuntimeTree(root)
            SCrypt.failWith("The portable WinFsp runtime could not be staged.")
        }

        let identity = Path.combine(bin, "winfsp.sxs")
        discard File.writeAllBytes(identity,
            @mkslice(cast(const [*] u8) @dataof("sCrypt\n"), @countof("sCrypt\n")))
        g_WinFsp.runtimeRoot = #move root
        return dll
    }

    func resolveWinFspApi() fail
    {
        let create = GetProcAddress(g_WinFsp.module, @dataof("FspFileSystemCreate"))
        let destroy = GetProcAddress(g_WinFsp.module, @dataof("FspFileSystemDelete"))
        let setMountPoint = GetProcAddress(g_WinFsp.module, @dataof("FspFileSystemSetMountPoint"))
        let removeMountPoint = GetProcAddress(g_WinFsp.module, @dataof("FspFileSystemRemoveMountPoint"))
        let startDispatcher = GetProcAddress(g_WinFsp.module, @dataof("FspFileSystemStartDispatcher"))
        let stopDispatcher = GetProcAddress(g_WinFsp.module, @dataof("FspFileSystemStopDispatcher"))
        let addDirInfo = GetProcAddress(g_WinFsp.module, @dataof("FspFileSystemAddDirInfo"))
        let setGuard = GetProcAddress(g_WinFsp.module, @dataof("FspFileSystemSetOperationGuardStrategyF"))
        let setSecurity = GetProcAddress(g_WinFsp.module, @dataof("FspSetSecurityDescriptor"))
        let deleteSecurity = GetProcAddress(g_WinFsp.module, @dataof("FspDeleteSecurityDescriptor"))
        let registerServer = GetProcAddress(g_WinFsp.module, @dataof("DllRegisterServer"))
        let unregisterServer = GetProcAddress(g_WinFsp.module, @dataof("DllUnregisterServer"))
        let setDebugLogHandle = GetProcAddress(g_WinFsp.module, @dataof("FspDebugLogSetHandle"))
        let startService = GetProcAddress(g_WinFsp.module, @dataof("FspFsctlStartService"))

        if !create or !destroy or !setMountPoint or !removeMountPoint or !startDispatcher or
           !stopDispatcher or !addDirInfo or !setGuard or !setSecurity or !deleteSecurity or
           !registerServer or !unregisterServer or !setDebugLogHandle or !startService do
            SCrypt.failWith("The bundled WinFsp runtime does not expose the expected ABI.")

        g_WinFsp.fsCreate                 = cast(FspFileSystemCreateFn) notnull create
        g_WinFsp.destroy                  = cast(FspFileSystemDeleteFn) notnull destroy
        g_WinFsp.setMountPoint            = cast(FspFileSystemSetMountPointFn) notnull setMountPoint
        g_WinFsp.removeMountPoint         = cast(FspFileSystemRemoveMountPointFn) notnull removeMountPoint
        g_WinFsp.startDispatcher          = cast(FspFileSystemStartDispatcherFn) notnull startDispatcher
        g_WinFsp.stopDispatcher           = cast(FspFileSystemStopDispatcherFn) notnull stopDispatcher
        g_WinFsp.addDirInfo               = cast(FspFileSystemAddDirInfoFn) notnull addDirInfo
        g_WinFsp.setGuard                 = cast(FspFileSystemSetGuardFn) notnull setGuard
        g_WinFsp.setSecurityDescriptor    = cast(FspSetSecurityDescriptorFn) notnull setSecurity
        g_WinFsp.setSecurityAddress       = notnull setSecurity
        g_WinFsp.deleteSecurityDescriptor = cast(FspDeleteSecurityDescriptorFn) notnull deleteSecurity
        g_WinFsp.registerServer           = cast(WinFspRegistrationFn) notnull registerServer
        g_WinFsp.unregisterServer         = cast(WinFspRegistrationFn) notnull unregisterServer
        g_WinFsp.setDebugLogHandle        = cast(FspDebugLogSetHandleFn) notnull setDebugLogHandle
        g_WinFsp.startService             = cast(FspFsctlStartServiceFn) notnull startService
    }

    func winFspLogPath()->String
    {
        let temp = Env.getSpecialDirectory(.Temp)
        return temp.isEmpty() ? "sCrypt-WinFsp.log" : Path.combine(temp, "sCrypt-WinFsp.log")
    }

    func winFspStageLogPath()->String
    {
        let temp = Env.getSpecialDirectory(.Temp)
        return temp.isEmpty() ? "sCrypt-WinFsp-stage.log" :
               Path.combine(temp, "sCrypt-WinFsp-stage.log")
    }

    func traceWinFspStage(message: string)
    {
        #static if !#hastag("SCrypt.Integration") do
            return
        var stream = catch File.open(winFspStageLogPath(), .Append, .Write, .Read) as openError
        if openError != null do
            return
        discard catch stream.write(notnull @dataof(message), @countof(message))
        discard catch stream.write(@dataof("\n"), 1)
        stream.close()
    }

    func beginWinFspLog()->NativeHandle
    {
        let logPath16 = Utf16.toZeroTerminated(winFspLogPath())
        let handle = CreateFileW(@dataof(logPath16), GenericWrite, ShareRead,
            null, 2, NormalFile, null)
        if handle != InvalidHandle do
            (g_WinFsp.setDebugLogHandle)(handle)
        return handle
    }

    func endWinFspLog(handle: NativeHandle)
    {
        if handle == InvalidHandle do
            return
        (g_WinFsp.setDebugLogHandle)(InvalidHandle)
        discard CloseHandle(handle)
    }

    func winFspLogDetail()->String
    {
        var detail = catch File.readAllText(winFspLogPath()) as readError
        if readError != null do
            return Format.toString("Diagnostic log: %", winFspLogPath())
        detail.trim()
        return detail.isEmpty() ? Format.toString("Diagnostic log: %", winFspLogPath()) : detail
    }

    func loadWinFsp() fail
    {
        if g_WinFsp.module do
            return

        #static if #hastag("SCrypt.Integration") do
            discard catch File.writeAllBytes(winFspStageLogPath(),
                @mkslice(cast(const [*] u8) @dataof("load requested\n"),
                         @countof("load requested\n")))

        if g_WinFsp.guardianManaged
        {
            g_WinFsp.module = loadLibrary(g_WinFsp.dllPath)
            g_WinFsp.portable = true
        }
        else
        {
            let programFiles = environmentValue("ProgramFiles(x86)")
            if !programFiles.isEmpty()
            {
                let installedPath = Path.combine(programFiles, "WinFsp", "bin", "winfsp-x64.dll")
                if File.exists(installedPath)
                {
                    g_WinFsp.module = loadLibrary(installedPath)
                    g_WinFsp.dllPath = installedPath
                }
            }
        }

        if !g_WinFsp.module
        {
            if g_WinFsp.guardianProcess
            {
                traceWinFspStage("staging portable runtime")
                g_WinFsp.dllPath = try stagePortableWinFsp()
                traceWinFspStage("portable runtime staged")
            }
            else do
                try ensurePortableGuardian()
            g_WinFsp.module = loadLibrary(g_WinFsp.dllPath)
            traceWinFspStage("LoadLibraryW returned")
            g_WinFsp.portable = true
        }

        if !g_WinFsp.module
        {
            if !g_WinFsp.guardianManaged
            {
                removeRuntimeTree(g_WinFsp.runtimeRoot)
                g_WinFsp.runtimeRoot.clear()
            }
            SCrypt.failWith("Windows could not load the signed WinFsp runtime.")
        }

        traceWinFspStage("resolving WinFsp exports")
        discard catch resolveWinFspApi() as resolveError
        if resolveError != null
        {
            discard FreeLibrary(g_WinFsp.module)
            g_WinFsp.module = null
            if !g_WinFsp.guardianManaged
            {
                removeRuntimeTree(g_WinFsp.runtimeRoot)
                g_WinFsp.runtimeRoot.clear()
            }
            fail resolveError
        }
        traceWinFspStage("WinFsp exports resolved")

        if g_WinFsp.portable do
            traceWinFspStage("portable SxS runtime ready")
    }

    func registerPortableWinFsp() fail
    {
        if !g_WinFsp.portable or g_WinFsp.registered or g_WinFsp.guardianManaged do
            return

        traceWinFspStage("registering portable driver")
        let logHandle = beginWinFspLog()
        let result = (g_WinFsp.registerServer)()
        traceWinFspStage("DllRegisterServer returned")
        if result < 0
        {
            endWinFspLog(logHandle)
            SCrypt.failWith(Format.toString(
                "Windows refused to register the portable WinFsp driver (HRESULT 0x%).\n\n%",
                Format.toString("%{X}", cast(u32) result), winFspLogDetail()))
        }
        g_WinFsp.registered = true

        traceWinFspStage("starting portable driver")
        let startStatus = (g_WinFsp.startService)()
        traceWinFspStage("FspFsctlStartService returned")
        endWinFspLog(logHandle)
        if startStatus < 0 do
            SCrypt.failWith(Format.toString(
                "Windows registered the portable WinFsp driver but could not start it (NTSTATUS %{X}).\n\n%",
                cast(u32) startStatus, winFspLogDetail()))
    }

    func unloadWinFsp()
    {
        if g_WinFsp.guardianManaged and !g_WinFsp.guardianProcess
        {
            if g_WinFsp.module
            {
                discard FreeLibrary(g_WinFsp.module)
                g_WinFsp.module = null
            }
            g_WinFsp.portable = false
            return
        }

        var canRemoveRuntime = true
        if g_WinFsp.portable and g_WinFsp.registered
        {
            if (g_WinFsp.unregisterServer)() < 0 do
                canRemoveRuntime = false
            else do
                g_WinFsp.registered = false
        }

        if g_WinFsp.module
        {
            discard FreeLibrary(g_WinFsp.module)
            g_WinFsp.module = null
        }
        if canRemoveRuntime do
            removeRuntimeTree(g_WinFsp.runtimeRoot)
        g_WinFsp.runtimeRoot.clear()
        g_WinFsp.dllPath.clear()
        g_WinFsp.portable = false
    }
}
