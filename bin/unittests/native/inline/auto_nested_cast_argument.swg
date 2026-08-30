#global private

enum AutoInlineArgumentKind
{
    First
    Second
}

alias AutoInlineCallback = func||(u32)->u32

func autoInlineValue(value: u8)->u8
{
    return value + 1
}

#[Swag.Inline]
func storeWidenedAutoInlineValue(value: u64, result: *u64)
{
    result[] = value
}

struct AutoInlineReceiver
{
    value: u8
}

impl AutoInlineReceiver
{
    mtd const readValue()->u8
    {
        return .value
    }

    mtd storeNextValue(result: *u64)
    {
        storeWidenedAutoInlineValue(.readValue() + 1, result)
    }
}

#[Swag.Safety(.Overflow, false)]
func autoInlineInferredParameter(kind = AutoInlineArgumentKind.First)->u32
{
    return cast(u32) kind
}

#[Swag.Inline]
func invokeMaterializedAutoInlineClosure(callback: AutoInlineCallback)->u32
{
    return callback(41)
}

#test
{
    var widened: u64
    storeWidenedAutoInlineValue(autoInlineValue(41), &widened)
    Swag.assert(widened == 42)

    let kind = AutoInlineArgumentKind.Second
    Swag.assert(autoInlineInferredParameter(kind) == 1)

    let offset: u32 = 1
    Swag.assert(invokeMaterializedAutoInlineClosure(func|offset|(value) => value + offset) == 42)

    var receiver = AutoInlineReceiver{41}
    receiver.storeNextValue(&widened)
    Swag.assert(widened == 42)
}
