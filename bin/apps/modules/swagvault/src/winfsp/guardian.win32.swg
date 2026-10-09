#global if WINDOWS

using Core, Win32

namespace WinFsp
{
    // Whether this process was launched as the guardian of another Swag Vault.
    func isPortableGuardianInvocation()->bool
    {
        let args = Env.arguments()
        return args.count >= 2 and args[1] == WinFspGuardianArgument
    }

    // The kind the guardian reports for a start that failed: what the volume layer said, or the
    // driver being unavailable for any other failure.
    func guardianErrorKind(err: any?)->ErrorKind
    {
        if err is Error as error do
            return error.kind
        return .DriverUnavailable
    }

    // The Windows error a helper launch that failed reported, or 0.
    func guardianLaunchCode(err: any?)->u64
    {
        if err is Swag.SystemError as error do
            return error.errorID
        return 0
    }

    // The status line that tells the waiting application why the guardian stopped.
    func guardianErrorStatus(kind: ErrorKind)->String => Format.toString("ERROR\n%", cast(u32, kind))

    // Tells the waiting application how the guardian started, through the status file.
    func writeGuardianStatus(path, status: string) fail
    {
        discard try File.writeAllText(path, status)
    }

    // Loads and registers the portable runtime, then reports `READY` with the path of its library.
    func startPortableGuardian(statusPath: string) fail
    {
        g_WinFsp.guardianProcess = true
        try loadWinFsp()
        try registerPortableWinFsp()
        try writeGuardianStatus(statusPath, Format.toString("READY\n%", g_WinFsp.dllPath))
    }

    // The guardian process: elevated, it registers the portable driver, keeps it while the
    // application that launched it lives, and removes it afterwards. Returns the process exit code.
    func runPortableGuardian()->s32
    {
        let args = Env.arguments()
        if args.count < 4 or args[1] != WinFspGuardianArgument or not isElevated() do
            return 2

        let parsed     = catch StrConv.parseU32(args[2]) as parseError
        let statusPath = args[3]
        if parseError != null or parsed.ovf or parsed.eat != args[2].count do
            return 2

        let parent = OpenProcess(ProcessSynchronize, 0, parsed.value)
        if not parent
        {
            discard catch writeGuardianStatus(statusPath, guardianErrorStatus(.DriverUnavailable))
            return 1
        }

        discard catch startPortableGuardian(statusPath) as startError
        if startError != null
        {
            discard catch writeGuardianStatus(statusPath, guardianErrorStatus(guardianErrorKind(startError)))
            unloadWinFsp()
            CloseHandle(parent)
            return 1
        }

        expect WaitForSingleObject(parent, WaitInfinite)
        CloseHandle(parent)
        unloadWinFsp()
        let communicationRoot = Path.directoryName(statusPath) orelse ""
        if communicationRoot.count do
            removeRuntimeTree(communicationRoot)
        return 0
    }

    // Whether this build is allowed to raise a Windows consent dialog.
    //
    // An ordinary test build never is: an automated run has nobody to accept the
    // dialog, so a test that reached the elevation path would hang instead of
    // failing. The privileged end-to-end harness is the one build that may,
    // and it is opt-in through the `vault.integration` tag.
    func canRequestElevation()->bool
    {
        #static if #command == Swag.CompilerCommand.Test and not #hastag("vault.integration") do
            return false
        return true
    }

    // Launches the elevated guardian once, and waits for its status file to report the library to
    // load, or why it could not.
    func ensurePortableGuardian() fail
    {
        // Checked before anything else, so no test run can reach ShellExecute.
        if not canRequestElevation() do
            fail volumeError(.DriverUnavailable)

        if g_WinFsp.guardianManaged do
            return
        if isElevated() do
            fail volumeError(.Elevated)

        let temp = Env.getSpecialDirectory(.Temp)
        if temp.isEmpty() do
            fail volumeError(.DriverUnavailable)

        let communicationRoot = Path.combine(temp, Format.toString("vault-Guardian-%-%", Env.Process.currentProcessId(), Guid64.random()))
        try Directory.create(communicationRoot)
        let statusPath     = Path.combine(communicationRoot, "status.txt")
        let parameters     = Format.toString("% % \"%\"", WinFspGuardianArgument, Env.Process.currentProcessId(), statusPath)
        let executablePath = try Env.Process.currentExecutablePath()
        let executable16   = Utf16.toZeroTerminated(executablePath)
        let operation16    = Utf16.toZeroTerminated("runas")
        let parameters16   = Utf16.toZeroTerminated(parameters)
        let directory16    = Utf16.toZeroTerminated(Path.directoryName(executablePath) orelse "")
        discard catch ShellExecuteW(null, operation16.buffer, executable16.buffer, parameters16.buffer, directory16.buffer, 0) as launchError
        if launchError != null
        {
            removeRuntimeTree(communicationRoot)
            fail volumeError(.DriverUnavailable, guardianLaunchCode(launchError))
        }

        for 1200
        {
            var status = catch File.readAllText(statusPath) as readError
            if readError == null
            {
                status.trim()
                if status.startsWith("READY\n") and status.count > ("READY\n").count
                {
                    g_WinFsp.dllPath         = Swag.makeString(status.buffer + ("READY\n").count, status.count - ("READY\n").count)
                    g_WinFsp.guardianManaged = true
                    return
                }

                if status.startsWith("ERROR\n")
                {
                    let prefixCount = ("ERROR\n").count
                    let reported    = catch StrConv.parseU32(Swag.makeString(status.buffer + prefixCount, status.count - prefixCount)) as parseError
                    let known       = parseError == null and reported.value <= cast(u32, ErrorKind.DriverUnavailable)
                    fail volumeError(known ? cast(ErrorKind, reported.value) : .DriverUnavailable)
                }
            }

            Threading.Thread.sleep(50'ms)
        }

        fail volumeError(.DriverUnavailable)
    }

    // Deletes a staged runtime directory and everything below it; what Windows still holds is
    // deleted at the next restart.
    func removeRuntimeTree(path: string)
    {
        if not Directory.exists(path) do
            return

        var options: Directory.EnumerationOptions
        var entries = catch Directory.enumerate(path, options) as enumError
        if enumError == null
        {
            for entry in entries
            {
                if entry.isDirectory()
                {
                    removeRuntimeTree(entry.fullName)
                }
                else
                {
                    discard catch File.delete(entry.fullName) as deleteError
                    if deleteError != null
                    {
                        let entry16 = Utf16.toZeroTerminated(entry.fullName)
                        catch MoveFileExW(entry16.buffer, null, MoveDelayUntilReboot)
                    }
                }
            }
        }

        let path16 = Utf16.toZeroTerminated(path)
        catch RemoveDirectoryW(path16.buffer) as error
        if error != null do
            catch MoveFileExW(path16.buffer, null, MoveDelayUntilReboot)
    }

    // Copies the portable library and driver into a fresh temporary directory, under an identity of
    // their own, and returns the path of the library.
    func stagePortableWinFsp()->String fail
    {
        let executablePath      = try Env.Process.currentExecutablePath()
        let executableDirectory = Path.directoryName(executablePath) orelse ""
        let sourceDll           = Path.combine(executableDirectory, WinFspDllName)
        let sourceDriver        = Path.combine(executableDirectory, WinFspDriverName)
        if not File.exists(sourceDll) or not File.exists(sourceDriver) do
            fail volumeError(.DriverUnavailable)

        let temp = Env.getSpecialDirectory(.Temp)
        if temp.isEmpty() do
            fail volumeError(.DriverUnavailable)

        // A guardian owns one driver registration. Sharing an identity across processes lets
        // one guardian unregister another's driver, and a pending deletion blocks every restart.
        // WinFsp reads at most 32 bytes from the SxS identity file.
        let sxsName = Format.toString("%-%", WinFspSxsName, Guid64.random())
        var root    = Path.combine(temp, Format.toString("vault-WinFsp-%", sxsName))
        try Directory.create(root)

        let bin = Path.combine(root, "bin")
        try Directory.create(bin)
        let dll    = Path.combine(bin, WinFspDllName)
        let driver = Path.combine(bin, WinFspDriverName)
        discard catch File.duplicate(dll, sourceDll) as dllError
        discard catch File.duplicate(driver, sourceDriver) as driverError
        if dllError != null or driverError != null or not File.exists(dll) or not File.exists(driver)
        {
            removeRuntimeTree(root)
            fail volumeError(.DriverUnavailable)
        }

        let identity = Path.combine(bin, "winfsp.sxs")
        discard try File.writeAllBytes(identity, sxsName.toSlice())
        g_WinFsp.runtimeRoot = #move root
        return dll
    }

    // Registers the staged driver with Windows and starts it.
    func registerPortableWinFsp() fail
    {
        if not g_WinFsp.portable or g_WinFsp.registered or g_WinFsp.guardianManaged do
            return

        traceWinFspStage("registering portable driver")
        let logHandle = beginWinFspLog()
        let result    = (g_WinFsp.registerServer)()
        traceWinFspStage("DllRegisterServer returned")
        if result < 0
        {
            endWinFspLog(logHandle)
            traceWinFspStage(winFspLogDetail())
            fail volumeError(.DriverUnavailable, statusBits(result))
        }

        g_WinFsp.registered = true

        traceWinFspStage("starting portable driver")
        let startStatus = (g_WinFsp.startService)()
        traceWinFspStage("FspFsctlStartService returned")
        endWinFspLog(logHandle)
        if startStatus < 0
        {
            traceWinFspStage(winFspLogDetail())
            fail volumeError(.DriverUnavailable, statusBits(startStatus))
        }
    }
}

func isMountHostInvocationNative()->bool => WinFsp.isPortableGuardianInvocation()

func runMountHostNative()->s32 => WinFsp.runPortableGuardian()
