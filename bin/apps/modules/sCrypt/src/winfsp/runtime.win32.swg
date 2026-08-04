#global if WINDOWS

using Core

namespace WinFsp
{
    func resolveWinFspApi() fail
    {
        let create            = GetProcAddress(g_WinFsp.module, @dataof("FspFileSystemCreate"))
        let destroy           = GetProcAddress(g_WinFsp.module, @dataof("FspFileSystemDelete"))
        let setMountPoint     = GetProcAddress(g_WinFsp.module, @dataof("FspFileSystemSetMountPoint"))
        let removeMountPoint  = GetProcAddress(g_WinFsp.module, @dataof("FspFileSystemRemoveMountPoint"))
        let startDispatcher   = GetProcAddress(g_WinFsp.module, @dataof("FspFileSystemStartDispatcher"))
        let stopDispatcher    = GetProcAddress(g_WinFsp.module, @dataof("FspFileSystemStopDispatcher"))
        let addDirInfo        = GetProcAddress(g_WinFsp.module, @dataof("FspFileSystemAddDirInfo"))
        let setGuard          = GetProcAddress(g_WinFsp.module, @dataof("FspFileSystemSetOperationGuardStrategyF"))
        let setSecurity       = GetProcAddress(g_WinFsp.module, @dataof("FspSetSecurityDescriptor"))
        let deleteSecurity    = GetProcAddress(g_WinFsp.module, @dataof("FspDeleteSecurityDescriptor"))
        let registerServer    = GetProcAddress(g_WinFsp.module, @dataof("DllRegisterServer"))
        let unregisterServer  = GetProcAddress(g_WinFsp.module, @dataof("DllUnregisterServer"))
        let setDebugLogHandle = GetProcAddress(g_WinFsp.module, @dataof("FspDebugLogSetHandle"))
        let startService      = GetProcAddress(g_WinFsp.module, @dataof("FspFsctlStartService"))

        if !create or !destroy or !setMountPoint or !removeMountPoint or !startDispatcher or !stopDispatcher or !addDirInfo or !setGuard or !setSecurity or !deleteSecurity or !registerServer or !unregisterServer or !setDebugLogHandle or !startService do
            failWith("The bundled WinFsp runtime does not expose the expected ABI.")

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
        let handle    = CreateFileW(@dataof(logPath16), GenericWrite, ShareRead, null, 2, NormalFile, null)
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
            discard catch File.writeAllBytes(winFspStageLogPath(), @mkslice(cast(const [*] u8) @dataof("load requested\n"), @countof("load requested\n")))

        if g_WinFsp.guardianManaged
        {
            g_WinFsp.module   = loadLibrary(g_WinFsp.dllPath)
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
                    g_WinFsp.module  = loadLibrary(installedPath)
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

            failWith("Windows could not load the signed WinFsp runtime.")
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
