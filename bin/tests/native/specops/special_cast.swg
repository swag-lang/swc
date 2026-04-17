#global fileprivate

struct RuntimeCastBox
{
    value:     s32
    intCalls:  s32
    boolCalls: s32
}

impl RuntimeCastBox
{
    #[Swag.Implicit, Swag.Overload, Swag.NoInline]
    mtd opCast() -> s32
    {
        .intCalls += 1
        return .value + 1
    }

    #[Swag.Overload, Swag.NoInline]
    mtd const opCast() -> bool
    {
        .boolCalls += 1
        return .value != 0
    }
}

func consumeInt(value: s32) -> s32
{
    return value
}

#test
{
    var value = RuntimeCastBox{value: 41}

    let explicitInt = cast(s32) value
    let explicitBool = cast(bool) value
    let implicitInt = consumeInt(value)
    let initialized: s32 = value

    @assert(explicitInt == 42)
    @assert(explicitBool)
    @assert(implicitInt == 42)
    @assert(initialized == 42)
    @assert(value.intCalls == 3)
    @assert(value.boolCalls == 1)
}
