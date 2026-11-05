#global private

struct SwitchDynamicValue
{
    value: s32 = 17
}

struct SwitchDynamicOther {}

func readDynamicCase(value: const any)->s32
{
    switch value
    {
    case SwitchDynamicOther:
        return -1
    case SwitchDynamicValue as item where item.value < 0:
        return -2
    case SwitchDynamicValue as item:
        return item.value
    case s32 as number:
        return number[]
    default:
        return 0
    }
}

#test
{
    var value: SwitchDynamicValue
    Swag.require(readDynamicCase(&value) == 17)
    Swag.require(readDynamicCase(42's32) == 42)
    Swag.require(readDynamicCase(false) == 0)
}

func inspectCaseCalls(value: const any, calls: *s32)->const *s32?
{
    calls[] += 1
    return (catch cast(const *s32?, value))
}

func readCompleteDynamicCase(value: const any)->s32
{
    switch #complete value
    {
    case s64 as number where true:
        return cast(s32, number[])
    case s32 as number where true:
        return number[]
    }
}

#test
{
    Swag.require(readCompleteDynamicCase(17's32) == 17)
    Swag.require(readCompleteDynamicCase(42's64) == 42)
}

#test
{
    var calls      = 0
    var result     = 0
    let value: const any = 42's32
    switch
    {
    case let number = inspectCaseCalls(false, &calls) where number[] == 0:
        result = -1
    case let number = inspectCaseCalls(value, &calls) where number[] == 42:
        result = number[]
    case let number = inspectCaseCalls(value, &calls):
        discard number
        result = -2
    }
    Swag.require(calls == 2)
    Swag.require(result == 42)
}

#test
{
    var result     = 0
    let value: const any = 42's32
    switch value
    {
    default:
        result = 1
        fallthrough
    case s64:
        result = -1
    case s32 as number:
        result += number[]
    }
    Swag.require(result == 43)
}
