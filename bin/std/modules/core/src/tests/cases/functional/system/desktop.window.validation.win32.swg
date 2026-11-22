#global if #command == Swag.CompilerCommand.Test
#global if WINDOWS
#global private

using Swag

#test
{
    var failure: Swag.Error
    discard catch Env.createWindow({identifier: "bad\0id", title: "valid", width: 80, height: 60}) as failure
    Swag.require(failure.value() is Errors.BadParameterError)

    discard catch Env.createWindow({identifier: "valid", title: "bad\0title", width: 80, height: 60}) as failure
    Swag.require(failure.value() is Errors.BadParameterError)
}
