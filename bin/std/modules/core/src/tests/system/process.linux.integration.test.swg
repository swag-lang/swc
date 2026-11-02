#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

#[Swag.TestTag("integration.process")]
#test
{
    let image = expect Env.Process.currentExecutablePath()
    Swag.assert(Path.isRooted(image.toString()) and File.exists(image.toString()))
    var environment = Env.currentEnvironment()
    let name        = "SWAG_PROCESS_SNAPSHOT_ONLY"
    let original    = Env.variable(name)
    environment.set(name, "local-value")
    Swag.assert(environment.value(name) == "local-value")
    Swag.assert(Env.variable(name) == original)
    environment.set("swag_process_snapshot_only", "different-case")
    Swag.assert(environment.value(name) == "local-value")
    Swag.assert(environment.value("swag_process_snapshot_only") == "different-case")
}

#[Swag.TestTag("integration.process")]
#test
{
    var environment: Env.ProcessEnvironment
    environment.set("SWAG_PROCESS_VALUE", "exact value")
    let arguments = ["-c", "printf '<%s>' \"$@\"; printf '|%s|%s' \"$SWAG_PROCESS_VALUE\" \"$PWD\"; printf error >&2; exit 37", "probe",
                     "", "two words", "quote\"value", "back\\slash", "é"]
    var process = expect Env.runProcess({fileName: "/bin/sh", arguments: arguments, environment: &environment,
                                         workingDirectory: "/", standardInput: .Discard, standardOutput: .Pipe, standardError: .Pipe})
    Swag.assert(process.exitCode() == 37 and not process.isRunning())
    Swag.assert(process.standardOutput() == "<><two words><quote\"value><back\\slash><é>|exact value|/")
    Swag.assert(process.standardError() == "error")
    let pid = process.processId
    process.close()
    process.close()
    Swag.assert(process.processId == pid and process.exitCode() == 37)
    Swag.assert(process.standardError() == "error")
}

#[Swag.TestTag("integration.process")]
#test
{
    // More than pipe capacity in both directions exposes a writer that forgets to drain stdout.
    var process = expect Env.startProcess({fileName: "/bin/cat", standardInput: .Pipe, standardOutput: .Pipe, standardError: .Pipe})
    var data: String
    for 32768 do
        data.append("abcdefgh")
    expect process.writeStandardInput(data.toString())
    process.closeStandardInput()
    process.closeStandardInput()
    Swag.assert(expect process.waitForExit() == 0)
    Swag.assert(process.standardOutput() == data.toString())
    Swag.assert(process.standardError().count == 0)
}

#[Swag.TestTag("integration.process")]
#test
{
    var process = expect Env.startProcess("/bin/sleep", ["30"])
    defer
    {
        discard catch process.kill()
        discard catch process.waitForExit()
    }

    Swag.assert(not expect process.tryWaitForExit(Time.Duration.fromMilliseconds(0)))
    Swag.assert(not expect process.tryWaitForExit(Time.Duration.fromMilliseconds(20)))
    Swag.assert(process.isRunning())
    expect process.kill()
    Swag.assert(expect process.waitForExit() == 137)
    Swag.assert(expect process.tryWaitForExit(Time.Duration.fromMilliseconds(0)))
    expect process.kill()
}

#[Swag.TestTag("integration.process")]
#test
{
    // The exit is observed before writing, so no reader remains and EPIPE is deterministic.
    var process = expect Env.startProcess({fileName: "/bin/true", standardInput: .Pipe})
    discard expect process.waitForExit()
    var outcome: Swag.Error
    catch process.writeStandardInput("closed reader") as outcome
    Swag.assert(outcome.value() is Swag.SystemError)
    Swag.assert((assume cast(const *Swag.SystemError, outcome.value())).errorID == cast(u64, Linux.EPIPE))
}

#[Swag.TestTag("integration.process")]
#test
{
    // close returns with the live child intact; its natural exit must subsequently be reaped.
    var process   = expect Env.startProcess("/bin/sleep", ["1"])
    let pid       = cast(s32, process.processId)
    let directory = Format.toString("/proc/%", pid)
    process.close()
    process.close()
    Swag.assert(Linux.kill(pid, 0) == 0)
    var clock: Time.Stopwatch
    clock.start()
    while Directory.exists(directory.toString()) and clock.elapsedMilliseconds() < 5000 do
        Threading.Thread.sleep(Time.Duration.fromMilliseconds(10))
    Swag.assert(not Directory.exists(directory.toString()), "closed child must not remain a zombie")
}

#[Swag.TestTag("integration.process")]
#test
{
    Swag.assert(not Env.Process.supportsResourceMeasurement())

    func unsupported(info: Env.StartInfo)
    {
        var outcome: Swag.Error
        discard catch Env.startProcess(info) as outcome
        Swag.assert(outcome.value() is Swag.SystemError)
        Swag.assert((assume cast(const *Swag.SystemError, outcome.value())).errorID == cast(u64, Linux.ENOTSUP))
    }

    unsupported({fileName: "/swag-missing-process", nativeArguments: "raw"})
    unsupported({fileName: "/swag-missing-process", affinityMask: 1})
    unsupported({fileName: "/swag-missing-process", measureResources: true})
    var outcome: Swag.Error
    discard catch Env.startProcess({fileName: "/swag-missing-process", standardInput: .Pipe, standardOutput: .Pipe, standardError: .Pipe}) as outcome
    Swag.assert(outcome.value() is Errors.FileNotFoundError)
}

#[Swag.TestTag("integration.process")]
#test
{
    // Both streams exceed pipe capacity; waiting must service each rather than waiting on one EOF.
    let script  = "i=0; while [ $i -lt 2048 ]; do printf '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'; printf 'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210' >&2; i=$((i+1)); done"
    let process = expect Env.runProcess("/bin/sh", ["-c", script])
    Swag.assert(process.exitCode() == 0)
    Swag.assert(process.standardOutput().count == 131072)
    Swag.assert(process.standardError().count == 131072)
}
