#global if #command == Swag.CompilerCommand.Test
#global private

func expectInvalidProcessArguments(info: Env.StartInfo)
{
    var outcome: Swag.Error
    discard catch Env.startProcess(info) as outcome

    // The deliberately missing executable would produce a native lookup failure if the
    // invalid input reached the host. Validation must fail before any launch is attempted.
    Swag.require(outcome.value() is Errors.BadParameterError)
}

#[Swag.TestTag("process.arguments")]
#test
{
    let arguments = ["ordinary", "embedded\0zero"]
    expectInvalidProcessArguments({fileName: "/swag-missing-process", arguments: arguments})
    expectInvalidProcessArguments({fileName: "/swag-missing-process", nativeArguments: "embedded\0zero"})
    expectInvalidProcessArguments({fileName: "embedded\0zero"})
}

#[Swag.TestTag("process.arguments")]
#test
{
    let arguments = ["one"]
    expectInvalidProcessArguments({fileName: "/swag-missing-process", arguments: arguments, nativeArguments: "two"})
    expectInvalidProcessArguments({fileName: ""})
    expectInvalidProcessArguments({fileName: "/swag-missing-process", workingDirectory: ""})
    expectInvalidProcessArguments({fileName: "/swag-missing-process", workingDirectory: "embedded\0zero"})
}

#[Swag.TestTag("process.arguments")]
#test
{
    var environment: Env.ProcessEnvironment
    environment.set("BAD=NAME", "value")
    expectInvalidProcessArguments({fileName: "/swag-missing-process", environment: &environment})
    environment.clear()
    environment.set("GOOD_NAME", "embedded\0zero")
    expectInvalidProcessArguments({fileName: "/swag-missing-process", environment: &environment})
}
