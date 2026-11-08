#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

using Swag

func checkDaylightSavingTransition()
{
    Swag.require(Env.variable("TZ") == "America/New_York")

    // The spring clock skips 02:00; the fall clock repeats 01:00 with a different UTC offset.
    Swag.require(Time.DateTime{2024, 3, 10, 6, 59, 59, 123}.toLocal() ==
                 Time.DateTime{2024, 3, 10, 1, 59, 59, 123})
    Swag.require(Time.DateTime{2024, 3, 10, 7, 0, 0, 456}.toLocal() ==
                 Time.DateTime{2024, 3, 10, 3, 0, 0, 456})
    Swag.require(Time.DateTime{2024, 11, 3, 5, 59, 59, 789}.toLocal() ==
                 Time.DateTime{2024, 11, 3, 1, 59, 59, 789})
    Swag.require(Time.DateTime{2024, 11, 3, 6, 0, 0, 12}.toLocal() ==
                 Time.DateTime{2024, 11, 3, 1, 0, 0, 12})
}

#premain
{
    if Env.hasArgument("--swag-dst-peer")
    {
        checkDaylightSavingTransition()
        Env.exit(0)
    }
}

#[Swag.TestTag("integration.timezone")]
#test
{
    Swag.require(not Swag.jit(), "run timezone integration with --no-test-jit")
    var environment = Env.currentEnvironment()
    environment.set("TZ", "America/New_York")
    let arguments = ["--swag-dst-peer"]
    let process = expect Env.runProcess(Env.StartInfo{fileName: Env.executablePath(), arguments: arguments,
                                                     environment: &environment, standardOutput: .Pipe, standardError: .Pipe})
    Swag.require(process.exitCode() == 0, String.from(process.standardError()).toString())
}
