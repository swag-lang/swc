#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

#test
{
    const Name = "SWAG_CORE_ENVIRONMENT_MUTATION_TEST"
    expect Env.removeVariable(Name)
    defer discard catch Env.removeVariable(Name)

    Swag.require(Env.currentEnvironment().value(Name) == null)
    expect Env.setVariable(Name, "")
    Swag.require(Env.variable(Name) == "")
    Swag.require(Env.currentEnvironment().value(Name) == "")

    expect Env.setVariable(Name, "updated")
    Swag.require(Env.variable(Name) == "updated")
    expect Env.removeVariable(Name)
    Swag.require(Env.currentEnvironment().value(Name) == null)
    expect Env.removeVariable(Name)
    Swag.require(Env.currentEnvironment().value(Name) == null)

    var rejectedEmptyName = false
    catch Env.setVariable("", "value") { rejectedEmptyName = true }
    Swag.require(rejectedEmptyName)

    var rejectedEqualsName = false
    catch Env.removeVariable("INVALID=NAME") { rejectedEqualsName = true }
    Swag.require(rejectedEqualsName)

    var rejectedZeroName = false
    catch Env.setVariable("INVALID\u0000NAME", "value") { rejectedZeroName = true }
    Swag.require(rejectedZeroName)

    var rejectedZeroValue = false
    catch Env.setVariable(Name, "INVALID\u0000VALUE") { rejectedZeroValue = true }
    Swag.require(rejectedZeroValue)
}
