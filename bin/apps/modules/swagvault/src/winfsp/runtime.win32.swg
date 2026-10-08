#global if WINDOWS

using Core, Win32

namespace WinFsp
{
    // The export `name` of the loaded runtime, given as a literal so it is zero-terminated. A
    // missing export means the bundled runtime is not the one Swag Vault was built against.
    func winFspExport(name: string)->const *void fail
    {
        let address = GetProcAddress(g_WinFsp.module, name.buffer)
        if not address do
            try failWith("The bundled WinFsp runtime does not expose the expected ABI.")
        return address!
    }

    // Binds every WinFsp export the mount uses, and fails when one is missing.
    func resolveWinFspApi() fail
    {
        let setSecurity = try winFspExport("FspSetSecurityDescriptor")
        g_WinFsp.fsCreate                 = cast(FspFileSystemCreateFn, try winFspExport("FspFileSystemCreate"))
        g_WinFsp.destroy                  = cast(FspFileSystemDeleteFn, try winFspExport("FspFileSystemDelete"))
        g_WinFsp.setMountPoint            = cast(FspFileSystemSetMountPointFn, try winFspExport("FspFileSystemSetMountPoint"))
        g_WinFsp.removeMountPoint         = cast(FspFileSystemRemoveMountPointFn, try winFspExport("FspFileSystemRemoveMountPoint"))
        g_WinFsp.startDispatcher          = cast(FspFileSystemStartDispatcherFn, try winFspExport("FspFileSystemStartDispatcher"))
        g_WinFsp.stopDispatcher           = cast(FspFileSystemStopDispatcherFn, try winFspExport("FspFileSystemStopDispatcher"))
        g_WinFsp.addDirInfo               = cast(FspFileSystemAddDirInfoFn, try winFspExport("FspFileSystemAddDirInfo"))
        g_WinFsp.setGuard                 = cast(FspFileSystemSetGuardFn, try winFspExport("FspFileSystemSetOperationGuardStrategyF"))
        g_WinFsp.setSecurityDescriptor    = cast(FspSetSecurityDescriptorFn, setSecurity)
        g_WinFsp.setSecurityAddress       = setSecurity
        g_WinFsp.deleteSecurityDescriptor = cast(FspDeleteSecurityDescriptorFn, try winFspExport("FspDeleteSecurityDescriptor"))
        g_WinFsp.registerServer           = cast(WinFspRegistrationFn, try winFspExport("DllRegisterServer"))
        g_WinFsp.unregisterServer         = cast(WinFspRegistrationFn, try winFspExport("DllUnregisterServer"))
        g_WinFsp.setDebugLogHandle        = cast(FspDebugLogSetHandleFn, try winFspExport("FspDebugLogSetHandle"))
        g_WinFsp.startService             = cast(FspFsctlStartServiceFn, try winFspExport("FspFsctlStartService"))
    }

    // A log file of the temporary directory, or of the working directory when Windows gives none.
    func tempLogPath(name: string)->String
    {
        let temp = Env.getSpecialDirectory(.Temp)
        return temp.isEmpty() ? name : Path.combine(temp, name)
    }

    // The WinFsp debug log, and the trace of the loading stages kept by integration builds.
    func winFspLogPath()->String      => tempLogPath("vault-WinFsp.log")
    func winFspStageLogPath()->String => tempLogPath("vault-WinFsp-stage.log")

    // Appends a loading stage to the trace; only integration builds keep one.
    func traceWinFspStage(message: string)
    {
        #static if not #hastag("vault.integration") do
            return
        var stream = catch File.open(winFspStageLogPath(), .Append, .Write, .Read) as openError
        if openError != null do
            return
        discard catch stream.write(message.buffer, message.count)
        discard catch stream.write(("\n").buffer, 1)
        stream.close()
    }

    // Sends the WinFsp debug output to its log file for the registration that follows.
    func beginWinFspLog()->NativeHandle
    {
        let logPath16 = Utf16.toZeroTerminated(winFspLogPath())
        let handle    = catch CreateFileW(logPath16.buffer, GenericWrite, ShareRead, null, 2, NormalFile, null) as error
        if error != null do
            return InvalidHandle
        if handle != InvalidHandle do
            (g_WinFsp.setDebugLogHandle)(handle)
        return handle
    }

    // Stops the WinFsp debug output and closes its log file.
    func endWinFspLog(handle: NativeHandle)
    {
        if handle == InvalidHandle do
            return
        (g_WinFsp.setDebugLogHandle)(InvalidHandle)
        CloseHandle(handle)
    }

    // What the WinFsp debug log says, or where to find it when it cannot be read.
    func winFspLogDetail()->String
    {
        var detail = catch File.readAllText(winFspLogPath()) as readError
        if readError != null do
            return Format.toString("Diagnostic log: %", winFspLogPath())
        detail.trim()
        return detail.isEmpty() ? Format.toString("Diagnostic log: %", winFspLogPath()) : detail
    }

    // Removes the runtime this process staged; a runtime staged by the guardian is its own to remove.
    func discardStagedRuntime()
    {
        if g_WinFsp.guardianManaged do
            return
        removeRuntimeTree(g_WinFsp.runtimeRoot)
        g_WinFsp.runtimeRoot.clear()
    }

    // Loads WinFsp once: the installed runtime when there is one, otherwise the signed portable
    // runtime shipped next to the executable, registered by the elevated guardian.
    func loadWinFsp() fail
    {
        if g_WinFsp.module do
            return

        #static if #hastag("vault.integration") do
            discard catch File.writeAllBytes(winFspStageLogPath(), Swag.makeSlice(cast(const [*] u8, ("load requested\n").buffer), ("load requested\n").count))

        if g_WinFsp.guardianManaged
        {
            g_WinFsp.module   = loadLibrary(g_WinFsp.dllPath)
            g_WinFsp.portable = true
        }
        else
        {
            let programFiles = environmentValue("ProgramFiles(x86)")
            if not programFiles.isEmpty()
            {
                let installedPath = Path.combine(programFiles, "WinFsp", "bin", "winfsp-x64.dll")
                if File.exists(installedPath)
                {
                    g_WinFsp.module  = loadLibrary(installedPath)
                    g_WinFsp.dllPath = installedPath
                }
            }
        }

        if not g_WinFsp.module
        {
            if g_WinFsp.guardianProcess
            {
                traceWinFspStage("staging portable runtime")
                g_WinFsp.dllPath = try stagePortableWinFsp()
                traceWinFspStage("portable runtime staged")
            }
            else
            {
                try ensurePortableGuardian()
            }

            g_WinFsp.module = loadLibrary(g_WinFsp.dllPath)
            traceWinFspStage("LoadLibraryW returned")
            g_WinFsp.portable = true
        }

        if not g_WinFsp.module
        {
            discardStagedRuntime()

            try failWith("Windows could not load the signed WinFsp runtime.")
        }

        traceWinFspStage("resolving WinFsp exports")
        discard catch resolveWinFspApi() as resolveError
        if resolveError != null
        {
            discard FreeLibrary(g_WinFsp.module)
            g_WinFsp.module = null
            discardStagedRuntime()

            fail resolveError
        }

        traceWinFspStage("WinFsp exports resolved")

        if g_WinFsp.portable do
            traceWinFspStage("portable SxS runtime ready")
    }

    // Releases WinFsp: unregisters the portable driver this process registered, unloads the
    // library, and removes the staged runtime once nothing holds it.
    func unloadWinFsp()
    {
        if g_WinFsp.guardianManaged and not g_WinFsp.guardianProcess
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
