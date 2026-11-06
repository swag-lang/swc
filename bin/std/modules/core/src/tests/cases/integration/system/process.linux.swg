#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

#[Swag.TestTag("integration.process")]
#test
{
    let image = expect Env.Process.currentExecutablePath()
    Swag.require(Path.isRooted(image.toString()) and File.exists(image.toString()))
    var environment = Env.currentEnvironment()
    let name        = "SWAG_PROCESS_SNAPSHOT_ONLY"
    let original    = Env.variable(name)
    environment.set(name, "local-value")
    Swag.require(environment.value(name) == "local-value")
    Swag.require(Env.variable(name) == original)
    environment.set("swag_process_snapshot_only", "different-case")
    Swag.require(environment.value(name) == "local-value")
    Swag.require(environment.value("swag_process_snapshot_only") == "different-case")
}

#[Swag.TestTag("integration.process")]
#test
{
    var environment: Env.ProcessEnvironment
    environment.set("SWAG_PROCESS_VALUE", "exact value")
    let arguments = ["-c", "printf '<%s>' \"$@\"; printf '|%s|%s' \"$SWAG_PROCESS_VALUE\" \"$PWD\"; printf error >&2; exit 37", "probe",
                     "", "two words", "quote\"value", "back\\slash", "é"]
    var process = expect Env.runProcess(Env.StartInfo{fileName: "/bin/sh", arguments: arguments, environment: &environment,
                                                      workingDirectory: "/", standardInput: .Discard, standardOutput: .Pipe, standardError: .Pipe})
    Swag.require(process.exitCode() == 37 and not process.isRunning())
    Swag.require(process.standardOutput() == "<><two words><quote\"value><back\\slash><é>|exact value|/")
    Swag.require(process.standardError() == "error")
    let pid = process.processId
    process.close()
    process.close()
    Swag.require(process.processId == pid and process.exitCode() == 37)
    Swag.require(process.standardError() == "error")
}

#[Swag.TestTag("integration.process")]
#test
{
    // More than pipe capacity in both directions exposes a writer that forgets to drain stdout.
    var process = expect Env.startProcess(Env.StartInfo{fileName: "/bin/cat", standardInput: .Pipe, standardOutput: .Pipe, standardError: .Pipe})
    var data: String
    for 32768 do
        data.append("abcdefgh")
    expect process.writeStandardInput(data.toString())
    process.closeStandardInput()
    process.closeStandardInput()
    Swag.require(expect process.waitForExit() == 0)
    Swag.require(process.standardOutput() == data.toString())
    Swag.require(process.standardError().count == 0)
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

    Swag.require(not expect process.tryWaitForExit(Time.Duration.fromMilliseconds(0)))
    Swag.require(not expect process.tryWaitForExit(Time.Duration.fromMilliseconds(20)))
    Swag.require(process.isRunning())
    expect process.kill()
    Swag.require(expect process.waitForExit() == 137)
    Swag.require(expect process.tryWaitForExit(Time.Duration.fromMilliseconds(0)))
    expect process.kill()
}

#[Swag.TestTag("integration.process")]
#test
{
    // The exit is observed before writing, so no reader remains and EPIPE is deterministic.
    var process = expect Env.startProcess(Env.StartInfo{fileName: "/bin/true", standardInput: .Pipe})
    discard expect process.waitForExit()
    var outcome: Swag.Error
    catch process.writeStandardInput("closed reader") as outcome
    Swag.require(outcome.value() is Swag.SystemError)
    Swag.require((assume cast(const *Swag.SystemError, outcome.value())).errorID == cast(u64, Linux.EPIPE))
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
    Swag.require(Linux.kill(pid, 0) == 0)
    var clock: Time.Stopwatch
    clock.start()
    while Directory.exists(directory.toString()) and clock.elapsedMilliseconds() < 5000 do
        Threading.Thread.sleep(Time.Duration.fromMilliseconds(10))
    Swag.require(not Directory.exists(directory.toString()), "closed child must not remain a zombie")
}

#[Swag.TestTag("integration.process")]
#test
{
    Swag.require(not Env.Process.supportsResourceMeasurement())

    func unsupported(info: Env.StartInfo)
    {
        var outcome: Swag.Error
        discard catch Env.startProcess(info) as outcome
        Swag.require(outcome.value() is Swag.SystemError)
        Swag.require((assume cast(const *Swag.SystemError, outcome.value())).errorID == cast(u64, Linux.ENOTSUP))
    }

    unsupported({fileName: "/swag-missing-process", nativeArguments: "raw"})
    unsupported({fileName: "/swag-missing-process", affinityMask: 1})
    unsupported({fileName: "/swag-missing-process", measureResources: true})
    var outcome: Swag.Error
    discard catch Env.startProcess(Env.StartInfo{fileName: "/swag-missing-process", standardInput: .Pipe, standardOutput: .Pipe, standardError: .Pipe}) as outcome
    Swag.require(outcome.value() is Errors.FileNotFoundError)
    Swag.require((assume cast(const *Errors.FileNotFoundError, outcome.value())).nativeErrorID == cast(u64, Linux.ENOENT))
}

#[Swag.TestTag("integration.process")]
#test
{
    // Both streams exceed pipe capacity; waiting must service each rather than waiting on one EOF.
    let script  = "i=0; while [ $i -lt 2048 ]; do printf '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'; printf 'fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210' >&2; i=$((i+1)); done"
    let process = expect Env.runProcess("/bin/sh", ["-c", script])
    Swag.require(process.exitCode() == 0)
    Swag.require(process.standardOutput().count == 131072)
    Swag.require(process.standardError().count == 131072)
}

#[Swag.TestTag("integration.process")]
#test
{
    // A child that never closes either output pipe cannot extend a finite wait indefinitely.
    const Script = "while :; do printf '0123456789abcdef'; printf 'fedcba9876543210' >&2; done"
    var process = expect Env.startProcess(Env.StartInfo{fileName: "/bin/sh", arguments: ["-c", Script],
                                                    standardOutput: .Pipe, standardError: .Pipe})
    defer
    {
        discard catch process.kill()
        discard catch process.waitForExit()
    }

    var clock: Time.Stopwatch
    clock.start()
    Swag.require(not expect process.tryWaitForExit(Time.Duration.fromMilliseconds(30)))
    Swag.require(clock.elapsedMilliseconds() < 1000)
    expect process.kill()
    Swag.require(expect process.waitForExit() == 137)
}

#[Swag.TestTag("integration.process")]
#test
{
    // A grandchild may retain the redirected pipes after the direct child has exited.
    const Script = "sleep 3 & printf ready"
    var process = expect Env.startProcess(Env.StartInfo{fileName: "/bin/sh", arguments: ["-c", Script],
                                                    standardOutput: .Pipe, standardError: .Pipe})
    var clock: Time.Stopwatch
    clock.start()
    let status  = expect process.waitForExit()
    let elapsed = clock.elapsedMilliseconds()
    Swag.require(status == 0 and elapsed < 2000 and process.standardOutput() == "ready")
}
