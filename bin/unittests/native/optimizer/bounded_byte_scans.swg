#global private

#[Swag.Optimize(true), Swag.NoInline]
func findSentinel(bytes: const [..] u8, first, last: u64)->u64
{
    var index = first
    while index < last
    {
        if bytes[index] == 128 do
            break
        index += 1
    }
    return index
}

#[Swag.Optimize(true), Swag.NoInline]
func skipSentinel(bytes: const [..] u8, first, last: u64)->u64
{
    var index = first
    while index < last
    {
        if bytes[index] != 128 do
            break
        index += 1
    }
    return index
}

#test
{
    for length in 0'u64 to 33
    {
        for first in 0'u64 to length + 1
        {
            for match in first to length + 1
            {
                let expected = first > length ? first : (match < length ? match : length)
                var bytes: [64] u8
                for i in bytes.count do
                    bytes[i] = 127
                if match < length do
                    bytes[match] = 128
                Swag.assert(findSentinel(bytes, first, length) == expected)

                for i in bytes.count do
                    bytes[i] = 128
                if match < length do
                    bytes[match] = 127
                Swag.assert(skipSentinel(bytes, first, length) == expected)
            }
        }
    }
}
