#global private

func incrementForInline(value: s32)->s32 => value + 1

func autoInlineLoopBody(value: s32)->s32 => incrementForInline(value)

func autoInlineLoopCaller(count: u32)->s32
{
    var total: s32
    for index in count
    {
        total += autoInlineLoopBody(cast(s32, index))
        total += autoInlineLoopBody(cast(s32, index + 1))
    }

    return total
}

#test
{
    Swag.assert(autoInlineLoopCaller(4) == 24)
}
