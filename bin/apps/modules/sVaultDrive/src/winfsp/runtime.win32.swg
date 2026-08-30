#global if WINDOWS

using Core

namespace WinFsp
{
    func resolveWinFspApi() fail
    {
        let create            = GetProcAddress(g_WinFsp.module, ("FspFileSystemCreate").buffer)
        let destroy           = GetProcAddress(g_WinFsp.module, ("FspFileSystemDelete").buffer)
        let setMountPoint     = GetProcAddress(g_WinFsp.module, ("FspFileSystemSetMountPoint").buffer)
        let removeMountPoint  = GetProcAddress(g_WinFsp.module, ("FspFileSystemRemoveMountPoint").buffer)
        let startDispatcher   = GetProcAddress(g_WinFsp.module, ("FspFileSystemStartDispatcher").buffer)
        let stopDispatcher    = GetProcAddress(g_WinFsp.module, ("FspFileSystemStopDispatcher").buffer)
        let addDirInfo        = GetProcAddress(g_WinFsp.module, ("FspFileSystemAddDirInfo").buffer)
        let setGuard          = GetProcAddress(g_WinFsp.module, ("FspFileSystemSetOperationGuardStrategyF").buffer)
        let setSecurity       = GetProcAddress(g_WinFsp.module, ("FspSetSecurityDescriptor").buffer)
        let deleteSecurity    = GetProcAddress(g_WinFsp.module, ("FspDeleteSecurityDescriptor").buffer)
        let registerServer    = GetProcAddress(g_WinFsp.module, ("DllRegisterServer").buffer)
        let unregisterServer  = GetProcAddress(g_WinFsp.module, ("DllUnregisterServer").buffer)
        let setDebugLogHandle = GetProcAddress(g_WinFsp.module, ("FspDebugLogSetHandle").buffer)
        let startService      = GetProcAddress(g_WinFsp.module, ("FspFsctlStartService").buffer)

        if !create or !destroy or !setMountPoint or !removeMountPoint or !startDispatcher or !stopDispatcher or !addDirInfo or !setGuard or !setSecurity or !deleteSecurity or !registerServer or !unregisterServer or !setDebugLogHandle or !startService do
            failWith("The bundled WinFsp runtime does not expose the expected ABI.")

        g_WinFsp.fsCreate                 = cast(FspFileSystemCreateFn) create!
        g_WinFsp.destroy                  = cast(FspFileSystemDeleteFn) destroy!
        g_WinFsp.setMountPoint            = cast(FspFileSystemSetMountPointFn) setMountPoint!
        g_WinFsp.removeMountPoint         = cast(FspFileSystemRemoveMountPointFn) removeMountPoint!
        g_WinFsp.startDispatcher          = cast(FspFileSystemStartDispatcherFn) startDispatcher!
        g_WinFsp.stopDispatcher           = cast(FspFileSystemStopDispatcherFn) stopDispatcher!
        g_WinFsp.addDirInfo               = cast(FspFileSystemAddDirInfoFn) addDirInfo!
        g_WinFsp.setGuard                 = cast(FspFileSystemSetGuardFn) setGuard!
        g_WinFsp.setSecurityDescriptor    = cast(FspSetSecurityDescriptorFn) setSecurity!
        g_WinFsp.setSecurityAddress       = setSecurity!
        g_WinFsp.deleteSecurityDescriptor = cast(FspDeleteSecurityDescriptorFn) deleteSecurity!
        g_WinFsp.registerServer           = cast(WinFspRegistrationFn) registerServer!
        g_WinFsp.unregisterServer         = cast(WinFspRegistrationFn) unregisterServer!
        g_WinFsp.setDebugLogHandle        = cast(FspDebugLogSetHandleFn) setDebugLogHandle!
        g_WinFsp.startService             = cast(FspFsctlStartServiceFn) startService!
    }

    func winFspLogPath()->String
    {
        let temp = Env.getSpecialDirectory(.Temp)
        return temp.isEmpty() ? "sVaultDrive-WinFsp.log" : Path.combine(temp, "sVaultDrive-WinFsp.log")
    }

    func winFspStageLogPath()->String
    {
        let temp = Env.getSpecialDirectory(.Temp)
        return temp.isEmpty() ? "sVaultDrive-WinFsp-stage.log" : Path.combine(temp, "sVaultDrive-WinFsp-stage.log")
    }

    func traceWinFspStage(message: string)
    {
        #static if !#hastag("SVaultDrive.Integration") do
            return
        var stream = catch File.open(winFspStageLogPath(), .Append, .Write, .Read) as openError
        if openError != null do
            return
        discard catch stream.write(message.buffer!, message.count)
        discard catch stream.write(("\n").buffer, 1)
        stream.close()
    }

    func beginWinFspLog()->NativeHandle
    {
        let logPath16 = Utf16.toZeroTerminated(winFspLogPath())
        let handle    = CreateFileW(logPath16.buffer, GenericWrite, ShareRead, null, 2, NormalFile, null)
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

        #static if #hastag("SVaultDrive.Integration") do
            discard catch File.writeAllBytes(winFspStageLogPath(), Swag.makeSlice(cast(const [*] u8) ("load requested\n").buffer, ("load requested\n").count))

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
