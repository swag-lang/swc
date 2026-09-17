#global private

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func add64(values: [*] u64, index, value: u64)
{
    values[index] = values[index] + value
}

#[Swag.NoInline]
func xor32(values: [*] u32, index: u64, value: u32)
{
    values[index] = values[index] ^ value
}

#[Swag.NoInline, Swag.Safety(.Overflow, false)]
func subtract8(values: [*] u8, index: u64, value: u8)
{
    values[index] = values[index] - value
}

#test
{
    var values64: [4] u64 = [0, 1, 0x7FFFFFFFFFFFFFFF, 0xFFFFFFFFFFFFFFFF]
    add64(&values64[0], 0, 7)
    add64(&values64[0], 3, 2)
    Swag.assert(values64[0] == 7 and values64[1] == 1 and values64[2] == 0x7FFFFFFFFFFFFFFF and values64[3] == 1)

    var values32: [4] u32 = [0, 1, 0x80000000, 0xFFFFFFFF]
    xor32(&values32[0], 1, 0xFFFFFFFF)
    xor32(&values32[0], 2, 0x80000001)
    Swag.assert(values32[0] == 0 and values32[1] == 0xFFFFFFFE and values32[2] == 1 and values32[3] == 0xFFFFFFFF)

    var values8: [4] u8 = [0, 1, 127, 255]
    subtract8(&values8[0], 0, 1)
    subtract8(&values8[0], 3, 2)
    Swag.assert(values8[0] == 255 and values8[1] == 1 and values8[2] == 127 and values8[3] == 253)
}
