#global private

#[Swag.NoInline]
func multiplyAdd6(value, addend: u64)->u64 => value * 6 + addend

#[Swag.NoInline]
func multiplyAdd10(value, addend: u64)->u64 => addend + value * 10

#[Swag.NoInline]
func multiplyAdd72(value, addend: u64)->u64 => value * 72 + addend

#test
{
    Swag.assert(multiplyAdd6(7, 3) == 45)
    Swag.assert(multiplyAdd10(7, 3) == 73)
    Swag.assert(multiplyAdd72(7, 3) == 507)
    Swag.assert(multiplyAdd6(0, 123) == 123)
    Swag.assert(multiplyAdd10(123, 0) == 1230)
    Swag.assert(multiplyAdd72(0, 0) == 0)

    // High bits must survive both the scaled address and the accumulator copy.
    let value  = 0x123456789ABCDE'u64
    let addend = 0xFEDCBA987654321'u64
    Swag.assert(multiplyAdd6(value, addend) == 0x105B05B05B05B055'u64)
    Swag.assert(multiplyAdd10(value, addend) == 0x10A3D70A3D70A3CD'u64)
    Swag.assert(multiplyAdd72(value, addend) == 0x150C83FB72EA6191'u64)
}
