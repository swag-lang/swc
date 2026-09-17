#global private

#[Swag.NoInline]
func median16(values: const [*]u16, index: u64)->u16
{
    let a = values[index]
    let b = values[index + 1]
    let c = values[index + 2]
    return Swag.max(Swag.min(a, b), Swag.min(Swag.max(a, b), c))
}

#[Swag.NoInline]
func median8(values: const [*]u8, index: u64)->u8
{
    let a = values[index]
    let b = values[index + 1]
    let c = values[index + 2]
    return Swag.max(Swag.min(a, b), Swag.min(Swag.max(a, b), c))
}

#test
{
    let values16 = [1'u16, 2, 3, 3, 2, 1, 2, 1, 3, 0, 0xFFFF, 17, 8, 8, 9]
    let results16 = [2'u16, 2, 2, 17, 8]
    for result, index in results16 do
        Swag.assert(median16(&values16[0], index * 3) == result)

    let values8 = [1'u8, 3, 2, 0xFF, 0, 17, 8, 8, 9]
    let results8 = [2'u8, 17, 8]
    for result, index in results8 do
        Swag.assert(median8(&values8[0], index * 3) == result)
}
