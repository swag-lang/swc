#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// ProcessEnvironment snapshots replace, remove, and clear bindings without leaking state.
#test
{
    var environment: Env.ProcessEnvironment
    Swag.require(environment.count() == 0)
    Swag.require(environment.value("SWAG_TEST_VALUE") == null)

    environment.set("SWAG_TEST_VALUE", "first")
    Swag.require(environment.count() == 1)
    Swag.require(environment.value("SWAG_TEST_VALUE") == "first")

    environment.set("SWAG_TEST_VALUE", "second")
    Swag.require(environment.count() == 1)
    Swag.require(environment.value("SWAG_TEST_VALUE") == "second")

    #static if WINDOWS
    {
        Swag.require(environment.value("swag_test_value") == "second")
        environment.set("swag_test_value", "third")
        Swag.require(environment.count() == 1)
        Swag.require(environment.value("SWAG_TEST_VALUE") == "third")
    }
    else
    {
        Swag.require(environment.value("swag_test_value") == null)
    }

    environment.remove("missing")
    Swag.require(environment.count() == 1)
    environment.remove("SWAG_TEST_VALUE")
    Swag.require(environment.count() == 0)
    Swag.require(environment.value("SWAG_TEST_VALUE") == null)

    environment.set("first", "1")
    environment.set("second", "2")
    environment.clear()
    Swag.require(environment.count() == 0)
    Swag.require(environment.value("first") == null)
}
