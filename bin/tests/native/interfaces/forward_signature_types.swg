#global fileprivate

interface IForwardSignature
{
    mtd score(flags: ForwardFlags, cxt: ForwardContext)->s32;
}

#[Swag.EnumFlags]
enum ForwardFlags
{
    Zero
    Bonus
}

struct ForwardContext
{
    value: s32
}

struct ForwardReceiver
{
    base: s32
}

func(T) has(flags, value: T)->bool
{
    return flags & value != 0
}

impl IForwardSignature for ForwardReceiver
{
    mtd impl score(flags: ForwardFlags, cxt: ForwardContext)->s32
    {
        if flags.has(.Bonus) do
            return .base + cxt.value + 5
        return .base + cxt.value
    }
}

#test
{
    let receiver = ForwardReceiver{base: 10}
    let itf: IForwardSignature = receiver
    @assert(itf.score(.Bonus, {value: 7}) == 22)
}
