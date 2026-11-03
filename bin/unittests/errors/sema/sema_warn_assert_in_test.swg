#global private

// A '#test' body states what it verifies with 'Swag.require' or 'Swag.check'. An assertion written
// there is a program invariant, which a safety setting can remove.
#test
{
    var count = 1
    Swag.assert(count == 1)     // swc-expected-warning {{sema_warn_assert_in_test}}
    Swag.require(count == 1)
}

// A function declared in the body keeps its own invariants.
#test
{
    func half(value: s32)->s32
    {
        Swag.assert(value % 2 == 0)
        return value / 2
    }

    Swag.require(half(4) == 2)
}

// A test of the assertion itself says so.
#[Swag.Warning("sema_warn_assert_in_test", .Disable)]
#test
{
    Swag.assert(true)
}
