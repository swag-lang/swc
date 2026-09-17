#global private

#[Swag.NoInline]
func orLowByte(values: [*] u64, index: u64)
{
    values[index] = values[index] | 0x40
}

#[Swag.NoInline]
func xorLowByte(values: [*] u64, index: u64)
{
    values[index] = values[index] ^ 0x80
}

#[Swag.NoInline]
func orSecondByte(values: [*] u64, index: u64)
{
    values[index] = values[index] | 0x4000
}

#test
{
    var values: [4] u64 = [0, 0xFFFFFFFFFFFFFFFF, 0x123456789ABC1EF0, 0x4000]
    orLowByte(&values[0], 0)
    xorLowByte(&values[0], 1)
    orSecondByte(&values[0], 2)
    orSecondByte(&values[0], 3)
    Swag.assert(values[0] == 0x40)
    Swag.assert(values[1] == 0xFFFFFFFFFFFFFF7F)
    Swag.assert(values[2] == 0x123456789ABC5EF0)
    Swag.assert(values[3] == 0x4000)
}
