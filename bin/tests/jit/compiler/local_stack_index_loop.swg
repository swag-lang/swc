#global fileprivate

struct Box
{
    min: u32
    max: u32
}

func parseNumber(bytes: const [..] u8, index: *u32)->u32
{
    var result: u32
    while dref index < @countof(bytes) and bytes[dref index] >= '0' and bytes[dref index] <= '9'
    {
        result = result * 10'u32 + cast(u32) (bytes[dref index] - '0')
        dref index += 1
    }

    return result
}

#test
{
    let bytes = cast(const [..] u8) "3-5\n"

    var boxes: [16] Box
    var slot: u32
    var index: u32

    while index < @countof(bytes)
    {
        boxes[slot].min = parseNumber(bytes, &index)
        index += 1
        boxes[slot].max = parseNumber(bytes, &index)

        if index < @countof(bytes) and bytes[index] == '\n''u8 do
            index += 1
    }

    @assert(slot == 0'u32)
    @assert(index == 4'u32)
    @assert(boxes[0].min == 3'u32)
    @assert(boxes[0].max == 5'u32)
}
