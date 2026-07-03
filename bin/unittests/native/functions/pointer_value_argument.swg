#global private

struct PointerValueArgumentPayload
{
    x: s32
    y: s32
}

func readPointerValueArgument(value: PointerValueArgumentPayload)->s32
{
    return value.x * 10 + value.y
}

#test
{
    var value = PointerValueArgumentPayload{x: 4, y: 7}
    let ptr = &value

    @assert(readPointerValueArgument(ptr) == 47)
}
