#global private

#[Swag.Optimize(true), Swag.NoInline]
func findSentinel(bytes: const [..] u8, first, last: u64)->u64
{
    var index = first
    while index < last
    {
        if bytes[index] == 128
        {
            break
        }
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
        if bytes[index] != 128
        {
            break
        }
        index += 1
    }
    return index
}

#test
{
    for length in 0_u64 to 33
    {
        for first in 0_u64 to length + 1
        {
            for match in first to length + 1
            {
                let expected = first > length ? first : (match < length ? match : length)
                var bytes: [64] u8
                for i in bytes.count
                {
                    bytes[i] = 127
                }
                if match < length
                {
                    bytes[match] = 128
                }
                Swag.require(findSentinel(bytes, first, length) == expected)

                for i in bytes.count
                {
                    bytes[i] = 128
                }
                if match < length
                {
                    bytes[match] = 127
                }
                Swag.require(skipSentinel(bytes, first, length) == expected)
            }
        }
    }
}
