#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

func closeAfterProcessShutdown()
{
    var process = expect Env.startProcess("/bin/sleep", ["1"])
    let pid = cast(s32, process.processId)

    // Simulate a global owner whose destructor runs after Core has stopped its reaper.
    Env.shutdownProcessesNative()
    process.close()

    var status: s32
    Swag.require(Linux.waitpid(pid, &status, Linux.WNOHANG) < 0 and Linux.errno() == Linux.ECHILD)
}

#premain
{
    if Env.hasArgument("--swag-process-late-peer")
    {
        closeAfterProcessShutdown()
        Env.exit(37)
    }
}

#[Swag.TestTag("integration.process")]
#test
{
    Swag.require(not Swag.jit(), "run late process close with --no-test-jit")
    let process = expect Env.runProcess(Env.StartInfo{fileName: Env.executablePath(),
                                                     arguments: ["--swag-process-late-peer"],
                                                     standardOutput: .Pipe, standardError: .Pipe})
    Swag.require(process.exitCode() == 37, String.from(process.standardError()).toString())
}
