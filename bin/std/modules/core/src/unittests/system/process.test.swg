#global if #command == Swag.CompilerCommand.Test
#global if WINDOWS
#global private

using Swag

func getShellExecutablePath()->String
{
    // This test launches a real system executable, so it has to look outside any sandbox to
    // find it. Data an application owns must never be reached this way.
    let fontsDir = Env.realSpecialDirectory(Env.SpecialDirectory.Font)
    @assert(fontsDir.length != 0)

    let windowsDir = Path.directoryName(fontsDir.toString())
    @assert(windowsDir != null)

    return Path.combine(windowsDir, "System32", "WindowsPowerShell", "v1.0", "powershell.exe")
}

#test
{
    let sourceExe = getShellExecutablePath()
    @assert(File.exists(sourceExe.toString()))

    var targetExe = CoreTests.makeFilesystemTestPath("process_copy")
    targetExe += " with spaces.exe"
    var targetOut = CoreTests.makeFilesystemTestPath("process_output")
    targetOut += ".txt"

    defer
    {
        if File.exists(targetExe.toString()) do
            discard catch File.delete(targetExe.toString())
        if File.exists(targetOut.toString()) do
            discard catch File.delete(targetOut.toString())
    }

    discard expect File.duplicate(targetExe.toString(), sourceExe.toString())
    @assert(File.exists(targetExe.toString()))

    var outArg = targetOut
    outArg.replace("/", "\\")
    let arguments = Format.toString("-NoProfile -Command \"[System.IO.File]::WriteAllText('%','ok')\"", outArg.toString())

    discard expect Env.doSyncProcess(targetExe.toString(), arguments.toString())
    @assert(File.exists(targetOut.toString()))
}
