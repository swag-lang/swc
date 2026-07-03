#global private

func wideNumericArraySum() -> u64
{
    let values = [1, 5_000_000_000]
    #assert(#typeof(values[0]) == s64)
    #assert(#typeof(values[1]) == s64)

    var total: u64 = 0
    foreach value in values
    {
        total += cast(u64) value
    }

    return total
}

func wideNumericArrayMiddle() -> u64
{
    let values = [7, 5_000_000_000, 11]
    return cast(u64) values[1]
}

#test
{
    @assert(wideNumericArraySum() == 5_000_000_001)
    @assert(wideNumericArrayMiddle() == 5_000_000_000)
}
