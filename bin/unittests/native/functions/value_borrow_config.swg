#global private
#global #[Swag.Safety(.ValueBorrow, true)]

// Explicit safety remains available with release optimization and its default guards disabled.
struct Value { first, second, third: u64 }
#[Swag.NoInline]
func write(value: Value, target: *Value)->u64
{
    target.first = 0
    return value.first
}
#test
{
    #assert(#safety(Swag.SafetyWhat.ValueBorrow))
    var value: Value = {first: 11}
    let panic = Swag.catchPanic(func|&value|() { discard write(value, &value) })
    Swag.assert(panic.raised and value.first == 11)
    let observed = write(#copy value, &value)
    Swag.assert(observed == 11 and value.first == 0)
}

#[Swag.Safety(.ValueBorrow, false), Swag.NoInline]
func localCheck(target: *Value)
{
    #assert(not #safety(Swag.SafetyWhat.ValueBorrow))
    #[Swag.Safety(.ValueBorrow, true)]
    target.first = 0
}
#[Swag.NoInline]
func readWithLocalCheck(value: Value, target: *Value)->u64
{
    localCheck(target)
    return value.first
}
#test
{
    var value: Value = {first: 13}
    let panic = Swag.catchPanic(func|&value|() { discard readWithLocalCheck(value, &value) })
    Swag.assert(panic.raised and value.first == 13)
}

