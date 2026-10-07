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
    let result = catch assumedOperation(-1) as error
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
    Swag.assert(uncheckedAssumedCall(41) == 42)
    Swag.assert(guardedAssumedCall(41) == 42)
    var value: s32 = 12
    let pointer    = assume assumedPointer(&value)
    Swag.assert(pointer == &value)
    Swag.assert(assumedCastAndCall(&value) == &value)
    Swag.assert(parenthesizedAssumedCast(&value) == &value)
    Swag.assert(contextuallyAssumedCast(value) == 12)
    Swag.assert(contextuallyAssumedCall(value) == 12)
    assume assumedVoid(&value)
    Swag.assert(value == 13)
    assumedBlock(&value)
    Swag.assert(value == 15)
    #[Swag.Safety(.Assume, false)]
    {
        Swag.assert(assume internallyHandledOperation() == 42)
        // A later checked operation still owns its failure.
        let failed = catch assumedOperation(-1) as error
        Swag.assert(failed == 0 and error != null)
    }
}
