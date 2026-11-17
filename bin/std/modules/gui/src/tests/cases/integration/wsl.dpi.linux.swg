#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Core, Linux

#[Swag.TestTag("integration.process")]
#test
{
    Swag.require(not Swag.jit(), "run WSL DPI timeout integration with --no-test-jit")
    var temporary = Path.combine(Env.getSpecialDirectory(.Temp), "swag-wsl-dpi-XXXXXX")
    Swag.require(Linux.mkdtemp(temporary.storage()) == temporary.buffer)
    defer expect Directory.delete(temporary, recurse: true)

    let hadPath         = Linux.getenv("PATH".buffer) != null
    let hadInterop      = Linux.getenv("WSL_INTEROP".buffer) != null
    let originalPath    = Env.variable("PATH")
    let originalInterop = Env.variable("WSL_INTEROP")
    defer
    {
        if hadPath do
            discard Linux.setenv("PATH".buffer, originalPath.storage(), 1)
        else do
            discard Linux.unsetenv("PATH".buffer)
        if hadInterop do
            discard Linux.setenv("WSL_INTEROP".buffer, originalInterop.storage(), 1)
        else do
            discard Linux.unsetenv("WSL_INTEROP".buffer)
    }

    let pidFile = Path.combine(temporary, "powershell.pid")
    var python  = expect Env.runProcess("which", ["python3"])
    Swag.require(python.exitCode() == 0)
    var pythonPath = String.from(python.standardOutput())
    pythonPath.trim()

    let fakePowerShell = Path.combine(temporary, "powershell.exe")
    const scriptTemplate = """#!/bin/sh
 echo "$$" > "%"
 exec % -c 'import time; time.sleep(30)'
 """
    let script = Format.toString(scriptTemplate, pidFile.toString(), pythonPath.toString())
    discard expect File.writeAllText(fakePowerShell, script)
    let executable = expect Env.runProcess("/bin/chmod", ["+x", fakePowerShell.toString()])
    Swag.require(executable.exitCode() == 0)
    Swag.require(Linux.setenv("PATH".buffer, temporary.storage(), 1) == 0)
    Swag.require(Linux.setenv("WSL_INTEROP".buffer, temporary.storage(), 1) == 0)

    let start   = Time.monotonicMilliseconds()
    let scale   = LinuxDesktop.wslDpiScale()
    let elapsed = Time.monotonicMilliseconds() - start
    Swag.require(scale == 0, "timed-out WSL DPI probe must use the fallback scale")
    Swag.require(elapsed >= 1000, Format.toString("PowerShell probe returned without waiting: %", elapsed))
    Swag.require(elapsed < 8000, Format.toString("WSL DPI probe exceeded 8 seconds: %", elapsed))

    var pidText = expect File.readAllText(pidFile)
    pidText.trim()
    let pid      = expect StrConv.toS32(pidText.toString())
    let deadline = Time.monotonicMilliseconds() + 2000
    while Linux.kill(pid, 0) == 0 and Time.monotonicMilliseconds() < deadline do
        Threading.Thread.sleep(Time.Duration.fromMilliseconds(10))
    Swag.require(Linux.kill(pid, 0) != 0, "PowerShell child survived the DPI timeout")
}
