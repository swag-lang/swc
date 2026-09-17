#global private

#[Swag.NoInline]
func add16(values: const [*]u16, index: u64)->u16
{
    let left = values[index]
    let sum  = left + #wrap values[index + 1]
    return sum < left ? 0xFFFF : sum
}

#[Swag.NoInline]
func add8(values: const [*]u8, index: u64)->u8
{
    let left = values[index]
    let sum  = left + #wrap values[index + 1]
    return sum < left ? 0xFF : sum
}

#test
{
    let values16 = [0'u16, 0, 1, 2, 0xFFFE, 1, 0xFFFF, 1, 0x8000, 0x8000]
    let results16 = [0'u16, 3, 0xFFFF, 0xFFFF, 0xFFFF]
    for result, index in results16 do
        Swag.assert(add16(&values16[0], index * 2) == result)

    let values8 = [0'u8, 1, 3, 4, 0xFE, 1, 0xFF, 1, 0x80, 0x80]
    let results8 = [1'u8, 7, 0xFF, 0xFF, 0xFF]
    for result, index in results8 do
        Swag.assert(add8(&values8[0], index * 2) == result)
}
