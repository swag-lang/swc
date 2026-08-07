#global if #command == Swag.CompilerCommand.Test
#global if WINDOWS
#global private

using Swag

#test
{
    let executable = expect Env.Process.currentExecutablePath()
    @assert(Path.isRooted(executable))
    @assert(File.exists(executable))
}

// Returns the path of a system executable this test drives.
//
// These tests launch real system programs, so they have to look outside any sandbox to find
// them. Data an application owns must never be reached this way.
func systemExecutablePath(name: string)->String
{
    let fontsDir = Env.realSpecialDirectory(Env.SpecialDirectory.Font)
    @assert(fontsDir.length != 0)

    let windowsDir = Path.directoryName(fontsDir.toString())
    @assert(windowsDir != null)

    let systemDir = Path.combine(windowsDir, "System32")
    return Path.combine(systemDir.toString(), name)
}

#test
{
    // A path containing a space has to survive the command line, so the shell is started from
    // a copy of itself placed under one.
    let sourceExe = systemExecutablePath("cmd.exe")
    @assert(File.exists(sourceExe.toString()))

    var targetExe = CoreTests.makeFilesystemTestPath("process_copy")
    targetExe += " with spaces.exe"

    defer
    {
        if File.exists(targetExe.toString()) do
            discard catch File.delete(targetExe.toString())
    }

    discard expect File.duplicate(targetExe.toString(), sourceExe.toString())
    @assert(File.exists(targetExe.toString()))

    let process = expect Env.runProcess(targetExe.toString(), "/c exit 7")
    @assert(process.exitCode() == 7)
    @assert(!process.isRunning())
}

#test
{
    let shell = systemExecutablePath("cmd.exe")

    let process = expect Env.runProcess(shell.toString(), "/c echo to-standard-output& echo to-standard-error 1>&2")
    @assert(process.exitCode() == 0)

    let output = String.from(process.standardOutput())
    let errors = String.from(process.standardError())
    @assert(output.contains("to-standard-output"))
    @assert(errors.contains("to-standard-error"))
    @assert(!output.contains("to-standard-error"))
}

#test
{
    let shell     = systemExecutablePath("cmd.exe")
    let directory = Env.getSpecialDirectory(.Temp)

    var info    = Env.StartInfo{fileName: shell.toString(), arguments: "/c cd", workingDirectory: directory.toString(), standardOutput: .Pipe}
    let process = expect Env.runProcess(info)
    @assert(process.exitCode() == 0)

    // The shell reports the directory it actually started in, spelled the native way and
    // without the separator a well-known directory can end on.
    var reported = String.from(process.standardOutput())
    reported.trim()
    reported.replace("\\", "/")

    var expected = String.from(directory.toString())
    if expected.endsWith("/") do
        expected.removeBack()

    @assert(Utf8.compare(reported.toSlice(), expected.toSlice(), .Latin1NoCase) == 0)
}

#test
{
    let shell = systemExecutablePath("cmd.exe")

    var environment = Env.currentEnvironment()
    @assert(environment.count() != 0)

    environment.set("SWAG_PROCESS_TEST", "captured-value")
    @assert(environment.value("SWAG_PROCESS_TEST") == "captured-value")

    // Windows matches variable names without regard to case, so a lookup finds it either way.
    @assert(environment.value("swag_process_test") == "captured-value")

    var info          = Env.StartInfo{fileName: shell.toString(), arguments: "/c echo %SWAG_PROCESS_TEST%", environment: &environment, standardOutput: .Pipe}
    let granted       = expect Env.runProcess(info)
    let grantedOutput = String.from(granted.standardOutput())
    @assert(grantedOutput.contains("captured-value"))

    // An unset variable is left as written by the shell, which is how the child reports that
    // the override really disappeared instead of merely turning empty.
    environment.remove("SWAG_PROCESS_TEST")
    @assert(environment.value("SWAG_PROCESS_TEST") == null)

    let revoked       = expect Env.runProcess(info)
    let revokedOutput = String.from(revoked.standardOutput())
    @assert(revokedOutput.contains("%SWAG_PROCESS_TEST%"))
}

#test
{
    let sorter = systemExecutablePath("sort.exe")

    var info    = Env.StartInfo{fileName: sorter.toString(), standardInput: .Pipe, standardOutput: .Pipe}
    var process = expect Env.startProcess(info)

    expect process.writeStandardInput("second\r\nfirst\r\n")
    process.closeStandardInput()

    let exitCode = expect process.waitForExit()
    @assert(exitCode == 0)

    var sorted = String.from(process.standardOutput())
    sorted.trim()
    @assert(sorted.startsWith("first"))
}

#test
{
    // A program that keeps running until it is stopped, so the kill has something to reach.
    let waiter = systemExecutablePath("ping.exe")

    var info    = Env.StartInfo{fileName: waiter.toString(), arguments: "-n 20 127.0.0.1", standardOutput: .Discard}
    var process = expect Env.startProcess(info)
    @assert(process.isRunning())
    @assert(process.processId != 0)

    let exitedEarly = expect process.tryWaitForExit(50'ms)
    @assert(!exitedEarly)

    expect process.kill(9)
    let exitCode = expect process.waitForExit()
    @assert(exitCode == 9)
    @assert(!process.isRunning())

    // A discarded stream is not captured, so nothing reaches this side.
    @assert(@countof(process.standardOutput()) == 0)
}
