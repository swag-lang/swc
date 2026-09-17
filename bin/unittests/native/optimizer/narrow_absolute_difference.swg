#global private

#[Swag.NoInline]
func difference16(values: const [*]u16, index: u64)->u16
{
    let left  = values[index]
    let right = values[index + 1]
    return left < right ? right - left : left - right
}

#[Swag.NoInline]
func difference8(values: const [*]u8, index: u64)->u8
{
    let left  = values[index]
    let right = values[index + 1]
    return left < right ? right - left : left - right
}

#test
{
    let values16 = [0'u16, 0, 0, 1, 1, 0, 7, 12, 12, 7, 0, 0xFFFF]
    let results16 = [0'u16, 1, 1, 5, 5, 0xFFFF]
    for result, index in results16 do
        Swag.assert(difference16(&values16[0], index * 2) == result)

    let values8 = [0'u8, 1, 1, 0, 7, 12, 12, 7, 0, 0xFF]
    let results8 = [1'u8, 1, 5, 5, 0xFF]
    for result, index in results8 do
        Swag.assert(difference8(&values8[0], index * 2) == result)
}
