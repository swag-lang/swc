#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

func openDescriptorCount()->u32
{
    let directory = Linux.opendir("/proc/self/fd".buffer)
    Swag.require(directory != null)
    defer discard Linux.closedir(unwrap directory)

    var count = 0'u32
    while Linux.readdir(directory) do
        count += 1
    return count
}

func checkProcessDescriptorLifetime()
{
    var warmup = expect Env.runProcess("/bin/true")
    warmup.close()
    let before = openDescriptorCount()

    for 64
    {
        var process = expect Env.runProcess(Env.StartInfo{fileName: "/bin/true", standardInput: .Pipe,
                                                       standardOutput: .Pipe, standardError: .Pipe})
        Swag.require(process.exitCode() == 0)
        process.close()

        var outcome: Swag.Error
        discard catch Env.startProcess(Env.StartInfo{fileName: "/swag-missing-process", standardInput: .Pipe,
                                                    standardOutput: .Pipe, standardError: .Pipe}) as outcome
        Swag.require(outcome.value() is Errors.FileNotFoundError)
    }

    Swag.require(openDescriptorCount() == before)
}

#premain
{
    if Env.hasArgument("--swag-process-descriptor-peer")
    {
        checkProcessDescriptorLifetime()
        Env.exit(37)
    }
}

#[Swag.TestTag("stress")]
#test
{
    Swag.require(not Swag.jit(), "run process descriptor stress with --no-test-jit")
    let process = expect Env.runProcess(Env.StartInfo{fileName: Env.executablePath(),
                                                     arguments: ["--swag-process-descriptor-peer"],
                                                     standardOutput: .Pipe, standardError: .Pipe})
    Swag.require(process.exitCode() == 37, String.from(process.standardError()).toString())
}
