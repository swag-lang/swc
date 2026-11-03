#global private

#[Swag.NoInline]
func assumedOperation(value: s32)->s32 fail
{
    if value < 0 do fail Swag.BaseError{"negative input"}
    return value + 1
}

#[Swag.NoInline]
func assumedPointer(value: *s32)->*s32 fail
{
    if value[] < 0 do fail Swag.BaseError{"negative input"}
    return value
}

#[Swag.Safety(.Assume, false), Swag.NoInline]
func uncheckedAssumedCall(value: s32)->s32 => assume assumedOperation(value)

#[Swag.Safety(.Assume, true), Swag.NoInline]
func guardedAssumedCall(value: s32)->s32 => assume assumedOperation(value)

func assumedVoid(value: *s32) fail { value[] += 1 }

func internallyHandledOperation()->s32 fail
{
    var errorOutcome: Swag.Error
    var result:       #decltype(expect assumedOperation(-1))
    catch { result = try assumedOperation(-1) } as errorOutcome
    let error = errorOutcome.value()
    Swag.assert(result == 0 and error != null)
    return 42
}

#[Swag.Safety(.Assume, false), Swag.NoInline]
func assumedCastAndCall(value: *s32)->*s32 => assume cast(*s32, assumedPointer(value))

#[Swag.Safety(.Assume, false), Swag.NoInline]
func parenthesizedAssumedCast(value: *s32?)->*s32 => assume (cast(*s32, value))

func contextuallyAssumedCast(value: any)->s32 => assume cast(value)

func fallibleBox(value: any)->any fail { return value }

func contextuallyAssumedCall(value: any)->s32 => assume cast(fallibleBox(value))

func assumedBlock(value: *s32)
{
    assume
    {
        defer value[] += 1
        try assumedVoid(value)
    }
}

#test
{
    Swag.require(uncheckedAssumedCall(41) == 42)
    Swag.require(guardedAssumedCall(41) == 42)
    var value: s32 = 12
    let pointer    = assume assumedPointer(&value)
    Swag.require(pointer == &value)
    Swag.require(assumedCastAndCall(&value) == &value)
    Swag.require(parenthesizedAssumedCast(&value) == &value)
    Swag.require(contextuallyAssumedCast(value) == 12)
    Swag.require(contextuallyAssumedCall(value) == 12)
    assume assumedVoid(&value)
    Swag.require(value == 13)
    assumedBlock(&value)
    Swag.require(value == 15)
    #[Swag.Safety(.Assume, false)]
    {
        Swag.require(assume internallyHandledOperation() == 42)
        // A later checked operation still owns its failure.
        var errorOutcome: Swag.Error
        var failed:       #decltype(expect assumedOperation(-1))
        catch { failed = try assumedOperation(-1) } as errorOutcome
        let error = errorOutcome.value()
        Swag.require(failed == 0 and error != null)
    }
}
