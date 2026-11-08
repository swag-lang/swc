#global if #command == Swag.CompilerCommand.Test and #os == Swag.TargetOs.Linux
#global private

func checkNativeEnvironmentMutation()
{
    const Name = "SWAG_LINUX_ENV_MUTATION_TEST"
    const OtherCase = "swag_linux_env_mutation_test"
    Swag.require(Linux.unsetenv(Name.buffer) == 0)
    Swag.require(Linux.unsetenv(OtherCase.buffer) == 0)

    let before = Env.currentEnvironment()
    Swag.require(before.value(Name) == null)

    Swag.require(Linux.setenv(Name.buffer, "first".buffer, 1) == 0)
    Swag.require(Env.variable(Name) == "first")
    let first = Env.currentEnvironment()
    Swag.require(first.value(Name) == "first" and before.value(Name) == null)

    Swag.require(Linux.setenv(Name.buffer, "second".buffer, 1) == 0)
    Swag.require(Linux.setenv(OtherCase.buffer, "lower".buffer, 1) == 0)
    Swag.require(Env.variable(Name) == "second" and Env.variable(OtherCase) == "lower")
    let second = Env.currentEnvironment()
    Swag.require(second.value(Name) == "second" and second.value(OtherCase) == "lower")
    Swag.require(first.value(Name) == "first" and first.value(OtherCase) == null)

    Swag.require(Linux.setenv(Name.buffer, "".buffer, 1) == 0)
    Swag.require(Env.variable(Name) == "")
    let empty = Env.currentEnvironment()
    Swag.require(empty.value(Name) == "" and empty.value(OtherCase) == "lower")

    Swag.require(Linux.unsetenv(Name.buffer) == 0)
    Swag.require(Env.variable(Name) == "")
    let absent = Env.currentEnvironment()
    Swag.require(absent.value(Name) == null and absent.value(OtherCase) == "lower")
    Swag.require(empty.value(Name) == "" and second.value(Name) == "second")
    Swag.require(Linux.unsetenv(OtherCase.buffer) == 0)
}

#premain
{
    if Env.hasArgument("--swag-environment-mutation-peer")
    {
        checkNativeEnvironmentMutation()
        Env.exit(37)
    }
}

#[Swag.TestTag("integration.environment")]
#test
{
    Swag.require(not Swag.jit(), "run native environment mutation with --no-test-jit")
    let process = expect Env.runProcess(Env.StartInfo{fileName: Env.executablePath(),
                                                     arguments: ["--swag-environment-mutation-peer"],
                                                     standardOutput: .Pipe, standardError: .Pipe})
    Swag.require(process.exitCode() == 37, String.from(process.standardError()).toString())
}
