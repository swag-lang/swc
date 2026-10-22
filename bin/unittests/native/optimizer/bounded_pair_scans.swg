#global private

#[Swag.Optimize(true), Swag.NoInline]
func commonPrefix(left, right: const [*] u8, first, last: s64)->s64
{
    var index = first
    while index < last
    {
        if left[index] != right[index] do
            break
        index += 1
    }
    return index
}

#[Swag.Optimize(true), Swag.NoInline]
func equalPrefix(left, right: const [*] u8, first, last: u64)->u64
{
    var index = first
    while index < last
    {
        if left[index] == right[index] do
            break
        index += 1
    }
    return index
}

#test
{
    var left, right: [64] u8
    for i in left.count do
        left[i] = 128

    for length in 0's64 to 24
    {
        for first in 0's64 to length + 1
        {
            for match in first to length + 1
            {
                let expected = first > length ? first : (match < length ? match : length)
                for i in right.count do
                    right[i] = 128
                if match < length do
                    right[match] = 127
                Swag.assert(commonPrefix(cast(const [*] u8, &left), cast(const [*] u8, &right), first, length) == expected)

                for i in right.count do
                    right[i] = 127
                if match < length do
                    right[match] = 128
                Swag.assert(equalPrefix(cast(const [*] u8, &left), cast(const [*] u8, &right), cast(u64, first), cast(u64, length)) == cast(u64, expected))
            }
        }
    }
}
