#global private

#[Swag.NoInline]
func average(values: const [*]u32, index: u64)->u32
{
    let left  = values[index]
    let right = values[index + 1]
    return (left | right) - ((left ^ right) >> 1)
}

#[Swag.NoInline]
func wideAverage(values: const [*]u64, index: u64)->u64
{
    let left  = values[index]
    let right = values[index + 1]
    return (left | right) - ((left ^ right) >> 1)
}

#test
{
    let values  = [0'u32, 0, 0, 1, 1, 2, 7, 12, 0xFFFFFFFF, 0xFFFFFFFF, 0, 0xFFFFFFFF]
    let results = [0'u32, 1, 2, 10, 0xFFFFFFFF, 0x80000000]
    for result, index in results do
        Swag.assert(average(&values[0], index * 2) == result)

    let wideValues = [0'u64, 0, 0, 1, 1, 2, 7, 12, 0xFFFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF,
                      0, 0xFFFFFFFFFFFFFFFF]
    let wideResults = [0'u64, 1, 2, 10, 0xFFFFFFFFFFFFFFFF, 0x8000000000000000]
    for result, index in wideResults do
        Swag.assert(wideAverage(&wideValues[0], index * 2) == result)
}
