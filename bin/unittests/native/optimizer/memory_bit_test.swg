#global private

#[Swag.NoInline]
func low(p: *u64, a, b: u64)->u64 => (p[] & 1) != 0 ? a : b
#[Swag.NoInline]
func mask(p: *u64, a, b: u64)->u64 => (p[] & 0x65) == 0 ? a : b
#[Swag.NoInline]
func word(p: *u32, a, b: u64)->u64 => (p[] & 3) != 0 ? a : b
#[Swag.NoInline]
func offset(p: [*]u64, a, b: u64)->u64 => (p[31] & 3) != 0 ? a : b
#[Swag.NoInline]
func shared(p: *u64, a, b: u64)->u64
{
    let value = p[]
    return ((value & 1) != 0 ? a : b) ^ value
}
#[Swag.NoInline]
func high(p: *u64, a, b: u64)->u64 => (p[] & 0x8000000000000000) != 0 ? a : b

#test
{
    let values = [0'u64, 1, 2, 3, 4, 0x40, 0x7F, 0x80, 0x100, 0x8000000000000000, 0xFFFFFFFFFFFFFFFF]
    var displaced: [32]u64
    for value in values
    {
        var cell = value
        var small = cast(u32) (value & 0xFFFFFFFF)
        displaced[31] = value
        Swag.assert(low(&cell, 17, 29) == ((value & 1) != 0 ? 17 : 29))
        Swag.assert(mask(&cell, 17, 29) == ((value & 0x65) == 0 ? 17 : 29))
        Swag.assert(word(&small, 17, 29) == ((value & 3) != 0 ? 17 : 29))
        Swag.assert(offset(&displaced[0], 17, 29) == ((value & 3) != 0 ? 17 : 29))
        Swag.assert(shared(&cell, 17, 29) == (((value & 1) != 0 ? 17'u64 : 29) ^ value))
        Swag.assert(high(&cell, 17, 29) == ((value & 0x8000000000000000) != 0 ? 17 : 29))
        Swag.assert(cell == value and displaced[31] == value)
    }
}
