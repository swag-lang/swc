#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func addFive64(values: [*] u64, index: u64)
{
    values[index] = values[index] + 5
}

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func subtractFive32(values: [*] u32, index: u64)
{
    values[index] = values[index] - 5
}

#[Swag.NoInline]
func andMask64(values: [*] u64, index: u64)
{
    values[index] = values[index] & 0x7FFFFFFF
}

#[Swag.NoInline]
func xorMask8(values: [*] u8, index: u64)
{
    values[index] = values[index] ^ 0x80
}

#[Swag.NoInline]
func orMask16(values: [*] u16, index: u64)
{
    values[index] = values[index] | 0x4000
}

#test
{
    var values64: [4] u64 = [0, 1, 0x80000000, 0xFFFFFFFFFFFFFFFF]
    addFive64(&values64[0], 0)
    addFive64(&values64[0], 3)
    andMask64(&values64[0], 2)
    Swag.assert(values64[0] == 5 and values64[1] == 1 and values64[2] == 0 and values64[3] == 4)

    var values32: [4] u32 = [0, 5, 6, 0xFFFFFFFF]
    subtractFive32(&values32[0], 0)
    subtractFive32(&values32[0], 2)
    Swag.assert(values32[0] == 0xFFFFFFFB and values32[1] == 5 and values32[2] == 1 and values32[3] == 0xFFFFFFFF)

    var values8: [4] u8 = [0, 1, 0x80, 0xFF]
    xorMask8(&values8[0], 0)
    xorMask8(&values8[0], 3)
    Swag.assert(values8[0] == 0x80 and values8[1] == 1 and values8[2] == 0x80 and values8[3] == 0x7F)

    var values16: [4] u16 = [0, 1, 0x8000, 0xFFFF]
    orMask16(&values16[0], 0)
    orMask16(&values16[0], 2)
    Swag.assert(values16[0] == 0x4000 and values16[1] == 1 and values16[2] == 0xC000 and values16[3] == 0xFFFF)
}
