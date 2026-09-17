#global private

#[Swag.NoInline]
func rotate(values: const [*]u16, index: u64)->u16 => Swag.rol(values[index], 5)

#[Swag.NoInline]
func byteSwap(values: const [*]u16, index: u64)->u16 => Swag.byteSwap(values[index])

#[Swag.NoInline]
func rotateDirect(value: *u16)->u16 => Swag.ror(value[], 3)

#test
{
    let values = [0'u16, 1, 0x1234, 0x8001, 0xFFFF]
    for value, index in values
    {
        Swag.assert(rotate(&values[0], index) == Swag.rol(value, 5))
        Swag.assert(byteSwap(&values[0], index) == Swag.byteSwap(value))
        Swag.assert(rotateDirect(&values[index]) == Swag.ror(value, 3))
    }
}
