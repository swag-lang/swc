#global if #command == Swag.CompilerCommand.Test
#global private

// Presence is exclusive across independent owners, reusable, and released with its scope.
#test
{
    let id = Format.toString("swag-test-%", Guid64.random())
    var second: Env.SessionInstance
    scope
    {
        var first: Env.SessionInstance
        Swag.require(expect first.acquire(id))
        Swag.require(not expect second.acquire(id))
        first.close()
        first.close()
        Swag.require(expect second.acquire(id))
        second.close()
        Swag.require(expect first.acquire(id))
    }

    Swag.require(expect second.acquire(id))
    var invalid: Env.SessionInstance
    var error:   Swag.Error
    discard catch invalid.acquire("../bad") as error
    Swag.require(error.value() is Errors.BadParameterError)
}

// Startup registration is an explicit system mutation and must not escape a sandbox.
#test
{
    if not Env.isSandboxed() do
        return
    let before = Env.deniedSystemMutations()
    Swag.require(not Env.setSessionStartup("swag-test", "Test", true, ["--hide"]))
    Swag.require(Env.deniedSystemMutations() == before + 1)
}
