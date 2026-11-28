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

// This test is about the assertion itself, so its body writes 'Swag.assert' on purpose.
#[Swag.Safety(.Assert, true), Swag.Warning("sema_warn_assert_in_test", .Disable)]
#test
{
    var count = 0
    Swag.assert(assertionCondition(&count), assertionMessage(&count))
    Swag.require(count == 1)
    #[Swag.Safety(.Assert, false)]
    {
        Swag.assert(assertionCondition(&count), assertionMessage(&count))
        Swag.assert(false)
    }

    Swag.require(count == 1)
}
