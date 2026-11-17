#global if #command == Swag.CompilerCommand.Test
#global private

using Swag

func rejectsSessionInstanceId(id: string)->bool
{
    var instance: Env.SessionInstance
    var error:    Swag.Error
    discard catch instance.acquire(id) as error
    return error.value() is Errors.BadParameterError
}

// Invalid IDs fail validation before acquiring any system resource.
#test
{
    for id in ["", "../bad", "bad_id", "has space", "caf\u00E9"] do
        Swag.require(rejectsSessionInstanceId(id))

    var longId = String.from("")
    for 129 do
        longId += "a"
    Swag.require(rejectsSessionInstanceId(longId.toString()))
}
