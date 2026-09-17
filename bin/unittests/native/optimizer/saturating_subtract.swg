#global private

#[Swag.NoInline]
func subtract(values: const [*]u32, index: u64)->u32
{
    let left  = values[index]
    let right = values[index + 1]
    return left < right ? 0 : left - right
}

#test
{
    let values = [0'u32, 0, 0, 1, 1, 0, 7, 12, 12, 7, 0xFFFFFFFF, 1, 1, 0xFFFFFFFF]
    let results = [0'u32, 0, 1, 0, 5, 0xFFFFFFFE, 0]
    for result, index in results do
        Swag.assert(subtract(&values[0], index * 2) == result)
}
