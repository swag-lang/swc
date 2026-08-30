#global if #command == Swag.CompilerCommand.Test
#global if WINDOWS
#global private

using Swag

#test
{
    let executable = expect Env.Process.currentExecutablePath()
    Swag.assert(Path.isRooted(executable))
    Swag.assert(File.exists(executable))
}

// Returns the path of a system executable this test drives.
//
// These tests launch real system programs, so they have to look outside any sandbox to find
// them. Data an application owns must never be reached this way.
func systemExecutablePath(name: string)->String
{
    let fontsDir = Env.realSpecialDirectory(Env.SpecialDirectory.Font)
    Swag.assert(fontsDir.length != 0)

    let windowsDir = Path.directoryName(fontsDir.toString())
    Swag.assert(windowsDir != null)

    let systemDir = Path.combine(windowsDir, "System32")
    return Path.combine(systemDir.toString(), name)
}

#test
{
    // A path containing a space has to survive the command line, so the shell is started from
    // a copy of itself placed under one.
    let sourceExe = systemExecutablePath("cmd.exe")
    Swag.assert(File.exists(sourceExe.toString()))

    var targetExe = CoreTests.makeFilesystemTestPath("process_copy")
    targetExe += " with spaces.exe"

    defer
    {
        if File.exists(targetExe.toString()) do
            discard catch File.delete(targetExe.toString())
    }

    discard expect File.duplicate(targetExe.toString(), sourceExe.toString())
    Swag.assert(File.exists(targetExe.toString()))

    let process = expect Env.runProcess(targetExe.toString(), "/c exit 7")
    Swag.assert(process.exitCode() == 7)
    Swag.assert(!process.isRunning())
}

#test
{
    let shell = systemExecutablePath("cmd.exe")

    let process = expect Env.runProcess(shell.toString(), "/c echo to-standard-output& echo to-standard-error 1>&2")
    Swag.assert(process.exitCode() == 0)

    let output = String.from(process.standardOutput())
    let errors = String.from(process.standardError())
    Swag.assert(output.contains("to-standard-output"))
    Swag.assert(errors.contains("to-standard-error"))
    Swag.assert(!output.contains("to-standard-error"))
}

#test
{
    let shell     = systemExecutablePath("cmd.exe")
    let directory = Env.getSpecialDirectory(.Temp)

    var info    = Env.StartInfo{fileName: shell.toString(), arguments: "/c cd", workingDirectory: directory.toString(), standardOutput: .Pipe}
    let process = expect Env.runProcess(info)
    Swag.assert(process.exitCode() == 0)

    // The shell reports the directory it actually started in, spelled the native way and
    // without the separator a well-known directory can end on.
    var reported = String.from(process.standardOutput())
    reported.trim()
    reported.replace("\\", "/")

    var expected = String.from(directory.toString())
    if expected.endsWith("/") do
        expected.removeBack()

    Swag.assert(Utf8.compare(reported.toSlice(), expected.toSlice(), .Latin1NoCase) == 0)
}

#test
{
    let shell = systemExecutablePath("cmd.exe")

    var environment = Env.currentEnvironment()
    Swag.assert(environment.count() != 0)

    environment.set("SWAG_PROCESS_TEST", "captured-value")
    Swag.assert(environment.value("SWAG_PROCESS_TEST") == "captured-value")

    // Windows matches variable names without regard to case, so a lookup finds it either way.
    Swag.assert(environment.value("swag_process_test") == "captured-value")

    var info          = Env.StartInfo{fileName: shell.toString(), arguments: "/c echo %SWAG_PROCESS_TEST%", environment: &environment, standardOutput: .Pipe}
    let granted       = expect Env.runProcess(info)
    let grantedOutput = String.from(granted.standardOutput())
    Swag.assert(grantedOutput.contains("captured-value"))

    // An unset variable is left as written by the shell, which is how the child reports that
    // the override really disappeared instead of merely turning empty.
    environment.remove("SWAG_PROCESS_TEST")
    Swag.assert(environment.value("SWAG_PROCESS_TEST") == null)

    let revoked       = expect Env.runProcess(info)
    let revokedOutput = String.from(revoked.standardOutput())
    Swag.assert(revokedOutput.contains("%SWAG_PROCESS_TEST%"))
}

#test
{
    let sorter = systemExecutablePath("sort.exe")

    var info    = Env.StartInfo{fileName: sorter.toString(), standardInput: .Pipe, standardOutput: .Pipe}
    var process = expect Env.startProcess(info)

    expect process.writeStandardInput("second\r\nfirst\r\n")
    process.closeStandardInput()

    let exitCode = expect process.waitForExit()
    Swag.assert(exitCode == 0)

    var sorted = String.from(process.standardOutput())
    sorted.trim()
    Swag.assert(sorted.startsWith("first"))
}

#test
{
    // A program that keeps running until it is stopped, so the kill has something to reach.
    let waiter = systemExecutablePath("ping.exe")

    var info    = Env.StartInfo{fileName: waiter.toString(), arguments: "-n 20 127.0.0.1", standardOutput: .Discard}
    var process = expect Env.startProcess(info)
    Swag.assert(process.isRunning())
    Swag.assert(process.processId != 0)

    let exitedEarly = expect process.tryWaitForExit(50'ms)
    Swag.assert(!exitedEarly)

    expect process.kill(9)
    let exitCode = expect process.waitForExit()
    Swag.assert(exitCode == 9)
    Swag.assert(!process.isRunning())

    // A discarded stream is not captured, so nothing reaches this side.
    Swag.assert((process.standardOutput()).count == 0)
}

#test
{
    // A value the grammar can pass through untouched keeps its exact spelling.
    Swag.assert(Env.quoteArgument("plain").toString() == "plain")
    Swag.assert(Env.quoteArgument("").toString() == "\"\"")
    Swag.assert(Env.quoteArgument("with space").toString() == "\"with space\"")
    Swag.assert(Env.quoteArgument("say \"hi\"").toString() == "\"say \\\"hi\\\"\"")
    Swag.assert(Env.quoteArgument("c:\\dir\\").toString() == "c:\\dir\\")

    // A trailing backslash inside a wrapped value has to be doubled, or it would escape the
    // closing quote and swallow the argument that follows.
    Swag.assert(Env.quoteArgument("c:\\my dir\\").toString() == "\"c:\\my dir\\\\\"")
    Swag.assert(Env.joinArguments(["a", "b c", ""]).toString() == "a \"b c\" \"\"")
}

#test
{
    // A variable the process really has, read one at a time.
    let path = Env.variable("Path")
    Swag.assert(!path.isEmpty())
    Swag.assert(Env.variable("SWAG_NO_SUCH_VARIABLE_HERE").isEmpty())
}

#test
{
    // A measured run accounts the process and everything it starts. The shell is given work that
    // takes a little time and a little memory, so none of the figures can be legitimately zero.
    let shell = systemExecutablePath("cmd.exe")

    var info = Env.StartInfo{
        fileName: shell.toString(),
        arguments: "/c for /L %i in (1,1,200000) do @set _x=%i",
        standardOutput: .Discard,
        standardError: .Discard,
        measureResources: true}

    let process = expect Env.runProcess(info)
    Swag.assert(process.exitCode() == 0)

    let used = process.resources()
    Swag.assert(used.processCount >= 1)
    Swag.assert(used.peakMemory != 0)
    Swag.assert(used.peakProcessMemory != 0)
    Swag.assert(used.peakMemory >= used.peakProcessMemory)
    Swag.assert(used.userTime.seconds + used.kernelTime.seconds > 0)
}

#test
{
    // A run that was not measured answers zero rather than an accidental figure.
    let shell = systemExecutablePath("cmd.exe")

    let process = expect Env.runProcess(shell.toString(), "/c exit 0")
    let used    = process.resources()
    Swag.assert(used.peakMemory == 0)
    Swag.assert(used.processCount == 0)
}

#test
{
    // Pinning a child to one processor must not change what it produces.
    let shell = systemExecutablePath("cmd.exe")

    var info    = Env.StartInfo{fileName: shell.toString(), arguments: "/c exit 3", affinityMask: 1}
    let process = expect Env.runProcess(info)
    Swag.assert(process.exitCode() == 3)
}
