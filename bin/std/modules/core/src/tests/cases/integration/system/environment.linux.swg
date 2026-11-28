#global if #command == Swag.CompilerCommand.Test
#global if #os == Swag.TargetOs.Linux
#global private

#[Swag.TestTag("integration.system")]
#test
{
    Swag.require(Env.LineEnding == "\n")
    Swag.require(Env.arguments().count != 0)
    Swag.require(Env.hasArgument("swag.test"))
    Swag.require(Env.executablePath().count != 0)
    Swag.require(Env.variable("") == "")
    Swag.require(Env.variable("invalid=name") == "")
    Swag.require(Env.variable("PATH\0ignored") == "")

    var environment: Env.ProcessEnvironment
    environment.set("Path", "one")
    environment.set("PATH", "two")
    Swag.require(environment.count() == 2)
    Swag.require(environment.value("Path") == "one")
    Swag.require(environment.value("PATH") == "two")
    environment.remove("Path")
    Swag.require(environment.value("Path") == null and environment.value("PATH") == "two")
}

#[Swag.TestTag("integration.system")]
#test
{
    let before = Time.monotonicTicks()
    Threading.Thread.sleep(Time.Duration.fromMilliseconds(2))
    let after = Time.monotonicTicks()
    Swag.require(after >= before and after - before >= 2_000_000)
    Threading.Thread.yield()
    Threading.Thread.sleep(Time.Duration.fromMilliseconds(0))
}
