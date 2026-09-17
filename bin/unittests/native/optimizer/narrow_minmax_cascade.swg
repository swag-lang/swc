#global private

#[Swag.NoInline]
func minimum16(values: const [*]u16, index: u64)->u16 => Swag.min(values[index], Swag.min(values[index + 1], values[index + 2]))

#[Swag.NoInline]
func maximum16(values: const [*]u16, index: u64)->u16 => Swag.max(values[index], Swag.max(values[index + 1], values[index + 2]))

#[Swag.NoInline]
func minimum8(values: const [*]u8, index: u64)->u8 => Swag.min(values[index], Swag.min(values[index + 1], values[index + 2]))

#[Swag.NoInline]
func maximum8(values: const [*]u8, index: u64)->u8 => Swag.max(values[index], Swag.max(values[index + 1], values[index + 2]))

#test
{
    let values16 = [9'u16, 4, 7, 0, 0xFFFF, 23, 8, 8, 8]
    Swag.assert(minimum16(&values16[0], 0) == 4)
    Swag.assert(maximum16(&values16[0], 0) == 9)
    Swag.assert(minimum16(&values16[0], 3) == 0)
    Swag.assert(maximum16(&values16[0], 3) == 0xFFFF)
    Swag.assert(minimum16(&values16[0], 6) == 8)
    Swag.assert(maximum16(&values16[0], 6) == 8)

    let values8 = [9'u8, 4, 7, 0, 0xFF, 23]
    Swag.assert(minimum8(&values8[0], 0) == 4)
    Swag.assert(maximum8(&values8[0], 0) == 9)
    Swag.assert(minimum8(&values8[0], 3) == 0)
    Swag.assert(maximum8(&values8[0], 3) == 0xFF)
}
