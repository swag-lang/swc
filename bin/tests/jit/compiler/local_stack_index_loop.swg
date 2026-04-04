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

func bumpForIndex(index: &u32)
{
    index += 2'u32
}

func parseForDigit(bytes: const [..] u8, index: &u64)->u32
{
    let value = cast(u32) (bytes[index] - '0''u8)
    index += 2'u64
    return value
}

func parseForDigit32(bytes: const [..] u8, index: &u32)->u32
{
    let value = cast(u32) (bytes[index] - '0''u8)
    index += 2'u32
    return value
}

#test
{
    let bytes = cast(const [..] u8) "01234"
    var seen: u8
    for i in @countof(bytes)
    {
        if i == 1'u32
        {
            i += 2'u32
            seen = bytes[i]
            break
        }
    }

    @assert(seen == '3''u8)
}

#test
{
    let bytes = cast(const [..] u8) "01234"
    var seen: u8
    for i in @countof(bytes)
    {
        if i == 1'u32
        {
            bumpForIndex(&i)
            seen = bytes[i]
            break
        }
    }

    @assert(seen == '3''u8)
}

#test
{
    let bytes = cast(const [..] u8) "2a4b"
    for i in @countof(bytes)
    {
        let a = parseForDigit32(bytes, &i), b = parseForDigit32(bytes, &i)
        @assert(a == 2'u32)
        @assert(b == 4'u32)
        break
    }
}

#test
{
    func solveDigits(bytes: const [..] u8)->u32
    {
        for i in @countof(bytes)
        {
            let a = parseForDigit(bytes, &i), b = parseForDigit(bytes, &i)
            return a * 10'u32 + b
        }

        return 0'u32
    }

    let bytes = cast(const [..] u8) "2a4b"
    @assert(solveDigits(bytes) == 24'u32)
}
