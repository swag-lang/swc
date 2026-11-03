#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

#[Swag.TestTag("integration.system")]
#test
{
    Swag.assert(Env.LineEnding == "\n")
    Swag.assert(Env.arguments().count != 0)
    Swag.assert(Env.hasArgument("swag.test"))
    Swag.assert(Env.executablePath().count != 0)
    Swag.assert(Env.variable("") == "")
    Swag.assert(Env.variable("invalid=name") == "")
    Swag.assert(Env.variable("PATH\0ignored") == "")

    var environment: Env.ProcessEnvironment
    environment.set("Path", "one")
    environment.set("PATH", "two")
    Swag.assert(environment.count() == 2)
    Swag.assert(environment.value("Path") == "one")
    Swag.assert(environment.value("PATH") == "two")
    environment.remove("Path")
    Swag.assert(environment.value("Path") == null and environment.value("PATH") == "two")
}

#[Swag.TestTag("integration.system")]
#test
{
    let before = Time.monotonicTicks()
    Threading.Thread.sleep(Time.Duration.fromMilliseconds(2))
    let after = Time.monotonicTicks()
    Swag.assert(after >= before and after - before >= 2_000_000)
    Threading.Thread.yield()
    Threading.Thread.sleep(Time.Duration.fromMilliseconds(0))
}
