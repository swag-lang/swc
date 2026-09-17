#global private

#[Swag.NoInline]
func subtract16(values: const [*]u16, index: u64)->u16
{
    let left  = values[index]
    let right = values[index + 1]
    return left < right ? 0 : left - right
}

#[Swag.NoInline]
func subtract16Expression(values: const [*]u16, index: u64)->u16 =>
    values[index] < values[index + 1] ? 0 : values[index] - values[index + 1]

#[Swag.NoInline]
func subtract8(values: const [*]u8, index: u64)->u8
{
    let left  = values[index]
    let right = values[index + 1]
    return left < right ? 0 : left - right
}

#[Swag.NoInline]
func subtract8Expression(values: const [*]u8, index: u64)->u8 =>
    values[index] < values[index + 1] ? 0 : values[index] - values[index + 1]

#test
{
    let values16  = [0'u16, 0, 0, 1, 1, 0, 7, 12, 12, 7, 0xFFFF, 1]
    let results16 = [0'u16, 0, 1, 0, 5, 0xFFFE]
    for result, index in results16
    {
        Swag.assert(subtract16(&values16[0], index * 2) == result)
        Swag.assert(subtract16Expression(&values16[0], index * 2) == result)
    }

    let values8  = [0'u8, 1, 1, 0, 7, 12, 12, 7, 0xFF, 1]
    let results8 = [0'u8, 1, 0, 5, 0xFE]
    for result, index in results8
    {
        Swag.assert(subtract8(&values8[0], index * 2) == result)
        Swag.assert(subtract8Expression(&values8[0], index * 2) == result)
    }
}
