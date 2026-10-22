#global private

#[Swag.Optimize(true), Swag.NoInline]
func reversePrefix(items: [*] u64, last: s64)
{
    var left  = 0's64
    var right = last
    while left < right
    {
        let first = items[left]
        items[left]  = items[right]
        items[right] = first
        left  += 1
        right -= 1
    }
}

#test
{
    for length in 0'u64 to 48
    {
        var items: [64] u64
        for i in items.count do
            items[i] = i * 5 + 17
        reversePrefix(cast([*] u64, &items), cast(s64, length) - 1)
        for i in items.count
        {
            let source = i < length ? length - 1 - i : i
            Swag.assert(items[i] == source * 5 + 17)
        }
    }
}
