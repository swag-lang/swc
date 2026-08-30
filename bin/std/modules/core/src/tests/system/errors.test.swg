#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

// An error family two levels deep: the base state still sits at offset zero.
struct DeepError
{
    using base: Errors.BadParameterError     // Embedded base state.
}

func failWithMessage() fail
{
    fail Errors.BadParameterError{"the message text"}
}

func failWithoutMessage() fail
{
    fail Errors.BadParameterError{}
}

func failWithoutBase() fail
{
    fail Errors.InvalidVersion{wantedVersion: 1, foundVersion: 2}
}

func failDeep() fail
{
    fail DeepError{{"the deep text"}}
}

#test
{
    catch failWithMessage() as err
    Swag.assert(err != null)
    Swag.assert(Errors.message(err) == "the message text")
}

#test
{
    catch failWithoutMessage() as err
    Swag.assert(Errors.message(err) == "BadParameterError")
}

#test
{
    catch failWithoutBase() as err
    Swag.assert(Errors.message(err) == "InvalidVersion")
}

#test
{
    catch failDeep() as err
    Swag.assert(Errors.message(err) == "the deep text")
}

#test
{
    Swag.assert(Errors.message(null) == "")
}
