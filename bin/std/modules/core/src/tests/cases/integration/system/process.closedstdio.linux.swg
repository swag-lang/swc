#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

func closedStandardDescriptorsPeer()
{
    for descriptor in 3 do
        discard Linux.close(cast(s32, descriptor))

    let arguments = ["-c", "read value; printf 'out:%s' \"$value\"; printf 'err:%s' \"$value\" >&2"]
    var process = expect Env.startProcess(Env.StartInfo{fileName: "/bin/sh", arguments: arguments,
                                                    standardInput: .Pipe, standardOutput: .Pipe, standardError: .Pipe})
    expect process.writeStandardInput("hello\n")
    process.closeStandardInput()
    Swag.require(expect process.waitForExit() == 0)
    Swag.require(process.standardOutput() == "out:hello")
    Swag.require(process.standardError() == "err:hello")
}

#premain
{
    if Env.hasArgument("--swag-closed-stdio-peer")
    {
        closedStandardDescriptorsPeer()
        Env.exit(37)
    }
}

#[Swag.TestTag("integration.process")]
#test
{
    Swag.require(not Swag.jit(), "run closed-standard-descriptor integration with --no-test-jit")
    let arguments = ["--swag-closed-stdio-peer"]
    let process = expect Env.runProcess(Env.StartInfo{fileName: Env.executablePath(), arguments: arguments,
                                                     standardOutput: .Pipe, standardError: .Pipe})
    Swag.require(process.exitCode() == 37, String.from(process.standardError()).toString())
    Swag.require(process.standardOutput().count == 0 and process.standardError().count == 0)
}
