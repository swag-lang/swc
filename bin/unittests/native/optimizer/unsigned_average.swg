#global private

#[Swag.NoInline]
func average(values: const [*]u32, index: u64)->u32
{
    let left  = values[index]
    let right = values[index + 1]
    return (left & right) + ((left ^ right) >> 1)
}

#test
{
    let values  = [0'u32, 0, 0, 1, 1, 2, 7, 12, 0xFFFFFFFF, 0xFFFFFFFF, 0, 0xFFFFFFFF]
    let results = [0'u32, 0, 1, 9, 0xFFFFFFFF, 0x7FFFFFFF]
    for result, index in results do
        Swag.assert(average(&values[0], index * 2) == result)
}
