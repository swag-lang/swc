#global private
#global #[Swag.Safety(.Overflow, false)]

#[Swag.NoInline]
func sumAtLeast(values: const [*] u32, count: u64, threshold: u32, seed: u64)->u64
{
    var total = seed
    for index in count
    {
        let value = values[index]
        if value >= threshold do
            total += value
    }

    return total
}

#test
{
    var values: [67] u32
    for &value, index in values
    {
        let low = cast(u32, index * 97)
        value[] = index % 3 == 0 ? low : 0xFFFF_FFFF'u32 - low
    }

    const Thresholds = [0'u32, 0x8000_0000'u32, 0xFFFF_FFFF'u32]
    const Seed = 0xFFFF_FFFF_FFFF_FFD0'u64
    for threshold in Thresholds
    {
        var expected = Seed
        for count in values.count + 1
        {
            Swag.require(sumAtLeast(&values[0], count, threshold, Seed) == expected)
            if count < values.count and values[count] >= threshold do
                expected += values[count]
        }
    }
}
