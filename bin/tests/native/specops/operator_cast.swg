#global fileprivate

struct RuntimeCastBox
{
    value:     s32
    intCalls:  s32
    boolCalls: s32
}

impl RuntimeCastBox
{
    #[Swag.Implicit, Swag.NoInline]
    mtd opCast() -> s32
    {
        .intCalls += 1
        return .value + 1
    }

    #[Swag.NoInline]
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

#[Swag.Strict]
alias OpCastStrictPtr = *s32

struct RuntimePointerCastBox
{
    value: s32
}

impl RuntimePointerCastBox
{
    #[Swag.Implicit, Swag.NoInline]
    mtd const opCast() -> OpCastStrictPtr
    {
        return cast(OpCastStrictPtr) &.value
    }
}

func consumeNullableStrictPtr(value: #null OpCastStrictPtr) -> s32
{
    return dref value
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

#test
{
    var box = RuntimePointerCastBox{value: 99}
    @assert(consumeNullableStrictPtr(box) == 99)
}
