#global private

#[Swag.NoInline]
func replay(values: [*] u8, start, distance, count: u64)
{
    var output = start
    for count
    {
        values[output] = values[output - distance]
        output         += 1
    }
}

#[Swag.NoInline, Swag.Optimize(false)]
func referenceReplay(values: [*] u8, start, distance, count: u64)
{
    var output = start
    for count
    {
        values[output] = values[output - distance]
        output         += 1
    }
}

#test
{
    for distance in [1'u64, 2, 3, 7, 16, 32]
    {
        for count in [0'u64, 1, 2, 7, 31, 32, 64]
        {
            var actual, expected: [128] u8
            for i in 128
            {
                actual[i]   = cast(u8, i + 1)
                expected[i] = actual[i]
            }

            replay(&actual[0], 32, distance, count)
            referenceReplay(&expected[0], 32, distance, count)
            Swag.assert(actual == expected)
        }
    }
}
