#global if WINDOWS

using Core

namespace WinFsp
{
    func isPortableGuardianInvocation()->bool
    {
        let args = Env.arguments()
        return @countof(args) >= 2 and args[1] == WinFspGuardianArgument
    }

    func guardianErrorText(err: #null any)->string
    {
        switch err
        {
        case Error:            return (cast(Error) err).message orelse "The portable WinFsp runtime failed."
        case Swag.SystemError: return (cast(Swag.SystemError) err).message orelse "Windows rejected the WinFsp helper."
        }

        return "The portable WinFsp helper failed."
    }

    func writeGuardianStatus(path, status: string) fail
    {
        discard File.writeAllBytes(path, @mkslice(cast(const [*] u8) @dataof(status), @countof(status)))
    }

    func startPortableGuardian(statusPath: string) fail
    {
        g_WinFsp.guardianProcess = true
        try loadWinFsp()
        try registerPortableWinFsp()
        try writeGuardianStatus(statusPath, Format.toString("READY\n%", g_WinFsp.dllPath))
    }

    func runPortableGuardian()->s32
    {
        let args = Env.arguments()
        if @countof(args) < 4 or args[1] != WinFspGuardianArgument or !isElevated() do
            return 2

        let parsed     = catch StrConv.parseU32(args[2]) as parseError
        let statusPath = args[3]
        if parseError != null or parsed.ovf or parsed.eat != @countof(args[2]) do
            return 2

        let parent = OpenProcess(ProcessSynchronize, 0, parsed.value)
        if !parent
        {
            discard catch writeGuardianStatus(statusPath, "ERROR\nThe WinFsp helper could not monitor the Swag Vault process.")
            return 1
        }

        discard catch startPortableGuardian(statusPath) as startError
        if startError != null
        {
            discard catch writeGuardianStatus(statusPath, Format.toString("ERROR\n%", guardianErrorText(startError)))
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

    // Whether this build is allowed to raise a Windows consent dialog.
    //
    // An ordinary test build never is: an automated run has nobody to accept the
    // dialog, so a test that reached the elevation path would hang instead of
    // failing. The privileged end-to-end harness is the one build that may,
    // and it is opt-in through the `vault.integration` tag.
    func canRequestElevation()->bool
    {
        #static if #command == Swag.CompilerCommand.Test and !#hastag("vault.integration") do
            return false
        return true
    }

    func ensurePortableGuardian() fail
    {
        // Checked before anything else, so no test run can reach ShellExecute.
        if !canRequestElevation() do
            failWith("This build must not request elevation. Mounting belongs to the privileged integration harness.")

        if g_WinFsp.guardianManaged do
            return
        if isElevated() do
            failWith("Launch Swag Vault normally, not with 'Run as administrator', so Windows Explorer can see the mounted drive.")

        let temp = Env.getSpecialDirectory(.Temp)
        if temp.isEmpty() do
            failWith("Windows did not provide a usable temporary directory.")

        let communicationRoot = Path.combine(temp, Format.toString("vault-Guardian-%-%", Env.Process.currentProcessId(), Guid64.random()))
        Directory.create(communicationRoot)
        let statusPath     = Path.combine(communicationRoot, "status.txt")
        let parameters     = Format.toString("% % \"%\"", WinFspGuardianArgument, Env.Process.currentProcessId(), statusPath)
        let executablePath = try Env.Process.currentExecutablePath()
        let executable16   = Utf16.toZeroTerminated(executablePath)
        let operation16    = Utf16.toZeroTerminated("runas")
        let parameters16   = Utf16.toZeroTerminated(parameters)
        let directory16    = Utf16.toZeroTerminated(Path.directoryName(executablePath) orelse "")
        let launch         = ShellExecuteW(null, @dataof(operation16), @dataof(executable16), @dataof(parameters16), @dataof(directory16), 0)
        if cast(u64) launch <= 32
        {
            removeRuntimeTree(communicationRoot)
            failWith(Format.toString("Windows could not start the portable WinFsp helper (ShellExecute code %, Windows error %).", cast(u64) launch, GetLastError()))
        }

        for attempt in 1200
        {
            discard attempt
            var status = catch File.readAllText(statusPath) as readError
            if readError == null
            {
                status.trim()
                if status.startsWith("READY\n") and @countof(status) > @countof("READY\n")
                {
                    g_WinFsp.dllPath         = @mkstring(@dataof(status) + @countof("READY\n"), @countof(status) - @countof("READY\n"))
                    g_WinFsp.guardianManaged = true
                    return
                }

                if status.startsWith("ERROR\n")
                {
                    let prefixCount = @countof("ERROR\n")
                    let detail      = @countof(status) > prefixCount ? @mkstring(@dataof(status) + prefixCount, @countof(status) - prefixCount) : "The portable WinFsp helper failed."
                    failWith(detail)
                }
            }

            Threading.Thread.sleep(50'ms)
        }

        failWith("The portable WinFsp helper did not become ready in time.")
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
        let executablePath      = try Env.Process.currentExecutablePath()
        let executableDirectory = Path.directoryName(executablePath) orelse ""
        let sourceDll           = Path.combine(executableDirectory, WinFspDllName)
        let sourceDriver        = Path.combine(executableDirectory, WinFspDriverName)
        if !File.exists(sourceDll) or !File.exists(sourceDriver) do
            failWith("The signed portable WinFsp runtime is incomplete.")

        let temp = Env.getSpecialDirectory(.Temp)
        if temp.isEmpty() do
            failWith("Windows did not provide a usable temporary directory.")

        var root = Path.combine(temp, Format.toString("vault-WinFsp-%-%", Env.Process.currentProcessId(), Time.Timestamp.utcNow().ticks))
        Directory.create(root)

        let bin = Path.combine(root, "bin")
        Directory.create(bin)
        let dll    = Path.combine(bin, WinFspDllName)
        let driver = Path.combine(bin, WinFspDriverName)
        discard catch File.duplicate(dll, sourceDll) as dllError
        discard catch File.duplicate(driver, sourceDriver) as driverError
        if dllError != null or driverError != null or !File.exists(dll) or !File.exists(driver)
        {
            removeRuntimeTree(root)
            failWith("The portable WinFsp runtime could not be staged.")
        }

        let identity = Path.combine(bin, "winfsp.sxs")
        discard File.writeAllBytes(identity, @mkslice(cast(const [*] u8) @dataof("swagvault\n"), @countof("swagvault\n")))
        g_WinFsp.runtimeRoot = #move root
        return dll
    }

    func registerPortableWinFsp() fail
    {
        if !g_WinFsp.portable or g_WinFsp.registered or g_WinFsp.guardianManaged do
            return

        traceWinFspStage("registering portable driver")
        let logHandle = beginWinFspLog()
        let result    = (g_WinFsp.registerServer)()
        traceWinFspStage("DllRegisterServer returned")
        if result < 0
        {
            endWinFspLog(logHandle)
            failWith(Format.toString("Windows refused to register the portable WinFsp driver (HRESULT 0x%).\n\n%", Format.toString("%{X}", statusBits(result)), winFspLogDetail()))
        }

        g_WinFsp.registered = true

        traceWinFspStage("starting portable driver")
        let startStatus = (g_WinFsp.startService)()
        traceWinFspStage("FspFsctlStartService returned")
        endWinFspLog(logHandle)
        if startStatus < 0 do
            failWith(Format.toString("Windows registered the portable WinFsp driver but could not start it (NTSTATUS %{X}).\n\n%", statusBits(startStatus), winFspLogDetail()))
    }
}

func isMountHostInvocationNative()->bool => WinFsp.isPortableGuardianInvocation()

func runMountHostNative()->s32 => WinFsp.runPortableGuardian()
