#global if #command == Swag.CompilerCommand.Test

private func assertionCondition(count: *s32)->bool
{
    count[] += 1
    return true
}

private func assertionMessage(count: *s32)->string
{
    count[] += 10
    return "assertion message"
}

#[Swag.Safety(.Assert, true)]
#test
{
    var count = 0
    Swag.assert(assertionCondition(&count), assertionMessage(&count))
    Swag.assert(count == 1)
    #[Swag.Safety(.Assert, false)]
    {
        Swag.assert(assertionCondition(&count), assertionMessage(&count))
        Swag.assert(false)
    }

    Swag.assert(count == 1)
}
